#!/bin/zsh

set -euo pipefail

app_bundle="${1:-Build/estrobo.app}"
source_executable="$app_bundle/Contents/MacOS/estrobo"

if [[ ! -x "$source_executable" ]]; then
    print -u2 "App executable not found: $source_executable"
    exit 1
fi

temporary_root=$(/usr/bin/mktemp -d /tmp/estrobo-launch-check.XXXXXX)
isolated_bundle_id="mx.loo.estrobo.launchcheck.$$"
container_root="${CFFIXED_USER_HOME:-${HOME:?}}/Library/Containers"
isolated_container="$container_root/$isolated_bundle_id"
isolated_app="$temporary_root/EstroboLaunchCheck.app"
app_executable="$isolated_app/Contents/MacOS/estrobo"
launch_log="$temporary_root/launch.log"
isolated_home="$temporary_root/home"
source_entitlements="$temporary_root/source-entitlements.plist"
app_pid=""

/bin/mkdir -p "$isolated_home"
/usr/bin/codesign -d --entitlements :- "$app_bundle" \
    >"$source_entitlements" 2>/dev/null
# Reuse the updater's exact host contract; the development app is thin, so
# distribution/universal verification remains in its dedicated release checks.
python3 - "$source_entitlements" "${0:A:h}/../../../scripts/macos-updater-artifacts.py" <<'PYVERIFY'
import pathlib, plistlib, runpy, sys
actual = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
expected = runpy.run_path(sys.argv[2])["HOST_ENTITLEMENTS"]
if actual != expected:
    raise SystemExit("The built Estrobo app does not have the exact updater entitlement contract")
PYVERIFY

/usr/bin/ditto "$app_bundle" "$isolated_app"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $isolated_bundle_id" \
    "$isolated_app/Contents/Info.plist"
# The source and its precise embedded components use development ad hoc signing
# without Hardened Runtime. Re-sign only the renamed outer harness, intentionally
# without Sandbox entitlements. Developer ID distribution verification is separate.
/usr/bin/codesign --force --sign - \
    --options 0 \
    "$isolated_app" >/dev/null
/usr/bin/codesign --verify --strict "$isolated_app"

cleanup() {
    if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill -TERM "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    /bin/rm -rf -- "$temporary_root"
}
trap cleanup EXIT INT TERM

CFFIXED_USER_HOME="$isolated_home" \
    "$app_executable" --mock-radio >"$launch_log" 2>&1 &
app_pid=$!

for _ in {1..20}; do
    if kill -0 "$app_pid" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

sleep 1

if ! kill -0 "$app_pid" 2>/dev/null; then
    wait "$app_pid" 2>/dev/null || app_status=$?
    print -u2 "Estrobo exited during launch responsiveness setup (status ${app_status:-unknown})"
    if [[ -s "$launch_log" ]]; then
        /bin/cat "$launch_log" >&2
    fi
    exit 1
fi

response=""
last_error=""
for _ in {1..20}; do
    if response=$(osascript \
        -e 'with timeout of 3 seconds' \
        -e "tell application id \"$isolated_bundle_id\" to activate" \
        -e 'return "responsive"' \
        -e 'end timeout' 2>&1); then
        break
    fi
    last_error="$response"
    response=""
    if ! kill -0 "$app_pid" 2>/dev/null; then
        break
    fi
    sleep 0.15
done

if [[ "$response" != "responsive" ]]; then
    print -u2 "Estrobo launch responsiveness check failed: ${last_error:-$response}"
    exit 1
fi

if [[ -e "$isolated_container" ]]; then
    print -u2 "The unsandboxed launch harness unexpectedly created a persistent container: $isolated_container"
    exit 1
fi

print "An isolated, unsandboxed Estrobo harness launched in mock mode and handled an activation AppleEvent without creating a persistent container"
