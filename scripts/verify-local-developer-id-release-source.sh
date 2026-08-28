#!/bin/zsh

set -euo pipefail

fail() {
  print -u2 "Local Developer ID release source verification failed: $*"
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${(P)name:-}" ]] || fail "missing environment variable ${name}"
}

for required_name in VERSION BUILD_NUMBER TAG; do
  require_value "$required_name"
done

script_dir="${0:A:h}"
repository_root="${script_dir:h}"
plist="$repository_root/prototype/GodoxMacControlPrototype/Info.plist"
prototype_makefile="$repository_root/prototype/GodoxMacControlPrototype/Makefile"
expected_repository="loomitz/estrobo"
expected_arm_check="macOS 15 (arm64)"
expected_intel_check="macOS 15 (x86_64)"
expected_github_actions_app_id="15368"
git_command="${GIT_COMMAND:-/usr/bin/git}"
build_input_paths=(
  prototype/GodoxMacControlPrototype/Sources
  prototype/GodoxMacControlPrototype/Resources
  prototype/GodoxBLEPoC/Sources
)

if [[ -n "${GH_COMMAND:-}" ]]; then
  gh_command="$GH_COMMAND"
else
  gh_command="$(command -v gh 2>/dev/null)" || fail "GitHub CLI is not installed"
fi

[[ -x "$git_command" ]] || fail "GIT_COMMAND is not executable"
[[ -x "$gh_command" ]] || fail "GH_COMMAND is not executable"
[[ -r "$plist" ]] || fail "prototype Info.plist is missing"
[[ -r "$prototype_makefile" ]] || fail "prototype Makefile is missing"

cd "$repository_root" || fail "could not enter the repository root"

inside_worktree="$("$git_command" rev-parse --is-inside-work-tree 2>/dev/null)" || \
  fail "repository root is not a Git worktree"
[[ "$inside_worktree" == true ]] || fail "repository root is not a Git worktree"

bare_repository="$("$git_command" rev-parse --is-bare-repository 2>/dev/null)" || \
  fail "could not inspect the Git worktree"
[[ "$bare_repository" == false ]] || fail "bare repositories cannot produce a local release"

git_top_level="$("$git_command" rev-parse --show-toplevel 2>/dev/null)" || \
  fail "could not resolve the Git worktree root"
[[ "${git_top_level:A}" == "${repository_root:A}" ]] || \
  fail "script is not running from its owning Git worktree"

origin_url="$("$git_command" remote get-url origin 2>/dev/null)" || fail "origin is not configured"
case "$origin_url" in
  git@github.com:loomitz/estrobo.git|\
  ssh://git@github.com/loomitz/estrobo.git|\
  ssh://git@github.com/loomitz/estrobo|\
  https://github.com/loomitz/estrobo.git|\
  https://github.com/loomitz/estrobo)
    ;;
  *)
    fail "origin does not identify the canonical GitHub repository"
    ;;
esac

verify_clean_worktree() {
  local status_output
  status_output="$("$git_command" status --porcelain=v1 --untracked-files=all)" || \
    fail "could not inspect Git worktree status"
  if [[ -n "$status_output" ]]; then
    print -u2 -- "$status_output"
    fail "Git worktree contains tracked or untracked changes"
  fi
}

verify_no_ignored_build_inputs() {
  local ignored_build_inputs
  ignored_build_inputs="$(
    "$git_command" ls-files --others --ignored --exclude-standard -- \
      "${build_input_paths[@]}"
  )" || fail "could not inspect ignored release build inputs"
  if [[ -n "$ignored_build_inputs" ]]; then
    print -u2 -- "$ignored_build_inputs"
    fail "ignored files are present in release build inputs"
  fi
}

read_make_default() {
  local variable_name="$1"
  local value
  value="$(
    /usr/bin/awk -v variable_name="$variable_name" '
      $1 == variable_name && $2 == "?=" {
        $1 = ""
        $2 = ""
        sub(/^[[:space:]]+/, "")
        print
      }
    ' "$prototype_makefile"
  )" || fail "could not read ${variable_name} from the prototype Makefile"
  [[ -n "$value" && "$value" != *$'\n'* ]] || \
    fail "prototype Makefile must declare exactly one ${variable_name} default"
  print -r -- "$value"
}

verify_required_check() {
  local expected_name="$1"
  local matching_rows
  local check_name
  local check_status
  local check_conclusion
  local check_sha
  local check_app_id

  matching_rows="$(
    print -r -- "$check_rows" |
      /usr/bin/awk -F '\t' -v expected_name="$expected_name" '$1 == expected_name { print }'
  )"
  [[ -n "$matching_rows" ]] || fail "required CI check is missing for HEAD: $expected_name"

  while IFS=$'\t' read -r check_name check_status check_conclusion check_sha check_app_id; do
    [[ "$check_name" == "$expected_name" ]] || fail "received an unexpected CI check record"
    [[ "$check_status" == completed && "$check_conclusion" == success ]] || \
      fail "required CI check is not green for HEAD: $expected_name"
    [[ "$check_sha" == "$head_commit" ]] || \
      fail "required CI check refers to a different commit: $expected_name"
    [[ "$check_app_id" == "$expected_github_actions_app_id" ]] || \
      fail "required CI check was not produced by the protected GitHub Actions app: $expected_name"
  done <<< "$matching_rows"
}

