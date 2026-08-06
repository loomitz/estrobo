SHELL := /bin/zsh

.DEFAULT_GOAL := build

APP_NAME := estrobo
BUILD_DIR ?= Build
DIST_DIR ?= Dist
VERSION ?= 0.1.0
BUILD_NUMBER ?= 2
TAG ?= v$(VERSION)-beta.$(BUILD_NUMBER)
SIGNING_IDENTITY ?=
SIGNING_KEYCHAIN ?=
MACOSX_DEPLOYMENT_TARGET := 13.0
BUNDLE_IDENTIFIER := mx.loo.estrobo
REPOSITORY_ROOT := ../..
SIGNING_CERTIFICATE ?= $(REPOSITORY_ROOT)/release/signing/estrobo-beta-signing.cer
SIGNING_CERTIFICATE_SHA256 ?= $(REPOSITORY_ROOT)/release/signing/estrobo-beta-signing.sha256
RELEASE_VERIFY_SCRIPT := $(REPOSITORY_ROOT)/scripts/verify-macos-release.sh
SIGNING_CERTIFICATE_VERIFY_SCRIPT := $(REPOSITORY_ROOT)/scripts/verify-signing-certificate.sh
PACKAGE_SCRIPT := $(REPOSITORY_ROOT)/scripts/package-macos-release.sh
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
LEGACY_APP_BUNDLE := $(BUILD_DIR)/GodoxMacControlPrototype.app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
EXECUTABLE := $(MACOS_DIR)/$(APP_NAME)
UNIVERSAL_DIR := $(BUILD_DIR)/Universal
UNIVERSAL_APP_BUNDLE := $(UNIVERSAL_DIR)/$(APP_NAME).app
UNIVERSAL_CONTENTS_DIR := $(UNIVERSAL_APP_BUNDLE)/Contents
UNIVERSAL_MACOS_DIR := $(UNIVERSAL_CONTENTS_DIR)/MacOS
UNIVERSAL_RESOURCES_DIR := $(UNIVERSAL_CONTENTS_DIR)/Resources
UNIVERSAL_EXECUTABLE := $(UNIVERSAL_MACOS_DIR)/$(APP_NAME)
SLICE_DIR := $(BUILD_DIR)/ReleaseSlices
TEST_EXECUTABLE := $(BUILD_DIR)/SafeGodoxProtocolFrameCheck
SESSION_TEST_EXECUTABLE := $(BUILD_DIR)/GodoxSessionRecoveryCheck
STUDIO_LIBRARY_TEST_EXECUTABLE := $(BUILD_DIR)/StudioLibraryStoreCheck
LOCALIZATION_TEST_EXECUTABLE := $(BUILD_DIR)/AppLocalizationCheck
MODELING_MENU_POINTER_TEST_EXECUTABLE := $(BUILD_DIR)/ModelingMenuMouseOrderingCheck
WORKSPACE_CHROME_TEST_EXECUTABLE := $(BUILD_DIR)/WorkspaceChromeInteractionCheck
BRAND_ASSET_TEST_EXECUTABLE := $(BUILD_DIR)/EstroboBrandAssetsCheck
INTERACTIVE_EDITING_TEST_EXECUTABLE := $(BUILD_DIR)/InteractiveEditingCheck
INFO_PLIST := Info.plist
ENTITLEMENTS := GodoxMacControlPrototype.entitlements
RESOURCE_SOURCE_DIR := Resources
LOCALIZATION_RESOURCES := $(sort $(wildcard $(RESOURCE_SOURCE_DIR)/*.lproj/*.strings))
RESOURCE_FILES := $(sort $(shell find $(RESOURCE_SOURCE_DIR) -type f))
LOCAL_SOURCES := $(sort $(wildcard Sources/*.swift))
BLE_SOURCE := ../GodoxBLEPoC/Sources/BluetoothClient.swift
SOURCES := $(LOCAL_SOURCES) $(BLE_SOURCE)

SWIFTC := $(shell xcrun --find swiftc)
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-path)
TARGET_ARCH ?= $(shell uname -m)
COMMIT ?= $(shell git -C "$(REPOSITORY_ROOT)" rev-parse HEAD 2>/dev/null || printf uncommitted)

.PHONY: build check test test-protocol test-session-recovery test-studio-library test-localization test-modeling-menu-pointer test-workspace-chrome test-brand-assets test-interactive-editing signing-certificate-check universal release-preflight release release-verify release-verify-existing package package-existing run clean

build: $(EXECUTABLE)

check:
	"$(SWIFTC)" \
		-parse-as-library \
		-warnings-as-errors \
		-typecheck \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework SwiftUI \
		-framework AppKit \
		-framework CoreBluetooth \
		$(SOURCES)

test: test-protocol test-session-recovery test-studio-library test-localization test-modeling-menu-pointer test-workspace-chrome test-brand-assets test-interactive-editing

test-protocol:
	@/bin/mkdir -p "$(BUILD_DIR)"
	"$(SWIFTC)" \
		-warnings-as-errors \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework Combine \
		-framework SwiftUI \
		-framework AppKit \
		Sources/AppLocalization.swift \
		Sources/SafeGodoxProtocol.swift \
		Sources/GroupVisualIdentity.swift \
		Sources/GroupVisualColor.swift \
		Sources/GodoxCapabilities.swift \
		Sources/ControlModel.swift \
		Sources/ChangeDeliveryPreferences.swift \
		Sources/TransmitterProfilePreferences.swift \
		Sources/LocalGroupPreferences.swift \
		Sources/PendingRestorationStore.swift \
		Sources/SavedRadioStore.swift \
		Tests/SafeGodoxProtocolFrameCheck.swift \
		-o "$(TEST_EXECUTABLE)"
	@"$(TEST_EXECUTABLE)"

test-session-recovery:
	@/bin/mkdir -p "$(BUILD_DIR)"
	"$(SWIFTC)" \
		-warnings-as-errors \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework Combine \
		-framework CoreBluetooth \
		Sources/AppLocalization.swift \
		Sources/SafeGodoxProtocol.swift \
		Sources/GodoxCapabilities.swift \
		Sources/ControlModel.swift \
		Sources/ChangeDeliveryPreferences.swift \
		Sources/TransmitterProfilePreferences.swift \
		Sources/LocalGroupPreferences.swift \
		Sources/PendingRestorationStore.swift \
		Sources/SavedRadioStore.swift \
		Sources/StudioLibraryStore.swift \
		Sources/SessionDeadlineScheduler.swift \
		Sources/GodoxSessionTransport.swift \
		Sources/GodoxSessionController.swift \
		$(BLE_SOURCE) \
		Tests/GodoxSessionRecoveryCheck.swift \
		-o "$(SESSION_TEST_EXECUTABLE)"
	@"$(SESSION_TEST_EXECUTABLE)"

test-studio-library:
	@/bin/mkdir -p "$(BUILD_DIR)"
	"$(SWIFTC)" \
		-warnings-as-errors \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		Sources/SafeGodoxProtocol.swift \
		Sources/StudioLibraryStore.swift \
		Tests/StudioLibraryStoreCheck.swift \
		-o "$(STUDIO_LIBRARY_TEST_EXECUTABLE)"
	@"$(STUDIO_LIBRARY_TEST_EXECUTABLE)"

test-localization:
	@/bin/mkdir -p "$(BUILD_DIR)"
	@/usr/bin/plutil -lint $(LOCALIZATION_RESOURCES)
	"$(SWIFTC)" \
		-warnings-as-errors \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework Combine \
		Sources/AppLocalization.swift \
		Tests/AppLocalizationCheck.swift \
		-o "$(LOCALIZATION_TEST_EXECUTABLE)"
	@"$(LOCALIZATION_TEST_EXECUTABLE)"

test-modeling-menu-pointer:
	@/bin/mkdir -p "$(BUILD_DIR)"
	"$(SWIFTC)" \
		-warnings-as-errors \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework SwiftUI \
		-framework AppKit \
		Tests/ModelingMenuMouseOrderingCheck.swift \
		-o "$(MODELING_MENU_POINTER_TEST_EXECUTABLE)"
	@"$(MODELING_MENU_POINTER_TEST_EXECUTABLE)"

test-workspace-chrome:
	@/bin/mkdir -p "$(BUILD_DIR)"
	"$(SWIFTC)" \
		-parse-as-library \
		-warnings-as-errors \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework SwiftUI \
		-framework AppKit \
		-framework CoreBluetooth \
		$(filter-out Sources/GodoxMacControlPrototypeApp.swift,$(LOCAL_SOURCES)) \
		$(BLE_SOURCE) \
		Tests/WorkspaceChromeInteractionCheck.swift \
		-o "$(WORKSPACE_CHROME_TEST_EXECUTABLE)"
	@"$(WORKSPACE_CHROME_TEST_EXECUTABLE)"

test-brand-assets: $(EXECUTABLE)
	@/bin/mkdir -p "$(BUILD_DIR)"
	"$(SWIFTC)" \
		-warnings-as-errors \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework AppKit \
		Sources/EstroboBrandAssets.swift \
		Tests/EstroboBrandAssetsCheck.swift \
		-o "$(BRAND_ASSET_TEST_EXECUTABLE)"
	@"$(BRAND_ASSET_TEST_EXECUTABLE)" "$(APP_BUNDLE)"

test-interactive-editing:
	@/bin/mkdir -p "$(BUILD_DIR)"
	"$(SWIFTC)" \
		-parse-as-library \
		-warnings-as-errors \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework SwiftUI \
		-framework AppKit \
		-framework CoreBluetooth \
		$(filter-out Sources/GodoxMacControlPrototypeApp.swift,$(LOCAL_SOURCES)) \
		$(BLE_SOURCE) \
		Tests/InteractiveEditingCheck.swift \
		-o "$(INTERACTIVE_EDITING_TEST_EXECUTABLE)"
	@"$(INTERACTIVE_EDITING_TEST_EXECUTABLE)"

signing-certificate-check:
	@"$(SIGNING_CERTIFICATE_VERIFY_SCRIPT)" \
		"$(SIGNING_CERTIFICATE)" \
		"$(SIGNING_CERTIFICATE_SHA256)"

$(EXECUTABLE): $(SOURCES) $(INFO_PLIST) $(ENTITLEMENTS) $(RESOURCE_FILES)
	@/bin/rm -rf -- "$(APP_BUNDLE)"
	@/bin/mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	@/bin/cp "$(INFO_PLIST)" "$(CONTENTS_DIR)/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_IDENTIFIER)" "$(CONTENTS_DIR)/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(CONTENTS_DIR)/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(CONTENTS_DIR)/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $(MACOSX_DEPLOYMENT_TARGET)" "$(CONTENTS_DIR)/Info.plist"
	@/usr/bin/ditto "$(RESOURCE_SOURCE_DIR)" "$(RESOURCES_DIR)"
	"$(SWIFTC)" \
		-parse-as-library \
		-sdk "$(MACOS_SDK)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework SwiftUI \
		-framework AppKit \
		-framework CoreBluetooth \
		-o "$(EXECUTABLE)" \
		$(SOURCES)
	/usr/bin/codesign --force --sign - \
		--options runtime \
		--entitlements "$(ENTITLEMENTS)" \
		"$(APP_BUNDLE)"
	@/usr/bin/codesign --verify --deep --strict "$(APP_BUNDLE)"
	@print "Construida: $(APP_BUNDLE)"

universal:
	@set -euo pipefail; \
	/bin/rm -rf -- "$(UNIVERSAL_DIR)" "$(SLICE_DIR)"; \
	/bin/mkdir -p "$(UNIVERSAL_MACOS_DIR)" "$(UNIVERSAL_RESOURCES_DIR)" "$(SLICE_DIR)/arm64" "$(SLICE_DIR)/x86_64"; \
	/bin/cp "$(INFO_PLIST)" "$(UNIVERSAL_CONTENTS_DIR)/Info.plist"; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $(BUNDLE_IDENTIFIER)" "$(UNIVERSAL_CONTENTS_DIR)/Info.plist"; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(UNIVERSAL_CONTENTS_DIR)/Info.plist"; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(UNIVERSAL_CONTENTS_DIR)/Info.plist"; \
	/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $(MACOSX_DEPLOYMENT_TARGET)" "$(UNIVERSAL_CONTENTS_DIR)/Info.plist"; \
	/usr/bin/ditto "$(RESOURCE_SOURCE_DIR)" "$(UNIVERSAL_RESOURCES_DIR)"; \
	for arch in arm64 x86_64; do \
		"$(SWIFTC)" \
			-parse-as-library \
			-O \
			-warnings-as-errors \
			-sdk "$(MACOS_SDK)" \
			-target "$${arch}-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
			-framework SwiftUI \
			-framework AppKit \
			-framework CoreBluetooth \
			-o "$(SLICE_DIR)/$${arch}/$(APP_NAME)" \
			$(SOURCES); \
	done; \
	/usr/bin/lipo -create \
		"$(SLICE_DIR)/arm64/$(APP_NAME)" \
		"$(SLICE_DIR)/x86_64/$(APP_NAME)" \
		-output "$(UNIVERSAL_EXECUTABLE)"; \
	/usr/bin/lipo "$(UNIVERSAL_EXECUTABLE)" -verify_arch arm64 x86_64; \
	print "Construido sin firmar: $(UNIVERSAL_APP_BUNDLE)"

release-preflight:
	@set -euo pipefail; \
	if [[ -z "$(SIGNING_IDENTITY)" || "$(SIGNING_IDENTITY)" == "-" ]]; then \
		print -u2 "SIGNING_IDENTITY debe ser una identidad estable; la firma ad hoc no está permitida para release."; \
		exit 2; \
	fi; \
	if [[ ! -r "$(SIGNING_CERTIFICATE)" || ! -r "$(SIGNING_CERTIFICATE_SHA256)" ]]; then \
		print -u2 "Faltan el certificado público o su huella versionada en release/signing/."; \
		exit 2; \
	fi; \
	"$(SIGNING_CERTIFICATE_VERIFY_SCRIPT)" \
		"$(SIGNING_CERTIFICATE)" \
		"$(SIGNING_CERTIFICATE_SHA256)"

release: release-preflight universal
	@set -euo pipefail; \
	keychain_args=(); \
	if [[ -n "$(SIGNING_KEYCHAIN)" ]]; then \
		keychain_args=(--keychain "$(SIGNING_KEYCHAIN)"); \
	fi; \
	/usr/bin/codesign --force \
		--sign "$(SIGNING_IDENTITY)" \
		"$${keychain_args[@]}" \
		--options runtime \
		--timestamp=none \
		--entitlements "$(ENTITLEMENTS)" \
		"$(UNIVERSAL_APP_BUNDLE)"; \
	print "Firmado para release: $(UNIVERSAL_APP_BUNDLE)"

release-verify: release
	@$(MAKE) release-verify-existing \
		BUILD_DIR="$(BUILD_DIR)" \
		DIST_DIR="$(DIST_DIR)" \
		VERSION="$(VERSION)" \
		BUILD_NUMBER="$(BUILD_NUMBER)" \
		MACOSX_DEPLOYMENT_TARGET="$(MACOSX_DEPLOYMENT_TARGET)" \
		SIGNING_CERTIFICATE="$(SIGNING_CERTIFICATE)" \
		SIGNING_CERTIFICATE_SHA256="$(SIGNING_CERTIFICATE_SHA256)"

release-verify-existing:
	@APP_BUNDLE="$(UNIVERSAL_APP_BUNDLE)" \
		VERSION="$(VERSION)" \
		BUILD_NUMBER="$(BUILD_NUMBER)" \
		BUNDLE_IDENTIFIER="$(BUNDLE_IDENTIFIER)" \
		MACOSX_DEPLOYMENT_TARGET="$(MACOSX_DEPLOYMENT_TARGET)" \
		SIGNING_CERTIFICATE="$(SIGNING_CERTIFICATE)" \
		SIGNING_CERTIFICATE_SHA256="$(SIGNING_CERTIFICATE_SHA256)" \
		"$(RELEASE_VERIFY_SCRIPT)"

package: release-verify
	@APP_BUNDLE="$(UNIVERSAL_APP_BUNDLE)" \
		DIST_DIR="$(DIST_DIR)" \
		VERSION="$(VERSION)" \
		BUILD_NUMBER="$(BUILD_NUMBER)" \
		TAG="$(TAG)" \
		COMMIT="$(COMMIT)" \
		MACOSX_DEPLOYMENT_TARGET="$(MACOSX_DEPLOYMENT_TARGET)" \
		BUNDLE_IDENTIFIER="$(BUNDLE_IDENTIFIER)" \
		SIGNING_CERTIFICATE="$(SIGNING_CERTIFICATE)" \
		SIGNING_CERTIFICATE_SHA256="$(SIGNING_CERTIFICATE_SHA256)" \
		VERIFY_SCRIPT="$(RELEASE_VERIFY_SCRIPT)" \
		"$(PACKAGE_SCRIPT)"

package-existing: release-verify-existing
	@APP_BUNDLE="$(UNIVERSAL_APP_BUNDLE)" \
		DIST_DIR="$(DIST_DIR)" \
		VERSION="$(VERSION)" \
		BUILD_NUMBER="$(BUILD_NUMBER)" \
		TAG="$(TAG)" \
		COMMIT="$(COMMIT)" \
		MACOSX_DEPLOYMENT_TARGET="$(MACOSX_DEPLOYMENT_TARGET)" \
		BUNDLE_IDENTIFIER="$(BUNDLE_IDENTIFIER)" \
		SIGNING_CERTIFICATE="$(SIGNING_CERTIFICATE)" \
		SIGNING_CERTIFICATE_SHA256="$(SIGNING_CERTIFICATE_SHA256)" \
		VERIFY_SCRIPT="$(RELEASE_VERIFY_SCRIPT)" \
		"$(PACKAGE_SCRIPT)"

run: build
	@/usr/bin/open -n "$(APP_BUNDLE)"

clean:
	@/bin/rm -rf -- "$(APP_BUNDLE)" "$(LEGACY_APP_BUNDLE)" "$(UNIVERSAL_DIR)" "$(SLICE_DIR)" "$(TEST_EXECUTABLE)" "$(SESSION_TEST_EXECUTABLE)" "$(STUDIO_LIBRARY_TEST_EXECUTABLE)" "$(LOCALIZATION_TEST_EXECUTABLE)" "$(MODELING_MENU_POINTER_TEST_EXECUTABLE)" "$(WORKSPACE_CHROME_TEST_EXECUTABLE)" "$(BRAND_ASSET_TEST_EXECUTABLE)" "$(INTERACTIVE_EDITING_TEST_EXECUTABLE)"
	@print "Eliminados los artefactos de $(APP_NAME)"
