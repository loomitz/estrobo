#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repository_root=${script_dir:h}
ios_dir="$repository_root/ios"
project_path="$ios_dir/EstroboIOS.xcodeproj"
scheme=EstroboIOS
bundle_identifier=${ESTROBO_IOS_BUNDLE_IDENTIFIER:-mx.loo.estrobo.dev}
output_dir="$repository_root/docs/screenshots/ios"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/estrobo-screenshots.XXXXXX")
staged_output="$temporary_root/current"
trap 'rm -rf "$temporary_root"' EXIT

if [[ ! -d "$project_path" ]]; then
    "$script_dir/ios-project.sh"
fi

mkdir -p "$output_dir"
mkdir -p "$staged_output"
captured_count=0

capture_family() {
    local family=$1
    local destination_id
    local result_bundle="$temporary_root/$family.xcresult"
    local exported="$temporary_root/$family-attachments"
    local family_count=0

    destination_id=$("$script_dir/ios-destination.sh" "$family")
    print "Capturing $family reference screens on simulator $destination_id"

    xcodebuild \
        -project "$project_path" \
        -scheme "$scheme" \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$destination_id" \
        -derivedDataPath "$ios_dir/DerivedData/screenshots-$family" \
        -resultBundlePath "$result_bundle" \
        -only-testing:EstroboIOSUITests/EstroboReferenceScreenshotUITests/testCaptureReferenceScreens \
        "ESTROBO_IOS_BUNDLE_IDENTIFIER=$bundle_identifier" \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
        CODE_SIGNING_ALLOWED=NO \
        test

    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$exported"

    local exported_file
    local suggested_name
    local destination_name
    while IFS=$'\t' read -r exported_file suggested_name; do
        [[ -n "$exported_file" && -n "$suggested_name" ]] || continue
        if [[ "$exported_file" != *.png \
            || "$suggested_name" != estrobo-reference-${family}-*.png ]]; then
            print -u2 "error: unexpected non-PNG or cross-family reference attachment: $suggested_name ($exported_file)."
            exit 1
        fi
        destination_name=$(print -r -- "$suggested_name" \
            | sed -E 's/_0_[[:xdigit:]-]+\.png$/.png/')
        cp "$exported/$exported_file" "$staged_output/$destination_name"
        if [[ "$family" == ipad ]]; then
            sips --rotate 270 "$staged_output/$destination_name" >/dev/null
        fi
        (( family_count += 1 ))
        (( captured_count += 1 ))
        print "Staged $destination_name"
    done < <(
        jq -r '
            .[]
            | .attachments[]
            | select(.suggestedHumanReadableName | startswith("estrobo-reference-"))
            | [.exportedFileName, .suggestedHumanReadableName]
            | @tsv
        ' "$exported/manifest.json"
    )

    if (( family_count != 7 )); then
        print -u2 "error: expected exactly seven current $family PNG attachments; exported $family_count."
        exit 1
    fi
}

capture_family iphone
capture_family ipad

if (( captured_count != 14 )); then
    print -u2 "error: expected exactly fourteen attachments from the current iPhone/iPad capture; exported $captured_count."
    exit 1
fi

for family in iphone ipad; do
    local_count=$(find "$staged_output" -maxdepth 1 -type f \
        -name "estrobo-reference-$family-*.png" | wc -l | tr -d ' ')
    if (( local_count != 7 )); then
        print -u2 "error: expected exactly seven staged $family reference screenshots; found $local_count."
        exit 1
    fi

    for reference in "$staged_output"/estrobo-reference-$family-*.png(N); do
        pixel_width=$(sips -g pixelWidth "$reference" | awk '/pixelWidth:/ { print $2 }')
        pixel_height=$(sips -g pixelHeight "$reference" | awk '/pixelHeight:/ { print $2 }')
        if [[ "$family" == iphone && $pixel_width -ge $pixel_height ]] \
            || [[ "$family" == ipad && $pixel_width -le $pixel_height ]]; then
            print -u2 "error: unexpected $family screenshot geometry for ${reference:t}: ${pixel_width}x${pixel_height}."
            exit 1
        fi
    done
done

typeset -a previous_references
previous_references=(
    "$output_dir"/estrobo-reference-iphone-*.png(N)
    "$output_dir"/estrobo-reference-ipad-*.png(N)
)
if (( ${#previous_references[@]} > 0 )); then
    mkdir -p "$temporary_root/previous"
    mv -- "${previous_references[@]}" "$temporary_root/previous/"
fi
cp "$staged_output"/*.png "$output_dir/"

final_count=$(find "$output_dir" -maxdepth 1 -type f \
    -name 'estrobo-reference-*.png' | wc -l | tr -d ' ')
if (( final_count != 14 )); then
    print -u2 "error: expected exactly fourteen installed reference screenshots; found $final_count."
    exit 1
fi

print "Reference screenshots are available in $output_dir"