verify_protected_context() {
  local expected_name="$1"
  local matching_rows
  local context_name
  local app_id

  matching_rows="$(
    print -r -- "$protected_check_rows" |
      /usr/bin/awk -F '\t' -v expected_name="$expected_name" '$1 == expected_name { print }'
  )"
  [[ -n "$matching_rows" ]] || fail "main no longer requires CI check: $expected_name"

  while IFS=$'\t' read -r context_name app_id; do
    [[ "$context_name" == "$expected_name" ]] || fail "received an unexpected branch protection record"
    [[ "$app_id" == "$expected_github_actions_app_id" ]] || \
      fail "main no longer binds required check to GitHub Actions: $expected_name"
  done <<< "$matching_rows"
}

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || \
  fail "VERSION must use numeric major.minor.patch format"
[[ "$BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]] || fail "BUILD_NUMBER must be a positive integer"
expected_tag="v${VERSION}-beta.${BUILD_NUMBER}"
[[ "$TAG" == "$expected_tag" ]] || fail "TAG does not match VERSION and BUILD_NUMBER"

plist_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>/dev/null)" || \
  fail "could not read CFBundleShortVersionString"
plist_build_number="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$plist" 2>/dev/null)" || \
  fail "could not read CFBundleVersion"
[[ "$plist_version" == "$VERSION" ]] || fail "VERSION does not match Info.plist"
[[ "$plist_build_number" == "$BUILD_NUMBER" ]] || fail "BUILD_NUMBER does not match Info.plist"

make_version="$(read_make_default VERSION)"
make_build_number="$(read_make_default BUILD_NUMBER)"
make_tag_template="$(read_make_default TAG)"
[[ "$make_version" == "$VERSION" ]] || fail "VERSION does not match the prototype Makefile"
[[ "$make_build_number" == "$BUILD_NUMBER" ]] || \
  fail "BUILD_NUMBER does not match the prototype Makefile"
[[ "$make_tag_template" == 'v$(VERSION)-beta.$(BUILD_NUMBER)' ]] || \
  fail "prototype Makefile TAG no longer derives from VERSION and BUILD_NUMBER"

verify_clean_worktree
verify_no_ignored_build_inputs

"$git_command" fetch --prune --no-tags origin \
  '+refs/heads/main:refs/remotes/origin/main' >/dev/null || \
  fail "could not fetch the canonical origin/main"

head_commit="$("$git_command" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || \
  fail "could not resolve HEAD"
origin_main_commit="$("$git_command" rev-parse --verify 'refs/remotes/origin/main^{commit}' 2>/dev/null)" || \
  fail "could not resolve origin/main after fetch"
[[ "$head_commit" =~ '^[0-9a-f]{40}$' ]] || fail "HEAD is not a full lowercase commit SHA"
[[ "$origin_main_commit" == "$head_commit" ]] || fail "HEAD is not exactly the fetched origin/main"

local_tag_status=0
"$git_command" show-ref --verify --quiet "refs/tags/$TAG" || local_tag_status=$?
case "$local_tag_status" in
  0)
    fail "release tag already exists locally"
    ;;
  1)
    ;;
  *)
    fail "could not prove that the release tag is absent locally"
    ;;
esac

remote_tag_status=0
"$git_command" ls-remote --exit-code --refs origin "refs/tags/$TAG" >/dev/null 2>&1 || \
  remote_tag_status=$?
case "$remote_tag_status" in
  0)
    fail "release tag already exists on origin"
    ;;
  2)
    ;;
  *)
    fail "could not prove that the release tag is absent from origin"
    ;;
esac

"$gh_command" auth status --hostname github.com >/dev/null 2>&1 || \
  fail "GitHub CLI authentication is not valid"

check_rows="$(
  "$gh_command" api --paginate \
    "repos/$expected_repository/commits/$head_commit/check-runs?filter=latest&per_page=100" \
    --jq '.check_runs[] | [.name, .status, (.conclusion // ""), .head_sha, ((.app.id // 0) | tostring)] | @tsv'
)" || fail "could not inspect CI checks for HEAD"
[[ -n "$check_rows" ]] || fail "HEAD has no GitHub check runs"
verify_required_check "$expected_arm_check"
verify_required_check "$expected_intel_check"

protection_strict="$(
  "$gh_command" api "repos/$expected_repository/branches/main/protection" \
    --jq '.required_status_checks.strict // false'
)" || fail "could not inspect main branch protection"
[[ "$protection_strict" == true ]] || fail "main branch protection no longer requires an up-to-date branch"

protected_check_rows="$(
  "$gh_command" api "repos/$expected_repository/branches/main/protection" \
    --jq '.required_status_checks.checks[] | [.context, ((.app_id // 0) | tostring)] | @tsv'
)" || fail "could not inspect required main checks"
[[ -n "$protected_check_rows" ]] || fail "main branch protection has no required checks"
verify_protected_context "$expected_arm_check"
verify_protected_context "$expected_intel_check"

final_head_commit="$("$git_command" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || \
  fail "could not reconfirm HEAD"
[[ "$final_head_commit" == "$head_commit" ]] || fail "HEAD changed during source verification"
verify_clean_worktree
verify_no_ignored_build_inputs

print "Local Developer ID release source verified: $head_commit ($TAG)"
