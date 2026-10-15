#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repository_root=${script_dir:h}
ios_dir="$repository_root/ios"
project_path="$ios_dir/EstroboIOS.xcodeproj"

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "error: XcodeGen is required. Install XcodeGen 2.46.0 and run make ios-project again."
    exit 1
fi

xcodegen_version=$(xcodegen --version | awk '{ print $NF }')
if [[ "$xcodegen_version" != "2.46.0" ]]; then
    print -u2 "error: expected XcodeGen 2.46.0, found $xcodegen_version."
    exit 1
fi

if [[ ! -f "$ios_dir/project.yml" ]]; then
    print -u2 "error: missing $ios_dir/project.yml."
    exit 1
fi

print "Generating $project_path with XcodeGen $xcodegen_version"
(
    cd "$ios_dir"
    xcodegen generate --spec project.yml
)

if [[ ! -d "$project_path" ]]; then
    print -u2 "error: XcodeGen did not create $project_path."
    exit 1
fi

print "Generated: $project_path"
