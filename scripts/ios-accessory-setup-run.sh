#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repository_root=${script_dir:h}
ios_dir="$repository_root/ios"
project_path="$ios_dir/EstroboIOS.xcodeproj"
action=${1:-}

case "$action" in
    check|spike|probe) ;;
    *)
        print -u2 "usage: $0 check|spike|probe"
        exit 64
        ;;
esac

if [[ ! -d "$project_path" ]]; then
    "$script_dir/ios-project.sh"
fi

validate_configuration() {
    local main_plist="$ios_dir/EstroboIOS/Info.plist"
    local probe_plist="$ios_dir/EstroboAdvertisementProbe/Info.plist"

    /usr/bin/plutil -lint "$main_plist" "$probe_plist"

    local plist
    for plist in "$main_plist" "$probe_plist"; do
        if /usr/libexec/PlistBuddy -c "Print :NSAccessorySetupKitSupports" \
            "$plist" >/dev/null 2>&1; then
            print -u2 "error: AccessorySetupKit must remain disabled until physical advertisement evidence is verified: $plist"
            exit 1
        fi
    done

    if ! /usr/libexec/PlistBuddy -c "Print :NSBluetoothAlwaysUsageDescription" \
        "$probe_plist" >/dev/null 2>&1; then
        print -u2 "error: the advertisement probe must explain foreground Bluetooth use."
        exit 1
    fi

    if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" \
        "$probe_plist" >/dev/null 2>&1; then
        print -u2 "error: the advertisement probe must remain foreground-only."
        exit 1
    fi

    local main_target_definition
    main_target_definition=$(
        awk '
            /^  EstroboIOS:$/ { in_target = 1; next }
            in_target && /^  [^[:space:]][^:]*:$/ { exit }
            in_target { print }
        ' "$ios_dir/project.yml"
    )
    if [[ "$main_target_definition" == *EstroboAccessorySetupSpike* ]]; then
        print -u2 "error: the AccessorySetupKit spike must not be linked to EstroboIOS before physical evidence is verified."
        exit 1
    fi

    if rg -n 'FFF0|FEC0|FFF1|FEC7|FEC8|GD|Ami' \
        "$ios_dir/EstroboAccessorySetupSpike" \
        "$ios_dir/EstroboAdvertisementProbe"; then
        print -u2 "error: diagnostic targets must not hardcode unverified Godox identities."
        exit 1
    fi
}

build_scheme() {
    local scheme=$1
    local derived_data_suffix=$2
    print "Building diagnostic scheme: $scheme"
    xcodebuild \
        -project "$project_path" \
        -scheme "$scheme" \
        -configuration Debug \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$ios_dir/DerivedData/$derived_data_suffix" \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
        CODE_SIGNING_ALLOWED=NO \
        build
}

validate_configuration

case "$action" in
    check)
        build_scheme EstroboAccessorySetupSpike accessory-setup-spike
        build_scheme EstroboAdvertisementProbe advertisement-probe
        ;;
    spike)
        build_scheme EstroboAccessorySetupSpike accessory-setup-spike
        ;;
    probe)
        build_scheme EstroboAdvertisementProbe advertisement-probe
        ;;
esac
