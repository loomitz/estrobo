#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "Local Developer ID release source test failed: $*"
  exit 1
}

script_dir="${0:A:h}"
source_verifier="$script_dir/verify-local-developer-id-release-source.sh"
[[ -x "$source_verifier" ]] || fail "source verifier is missing or not executable"

temporary_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/estrobo-local-release-source-test.XXXXXX")"
trap '/bin/rm -rf -- "$temporary_dir"' EXIT

fixture_root="$temporary_dir/fixture"
fixture_script_dir="$fixture_root/scripts"
fixture_prototype_dir="$fixture_root/prototype/GodoxMacControlPrototype"
/bin/mkdir -p "$fixture_script_dir" "$fixture_prototype_dir"
/bin/cp "$source_verifier" "$fixture_script_dir/verify-local-developer-id-release-source.sh"
/bin/chmod 755 "$fixture_script_dir/verify-local-developer-id-release-source.sh"

fixture_plist="$fixture_prototype_dir/Info.plist"
/usr/bin/plutil -create xml1 "$fixture_plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 0.1.0 "$fixture_plist"
/usr/bin/plutil -insert CFBundleVersion -string 4 "$fixture_plist"

/usr/bin/printf '%s\n' \
  'SHELL := /bin/zsh' \
  'VERSION ?= 0.1.0' \
  'BUILD_NUMBER ?= 4' \
  'TAG ?= v$(VERSION)-beta.$(BUILD_NUMBER)' \
  >"$fixture_prototype_dir/Makefile"

fake_git="$temporary_dir/fake-git"
/bin/cat >"$fake_git" <<'FAKE_GIT'
#!/bin/zsh

set -euo pipefail

state_dir="${FAKE_STATE_DIR:?}"
repository_root="${FAKE_REPOSITORY_ROOT:?}"
head_sha="${FAKE_HEAD_SHA:-1111111111111111111111111111111111111111}"
origin_sha="${FAKE_ORIGIN_SHA:-$head_sha}"
final_head_sha="${FAKE_FINAL_HEAD_SHA:-2222222222222222222222222222222222222222}"
/bin/mkdir -p "$state_dir"

case "${1:-}" in
  rev-parse)
    case "${2:-}" in
      --is-inside-work-tree)
        print true
        ;;
      --is-bare-repository)
        print false
        ;;
      --show-toplevel)
        print -r -- "$repository_root"
        ;;
      --verify)
        case "${3:-}" in
          'HEAD^{commit}')
            head_count=0
            if [[ -f "$state_dir/head.count" ]]; then
              head_count="$(<"$state_dir/head.count")"
            fi
            head_count="$((head_count + 1))"
            print -r -- "$head_count" >"$state_dir/head.count"
            if [[ "${FAKE_FINAL_HEAD_CHANGE:-0}" == 1 && "$head_count" -ge 2 ]]; then
              print -r -- "$final_head_sha"
            else
              print -r -- "$head_sha"
            fi
            ;;
          'refs/remotes/origin/main^{commit}')
            print -r -- "$origin_sha"
            ;;
          *)
            print -u2 "unexpected rev-parse ref: ${3:-}"
            exit 64
            ;;
        esac
        ;;
      *)
        print -u2 "unexpected rev-parse arguments: $*"
        exit 64
        ;;
    esac
    ;;
  remote)
    [[ "${2:-}" == get-url && "${3:-}" == origin ]] || exit 64
    print 'git@github.com:loomitz/estrobo.git'
    ;;
  status)
    if [[ "${FAKE_DIRTY_WORKTREE:-0}" == 1 ]]; then
      print '?? synthetic-untracked.txt'
    fi
    ;;
  ls-files)
    if [[ "${FAKE_IGNORED_BUILD_INPUT:-0}" == 1 ]]; then
      print 'prototype/GodoxMacControlPrototype/Resources/.env'
    fi
    ;;
  fetch)
    fetch_count=0
    if [[ -f "$state_dir/fetch.count" ]]; then
      fetch_count="$(<"$state_dir/fetch.count")"
    fi
    print -r -- "$((fetch_count + 1))" >"$state_dir/fetch.count"
    ;;
  show-ref)
    if [[ "${FAKE_LOCAL_TAG_EXISTS:-0}" == 1 ]]; then
      exit 0
    fi
    exit 1
    ;;
  ls-remote)
    if [[ "${FAKE_REMOTE_TAG_EXISTS:-0}" == 1 ]]; then
      print 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/tags/v0.1.0-beta.4'
      exit 0
    fi
    exit 2
    ;;
  *)
    print -u2 "unexpected fake Git invocation: $*"
    exit 64
    ;;
esac
FAKE_GIT
/bin/chmod 755 "$fake_git"

fake_gh="$temporary_dir/fake-gh"
/bin/cat >"$fake_gh" <<'FAKE_GH'
#!/bin/zsh

set -euo pipefail

head_sha="${FAKE_HEAD_SHA:-1111111111111111111111111111111111111111}"
actions_app_id=15368

