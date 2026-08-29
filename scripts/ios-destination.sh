#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repository_root=${script_dir:h}
project_path="$repository_root/ios/EstroboIOS.xcodeproj"
scheme=EstroboIOS
family=${1:-}

case "$family" in
    iphone) family_token=iphone ;;
    ipad) family_token=ipad ;;
    *)
        print -u2 "usage: $0 iphone|ipad"
        exit 64
        ;;
esac

if [[ ! -d "$project_path" ]]; then
    print -u2 "error: missing $project_path; run make ios-project first."
    exit 1
fi

destinations=""
destination_id=""
integer attempt

for attempt in 1 2 3; do
    destinations=$(xcodebuild \
        -project "$project_path" \
        -scheme "$scheme" \
        -showdestinations)

    destination_id=$(print -r -- "$destinations" | awk -v family="$family_token" '
        index(tolower($0), "platform:ios simulator") {
            lowercase = tolower($0)
            name_start = index(lowercase, "name:")
            if (name_start == 0 || index(substr(lowercase, name_start + 5), family) == 0) {
                next
            }
            if (match($0, /id:[^,}]+/)) {
                value = substr($0, RSTART + 3, RLENGTH - 3)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
                exit
            }
        }
    ')

    if [[ -n "$destination_id" ]]; then
        break
    fi

    if (( attempt < 3 )); then
        print -u2 "warning: Xcode has not reported a concrete $family simulator yet; retrying ($attempt/3)."
        sleep 1
    fi
done

if [[ -z "$destination_id" ]]; then
    print -u2 "error: no available $family simulator appears in xcodebuild -showdestinations."
    print -u2 "Install an iOS runtime and at least one $family simulator in Xcode Settings > Components."
    exit 1
fi

print -r -- "$destination_id"
