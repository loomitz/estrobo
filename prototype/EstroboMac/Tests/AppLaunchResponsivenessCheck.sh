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
entitlement_count=$(
    /usr/bin/plutil -p "$source_entitlements" | /usr/bin/grep -c '=>'
)
if [[ "$entitlement_count" != "2" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$source_entitlements")" != "true" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.bluetooth' "$source_entitlements")" != "true" ]]; then
    print -u2 "The built Estrobo app does not have the exact Sandbox + Bluetooth entitlement contract"
    exit 1
fi

/usr/bin/ditto "$app_bundle" "$isolated_app"
/usr/libexec/PlistBuddy \
    -c "Set :CFBundleIdentifier $isolated_bundle_id" \
    "$isolated_app/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - \
    --options runtime \
    "$isolated_app" >/dev/null

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
