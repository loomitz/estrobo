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
    check|build|test|ui-smoke|ui-test|release-build|archive) ;;
    *)
        print -u2 "usage: $0 check|build|test|ui-smoke|ui-test|release-build|archive"
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

validate_localization_parity() {
    local english_path=$1
    local spanish_path=$2
    local label=$3
    local key_diff

    key_diff=$(
        /usr/bin/diff -u \
            <(/usr/bin/plutil -convert json -o - "$english_path" \
                | jq -r 'keys[]' \
                | LC_ALL=C /usr/bin/sort) \
            <(/usr/bin/plutil -convert json -o - "$spanish_path" \
                | jq -r 'keys[]' \
                | LC_ALL=C /usr/bin/sort) \
            || true
    )
    if [[ -n "$key_diff" ]]; then
        print -u2 "error: English and Spanish $label keys differ:"
        print -u2 -r -- "$key_diff"
        exit 1
    fi
}

validate_metadata() {
    if ! command -v jq >/dev/null 2>&1; then
        print -u2 "error: jq is required for iOS metadata validation (for example: brew install jq)."
        exit 1
    fi

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

    validate_localization_parity \
        "$ios_dir/EstroboIOS/Resources/en.lproj/InfoPlist.strings" \
        "$ios_dir/EstroboIOS/Resources/es.lproj/InfoPlist.strings" \
        "InfoPlist.strings"
    validate_localization_parity \
        "$ios_dir/EstroboIOS/Resources/en.lproj/Localizable.strings" \
        "$ios_dir/EstroboIOS/Resources/es.lproj/Localizable.strings" \
        "Localizable.strings"

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
    if ! print -r -- "$privacy_json" | jq -e '
        .NSPrivacyTracking == false
            and (.NSPrivacyTrackingDomains | type == "array" and length == 0)
            and (.NSPrivacyCollectedDataTypes | type == "array" and length == 0)
    ' >/dev/null; then
        print -u2 "error: PrivacyInfo.xcprivacy must declare no tracking, tracking domains, or collected data."
        exit 1
    fi
}

validate_unsigned_archive() {
    local archive_path=$1
    local app_path="$archive_path/Products/Applications/Estrobo.app"
    local executable_path="$app_path/Estrobo"
    local dsym_path="$archive_path/dSYMs/Estrobo.app.dSYM"
    local dsym_binary="$dsym_path/Contents/Resources/DWARF/Estrobo"
    local archived_bundle_identifier
    local executable_uuid
    local dsym_uuid

    [[ -d "$archive_path" ]] || {
        print -u2 "error: archive was not created at $archive_path."
        exit 1
    }
    [[ -d "$app_path" ]] || {
        print -u2 "error: archive does not contain Estrobo.app."
        exit 1
    }
    [[ -f "$executable_path" ]] || {
        print -u2 "error: archived app does not contain its executable."
        exit 1
    }
    [[ -d "$dsym_path" ]] || {
        print -u2 "error: archive does not contain Estrobo.app.dSYM."
        exit 1
    }
    [[ -f "$dsym_binary" ]] || {
        print -u2 "error: Estrobo.app.dSYM does not contain its DWARF binary."
        exit 1
    }
    [[ -f "$app_path/PrivacyInfo.xcprivacy" ]] || {
        print -u2 "error: archived app does not contain PrivacyInfo.xcprivacy."
        exit 1
    }
    [[ -f "$app_path/Assets.car" ]] || {
        print -u2 "error: archived app does not contain its compiled asset catalogue."
        exit 1
    }
    [[ ! -d "$app_path/_CodeSignature" ]] || {
        print -u2 "error: the credential-free archive lane unexpectedly produced a code signature."
        exit 1
    }

    archived_bundle_identifier=$(
        /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
            "$app_path/Info.plist"
    )
    if [[ "$archived_bundle_identifier" != "$bundle_identifier" ]]; then
        print -u2 \
            "error: archived bundle identifier $archived_bundle_identifier does not match $bundle_identifier."
        exit 1
    fi

    /usr/bin/lipo "$executable_path" -verify_arch arm64
    executable_uuid=$(
        /usr/bin/dwarfdump --uuid "$executable_path" \
            | /usr/bin/awk '/^UUID:/ { print $2 " " $3 }'
    )
    dsym_uuid=$(
        /usr/bin/dwarfdump --uuid "$dsym_binary" \
            | /usr/bin/awk '/^UUID:/ { print $2 " " $3 }'
    )
    if [[ -z "$executable_uuid" || "$executable_uuid" != "$dsym_uuid" ]]; then
        print -u2 "error: archived executable and dSYM UUIDs do not match."
        exit 1
    fi
    if /usr/bin/codesign --verify "$app_path" >/dev/null 2>&1; then
        print -u2 "error: the credential-free archive lane unexpectedly produced a signed app."
        exit 1
    fi

    print "Validated unsigned Release archive: $archive_path"
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
    ui-smoke)
        destination_ids
        smoke_tests=(
            -only-testing:EstroboIOSUITests/EstroboTracerUITests/testDemoScanReadyAdjustAndApplyTracer
            -only-testing:EstroboIOSUITests/EstroboTracerUITests/testAdaptiveRootMatchesCurrentIdiom
            -only-testing:EstroboIOSUITests/EstroboSettingsLinksUITests/testSettingsExposePrivacyAndSupportLinks
        )
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$iphone_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/ui-smoke-iphone" \
            "${smoke_tests[@]}" \
            test
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$ipad_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/ui-smoke-ipad" \
            "${smoke_tests[@]}" \
            test
        ;;
    ui-test)
        destination_ids
        full_ui_tests=(
            -only-testing:EstroboIOSUITests
            -skip-testing:EstroboIOSUITests/EstroboReferenceScreenshotUITests
        )
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$iphone_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/ui-test-iphone" \
            "${full_ui_tests[@]}" \
            test
        run_xcodebuild \
            "${common_arguments[@]}" \
            -destination "platform=iOS Simulator,id=$ipad_destination_id" \
            -derivedDataPath "$ios_dir/DerivedData/ui-test-ipad" \
            "${full_ui_tests[@]}" \
            test
        ;;
    release-build)
        validate_metadata
        run_xcodebuild \
            -project "$project_path" \
            -scheme "$scheme" \
            -configuration Release \
            "ESTROBO_IOS_BUNDLE_IDENTIFIER=$bundle_identifier" \
            SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
            -destination "generic/platform=iOS" \
            -derivedDataPath "$ios_dir/DerivedData/release-build" \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            build
        ;;
    archive)
        validate_metadata
        archive_path=${ESTROBO_IOS_ARCHIVE_PATH:-"$ios_dir/DerivedData/archive/Estrobo.xcarchive"}
        run_xcodebuild \
            -project "$project_path" \
            -scheme "$scheme" \
            -configuration Release \
            "ESTROBO_IOS_BUNDLE_IDENTIFIER=$bundle_identifier" \
            SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
            -destination "generic/platform=iOS" \
            -archivePath "$archive_path" \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            archive
        validate_unsigned_archive "$archive_path"
        ;;
esac