case "${1:-}" in
  auth)
    [[ "${2:-}" == status ]] || exit 64
    exit 0
    ;;
  api)
    invocation="$*"
    if [[ "$invocation" == *'/check-runs?'* ]]; then
      check_mode="${FAKE_CHECK_MODE:-success}"
      arm_conclusion=success
      intel_conclusion=success
      arm_app_id="$actions_app_id"
      intel_app_id="$actions_app_id"
      case "$check_mode" in
        success)
          ;;
        missing-intel)
          ;;
        failed-arm)
          arm_conclusion=failure
          ;;
        wrong-arm-app)
          arm_app_id=99999
          ;;
        *)
          print -u2 "unknown fake check mode: $check_mode"
          exit 64
          ;;
      esac
      print -r -- "macOS 15 (arm64)"$'\t'"completed"$'\t'"${arm_conclusion}"$'\t'"${head_sha}"$'\t'"${arm_app_id}"
      if [[ "$check_mode" != missing-intel ]]; then
        print -r -- "macOS 15 (x86_64)"$'\t'"completed"$'\t'"${intel_conclusion}"$'\t'"${head_sha}"$'\t'"${intel_app_id}"
      fi
      exit 0
    fi

    if [[ "$invocation" == *'.required_status_checks.strict'* ]]; then
      print -r -- "${FAKE_PROTECTION_STRICT:-true}"
      exit 0
    fi

    if [[ "$invocation" == *'.required_status_checks.checks[]'* ]]; then
      protection_app_id="${FAKE_PROTECTION_APP_ID:-$actions_app_id}"
      print -r -- "macOS 15 (arm64)"$'\t'"${protection_app_id}"
      print -r -- "macOS 15 (x86_64)"$'\t'"${protection_app_id}"
      exit 0
    fi

    print -u2 "unexpected fake GitHub API invocation: $invocation"
    exit 64
    ;;
  *)
    print -u2 "unexpected fake GitHub invocation: $*"
    exit 64
    ;;
esac
FAKE_GH
/bin/chmod 755 "$fake_gh"

head_sha=1111111111111111111111111111111111111111

run_case() {
  local case_name="$1"
  shift
  local state_dir="$temporary_dir/state-$case_name"
  local output_path="$temporary_dir/output-$case_name.txt"
  local case_status=0
  /bin/mkdir -p "$state_dir"

  /usr/bin/env -i \
    PATH=/usr/bin:/bin \
    TMPDIR="${TMPDIR:-/tmp}" \
    VERSION=0.1.0 \
    BUILD_NUMBER=4 \
    TAG=v0.1.0-beta.4 \
    GIT_COMMAND="$fake_git" \
    GH_COMMAND="$fake_gh" \
    FAKE_STATE_DIR="$state_dir" \
    FAKE_REPOSITORY_ROOT="$fixture_root" \
    FAKE_HEAD_SHA="$head_sha" \
    "$@" \
    "$fixture_script_dir/verify-local-developer-id-release-source.sh" \
      >"$output_path" 2>&1 || case_status=$?

  print -r -- "$case_status" >"$state_dir/case.status"
  print -r -- "$output_path"
}

expect_success() {
  local case_name="$1"
  shift
  local output_path
  local case_status
  output_path="$(run_case "$case_name" "$@")"
  case_status="$(<"$temporary_dir/state-$case_name/case.status")"
  if [[ "$case_status" -ne 0 ]]; then
    /bin/cat "$output_path" >&2
    fail "success case '$case_name' exited with status $case_status"
  fi
  /usr/bin/grep -Fq \
    "Local Developer ID release source verified: $head_sha (v0.1.0-beta.4)" \
    "$output_path" || fail "success case '$case_name' omitted its verification result"
}

expect_failure() {
  local case_name="$1"
  local expected_message="$2"
  shift 2
  local output_path
  local case_status
  output_path="$(run_case "$case_name" "$@")"
  case_status="$(<"$temporary_dir/state-$case_name/case.status")"
  if [[ "$case_status" -eq 0 ]]; then
    /bin/cat "$output_path" >&2
    fail "unsafe case '$case_name' was accepted"
  fi
  if ! /usr/bin/grep -Fq -- "$expected_message" "$output_path"; then
    /bin/cat "$output_path" >&2
    fail "case '$case_name' failed for an unexpected reason"
  fi
}

expect_success success

expect_failure dirty-worktree \
  'Git worktree contains tracked or untracked changes' \
  FAKE_DIRTY_WORKTREE=1
[[ ! -e "$temporary_dir/state-dirty-worktree/fetch.count" ]] || \
  fail "dirty worktree reached Git fetch"

expect_failure ignored-build-input \
  'ignored files are present in release build inputs' \
  FAKE_IGNORED_BUILD_INPUT=1
[[ ! -e "$temporary_dir/state-ignored-build-input/fetch.count" ]] || \
  fail "ignored build input reached Git fetch"

expect_failure head-not-origin-main \
  'HEAD is not exactly the fetched origin/main' \
  FAKE_ORIGIN_SHA=3333333333333333333333333333333333333333

expect_failure local-tag-exists \
  'release tag already exists locally' \
  FAKE_LOCAL_TAG_EXISTS=1

expect_failure remote-tag-exists \
  'release tag already exists on origin' \
  FAKE_REMOTE_TAG_EXISTS=1

expect_failure missing-required-check \
  'required CI check is missing for HEAD: macOS 15 (x86_64)' \
  FAKE_CHECK_MODE=missing-intel

expect_failure failed-required-check \
  'required CI check is not green for HEAD: macOS 15 (arm64)' \
  FAKE_CHECK_MODE=failed-arm

expect_failure wrong-check-app-id \
  'required CI check was not produced by the protected GitHub Actions app: macOS 15 (arm64)' \
  FAKE_CHECK_MODE=wrong-arm-app

expect_failure non-strict-protection \
  'main branch protection no longer requires an up-to-date branch' \
  FAKE_PROTECTION_STRICT=false

expect_failure wrong-protection-app-id \
  'main no longer binds required check to GitHub Actions: macOS 15 (arm64)' \
  FAKE_PROTECTION_APP_ID=99999

expect_failure head-changed-during-verification \
  'HEAD changed during source verification' \
  FAKE_FINAL_HEAD_CHANGE=1

print "Local Developer ID release source tests passed"
