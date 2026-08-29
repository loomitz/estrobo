#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repository_root=${script_dir:h}
ios_dir="$repository_root/ios"
project_path="$ios_dir/EstroboIOS.xcodeproj"
scheme=EstroboIOS
action=${1:-}
bundle_identifier=${ESTROBO_IOS_BUNDLE_IDENTIFIER:-mx.loo.estrobo.dev}

case "$action" in
    check|build|test|ui-test) ;;
    *)
        print -u2 "usage: $0 check|build|test|ui-test"
        exit 64
        ;;
esac

if [[ ! -d "$project_path" ]]; then
    "$script_dir/ios-project.sh"
fi

common_arguments=(
    -project "$project_path"
    -scheme "$scheme"
    -configuration Debug
    "ESTROBO_IOS_BUNDLE_IDENTIFIER=$bundle_identifier"
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
)

run_xcodebuild() {
    print "Running: xcodebuild ${(q)@}"
    xcodebuild "$@"
}

validate_metadata() {
    local plist
    for plist in \
        "$ios_dir/EstroboIOS/Info.plist" \
        "$ios_dir/EstroboIOS/Resources/PrivacyInfo.xcprivacy" \
        "$ios_dir/EstroboIOS/Resources/en.lproj/InfoPlist.strings" \
        "$ios_dir/EstroboIOS/Resources/es.lproj/InfoPlist.strings" \
        "$ios_dir/EstroboIOS/Resources/en.lproj/Localizable.strings" \
        "$ios_dir/EstroboIOS/Resources/es.lproj/Localizable.strings"
    do
        /usr/bin/plutil -lint "$plist"
    done

    if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" \
        "$ios_dir/EstroboIOS/Info.plist" >/dev/null 2>&1; then
        print -u2 "error: the foreground-only scaffold must not declare UIBackgroundModes."
        exit 1
    fi

    local forbidden_key
    for forbidden_key in \
        NSCameraUsageDescription \
        NSLocationAlwaysAndWhenInUseUsageDescription \
        NSLocationWhenInUseUsageDescription \
        NSLocalNetworkUsageDescription
    do
        if /usr/libexec/PlistBuddy -c "Print :$forbidden_key" \
            "$ios_dir/EstroboIOS/Info.plist" >/dev/null 2>&1; then
            print -u2 "error: unexpected permission key $forbidden_key in Info.plist."
            exit 1
        fi
    done

    local privacy_manifest="$ios_dir/EstroboIOS/Resources/PrivacyInfo.xcprivacy"
    local privacy_json
    privacy_json=$(/usr/bin/plutil -convert json -o - "$privacy_manifest")
    if ! print -r -- "$privacy_json" | jq -e '
        any(
            .NSPrivacyAccessedAPITypes[];
            .NSPrivacyAccessedAPIType == "NSPrivacyAccessedAPICategoryUserDefaults"
                and (.NSPrivacyAccessedAPITypeReasons | index("CA92.1") != null)
        )
    ' >/dev/null; then
        print -u2 "error: PrivacyInfo.xcprivacy must declare UserDefaults/CA92.1."
        exit 1
    fi
    if ! print -r -- "$privacy_json" | jq -e '
        any(
            .NSPrivacyAccessedAPITypes[];
            .NSPrivacyAccessedAPIType == "NSPrivacyAccessedAPICategoryFileTimestamp"
                and (.NSPrivacyAccessedAPITypeReasons | index("C617.1") != null)
        )
    ' >/dev/null; then
        print -u2 "error: PrivacyInfo.xcprivacy must declare FileTimestamp/C617.1 for the app-container recovery journal."
        exit 1
    fi
}

destination_ids() {
    iphone_destination_id=$("$script_dir/ios-destination.sh" iphone)
    ipad_destination_id=$("$script_dir/ios-destination.sh" ipad)
    print "Selected iPhone simulator UDID: $iphone_destination_id"
    print "Selected iPad simulator UDID: $ipad_destination_id"
}

case "$action" in
    check)
        validate_metadata
        run_xcodebuild -project "$project_path" -list
        run_xcodebuild -project "$project_path" -scheme "$scheme" -showdestinations
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "generic/platform=iOS Simulator" \
            -derivedDataPath "$ios_dir/DerivedData/check" \
            CODE_SIGNING_ALLOWED=NO \
            build
        ;;
    build)
        destination_ids
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "generic/platform=iOS" \
            -derivedDataPath "$ios_dir/DerivedData/build-device" \
            CODE_SIGNING_ALLOWED=NO \
            build
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$iphone_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/build-iphone" \
            CODE_SIGNING_ALLOWED=NO \
            build
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$ipad_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/build-ipad" \
            CODE_SIGNING_ALLOWED=NO \
            build
        ;;
    test)
        destination_ids
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$iphone_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/test-iphone" \
            -only-testing:EstroboIOSTests \
            test
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$ipad_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/test-ipad" \
            -only-testing:EstroboIOSTests \
            test
        ;;
    ui-test)
        destination_ids
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$iphone_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/ui-test-iphone" \
            -only-testing:EstroboIOSUITests \
            test
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$ipad_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/ui-test-ipad" \
            -only-testing:EstroboIOSUITests \
            test
        ;;
esac
