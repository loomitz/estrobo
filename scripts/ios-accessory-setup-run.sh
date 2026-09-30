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
    local spike_plist="$ios_dir/EstroboAccessorySetupSpike/Info.plist"

    /usr/bin/plutil -lint "$main_plist" "$probe_plist" "$spike_plist"

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

    local actual_value
    actual_value=$(/usr/bin/plutil -extract NSAccessorySetupKitSupports json -o - "$spike_plist")
    if [[ "$actual_value" != '["Bluetooth"]' ]]; then
        print -u2 "error: the ASK diagnostic must support exactly Bluetooth."
        exit 1
    fi
    actual_value=$(/usr/bin/plutil -extract NSAccessorySetupBluetoothServices json -o - "$spike_plist")
    if [[ "$actual_value" != '["FFC0"]' ]]; then
        print -u2 "error: the ASK diagnostic must allow exactly the verified FFC0 service."
        exit 1
    fi
    actual_value=$(/usr/bin/plutil -extract NSAccessorySetupBluetoothNames json -o - "$spike_plist")
    if [[ "$actual_value" != '["GDBH-A681"]' ]]; then
        print -u2 "error: the ASK diagnostic must allow exactly the verified GDBH-A681 name."
        exit 1
    fi
    if ! /usr/libexec/PlistBuddy -c "Print :NSBluetoothAlwaysUsageDescription" \
        "$spike_plist" >/dev/null 2>&1; then
        print -u2 "error: the ASK diagnostic must explain Bluetooth identifier resolution."
        exit 1
    fi
    if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" \
        "$spike_plist" >/dev/null 2>&1; then
        print -u2 "error: the ASK diagnostic must remain foreground-only."
        exit 1
    fi
    if /usr/libexec/PlistBuddy -c "Print :NSAccessorySetupBluetoothCompanyIdentifiers" \
        "$spike_plist" >/dev/null 2>&1; then
        print -u2 "error: no Bluetooth Company ID was present in the physical evidence."
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

    if rg -n 'FFF0|FEC0|FFF1|FEC7|FEC8|GDBH|Ami' \
        "$ios_dir/EstroboAdvertisementProbe"; then
        print -u2 "error: the generic advertisement probe must not hardcode Godox identities."
        exit 1
    fi

    if rg -n 'scanForPeripherals|retrieveConnectedPeripherals|connect[[:space:]]*\(|cancelPeripheralConnection|registerForConnectionEvents|discoverServices|discoverCharacteristics|readValue|writeValue|setNotifyValue|openL2CAPChannel|CBCentralManagerOptionRestoreIdentifierKey|finishAuthorization|failAuthorization|confirmAuthorization|updateAuthorization|renameAccessory|bluetoothPairingLE' \
        "$ios_dir/EstroboAccessorySetupSpike"; then
        print -u2 "error: the ASK diagnostic may only resolve an authorized identifier; broader Bluetooth operations are forbidden."
        exit 1
    fi

    local diagnostic_model="$ios_dir/EstroboAccessorySetupSpike/AccessorySetupDiagnosticModel.swift"
    if ! rg -qF 'let exactBluetoothName = "GDBH-A681"' "$diagnostic_model" ||
        ! rg -qF 'let advertisedServiceUUID = "FFC0"' "$diagnostic_model" ||
        ! rg -qF 'settings.options = [.filterDiscoveryResults]' "$diagnostic_model" ||
        ! rg -qF 'handlePersistedAccessories()' "$diagnostic_model"; then
        print -u2 "error: the ASK runtime identity/filter contract diverges from the verified plist evidence."
        exit 1
    fi

    local retrieve_count
    retrieve_count=$(rg -c 'retrievePeripherals[[:space:]]*\(' \
        "$ios_dir/EstroboAccessorySetupSpike"/*.swift | \
        awk -F: '{ total += $NF } END { print total + 0 }')
    if [[ "$retrieve_count" != 1 ]]; then
        print -u2 "error: the ASK diagnostic must contain exactly one read-only identifier resolution call."
        exit 1
    fi

    local remove_count
    remove_count=$(rg -c 'removeAccessory[[:space:]]*\(' \
        "$ios_dir/EstroboAccessorySetupSpike"/*.swift | \
        awk -F: '{ total += $NF } END { print total + 0 }')
    if [[ "$remove_count" != 1 ]]; then
        print -u2 "error: the ASK diagnostic must contain exactly one explicit authorization-removal call."
        exit 1
    fi
    if ! rg -qF 'Button("3. Remove diagnostic authorization", role: .destructive)' \
        "$ios_dir/EstroboAccessorySetupSpike/AccessorySetupDiagnosticViews.swift" ||
        ! rg -qF '"Remove diagnostic authorization?"' \
        "$ios_dir/EstroboAccessorySetupSpike/AccessorySetupDiagnosticViews.swift" ||
        ! rg -qF 'guard canRemoveAuthorization' "$diagnostic_model"; then
        print -u2 "error: authorization removal must remain explicit, confirmed, and state-gated."
        exit 1
    fi

    if ! rg -U -q 'case \.pickerDidDismiss:\n[[:space:]]+isPickerPresented = false\n[[:space:]]+pickerGeneration = UUID\(\)\n[[:space:]]+resetDiscoveryState\(\)' \
        "$diagnostic_model" ||
        ! rg -qF 'guard isPickerPresented else { return }' "$diagnostic_model" ||
        ! rg -qF 'enterRemovalVerificationPresentation()' "$diagnostic_model"; then
        print -u2 "error: picker cancellation and removal verification must remain fail-closed."
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
