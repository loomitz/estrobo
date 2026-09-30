MAC_PROTOTYPE_DIR := $(CURDIR)/prototype/GodoxMacControlPrototype
BUILD_DIR ?= $(MAC_PROTOTYPE_DIR)/Build
DIST_DIR ?= $(CURDIR)/Dist

IOS_DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
IOS_BUNDLE_IDENTIFIER ?= mx.loo.estrobo.dev
MODULE_DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer

.PHONY: poc poc-build poc-clean mac-prototype mac-prototype-build mac-prototype-check mac-prototype-test mac-prototype-signing-certificate-check mac-prototype-universal mac-prototype-release mac-prototype-release-verify mac-prototype-release-verify-existing mac-prototype-package mac-prototype-package-existing mac-prototype-developer-id-tools-test mac-prototype-developer-id-certificate-check mac-prototype-developer-id-release mac-prototype-developer-id-release-verify mac-prototype-developer-id-local-release mac-prototype-developer-id-verify-signed-existing mac-prototype-developer-id-notarize-existing mac-prototype-developer-id-local-notarize-existing mac-prototype-developer-id-resume-notarization-existing mac-prototype-developer-id-local-resume-notarization-existing mac-prototype-developer-id-verify-existing mac-prototype-developer-id-package-existing mac-prototype-developer-id-local-source-verify mac-prototype-developer-id-dmg-create-existing mac-prototype-developer-id-dmg-resume-existing mac-prototype-developer-id-dmg-verify-existing mac-prototype-developer-id-local-approval-finalize mac-prototype-developer-id-local-approval-verify mac-prototype-clean
.PHONY: ios-project ios-check ios-core-test ios-build ios-test ios-ui-smoke ios-ui-test ios-release-build ios-archive ios-screenshots ios-accessory-setup-check ios-accessory-spike-check ios-advertisement-probe-check

poc:
	$(MAKE) -C prototype/GodoxBLEPoC run

poc-build:
	$(MAKE) -C prototype/GodoxBLEPoC build

poc-clean:
	$(MAKE) -C prototype/GodoxBLEPoC clean

mac-prototype:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" run BUILD_DIR="$(abspath $(BUILD_DIR))"

mac-prototype-build:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" build BUILD_DIR="$(abspath $(BUILD_DIR))"

mac-prototype-check:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" check BUILD_DIR="$(abspath $(BUILD_DIR))" MODULE_DEVELOPER_DIR="$(MODULE_DEVELOPER_DIR)"

mac-prototype-test:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" test BUILD_DIR="$(abspath $(BUILD_DIR))"

mac-prototype-signing-certificate-check:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" signing-certificate-check BUILD_DIR="$(abspath $(BUILD_DIR))"

mac-prototype-universal:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" universal BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-release:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" release BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-release-verify:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" release-verify BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-release-verify-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" release-verify-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-package:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" package BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-package-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" package-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-tools-test:
	./scripts/test-developer-id-release-tools.sh
	./scripts/test-local-developer-id-release-source.sh
	./scripts/test-developer-id-dmg-tools.sh
	./scripts/test-local-developer-id-release-approval.sh

mac-prototype-developer-id-certificate-check:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-certificate-check BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-release:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-release BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-release-verify:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-release-verify BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-local-release:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-local-release BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-verify-signed-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-verify-signed-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-notarize-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-notarize-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-local-notarize-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-local-notarize-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-resume-notarization-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-resume-notarization-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-local-resume-notarization-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-local-resume-notarization-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-verify-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-verify-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-package-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-package-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-local-source-verify:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-local-source-verify BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-dmg-create-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-dmg-create-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-dmg-resume-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-dmg-resume-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-dmg-verify-existing:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-dmg-verify-existing BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-local-approval-finalize:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-local-approval-finalize BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-developer-id-local-approval-verify:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" developer-id-local-approval-verify BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

mac-prototype-clean:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" clean BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"

ios-project:
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" ./scripts/ios-project.sh

ios-check: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" \
		ESTROBO_IOS_BUNDLE_IDENTIFIER="$(IOS_BUNDLE_IDENTIFIER)" \
		./scripts/ios-run.sh check

ios-core-test:
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" swift test

ios-build: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" \
		ESTROBO_IOS_BUNDLE_IDENTIFIER="$(IOS_BUNDLE_IDENTIFIER)" \
		./scripts/ios-run.sh build

ios-test: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" \
		ESTROBO_IOS_BUNDLE_IDENTIFIER="$(IOS_BUNDLE_IDENTIFIER)" \
		./scripts/ios-run.sh test

ios-ui-smoke: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" \
		ESTROBO_IOS_BUNDLE_IDENTIFIER="$(IOS_BUNDLE_IDENTIFIER)" \
		./scripts/ios-run.sh ui-smoke

ios-ui-test: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" \
		ESTROBO_IOS_BUNDLE_IDENTIFIER="$(IOS_BUNDLE_IDENTIFIER)" \
		./scripts/ios-run.sh ui-test

ios-release-build: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" \
		ESTROBO_IOS_BUNDLE_IDENTIFIER="$(IOS_BUNDLE_IDENTIFIER)" \
		./scripts/ios-run.sh release-build

ios-archive: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" \
		ESTROBO_IOS_BUNDLE_IDENTIFIER="$(IOS_BUNDLE_IDENTIFIER)" \
		./scripts/ios-run.sh archive

ios-screenshots: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" \
		ESTROBO_IOS_BUNDLE_IDENTIFIER="$(IOS_BUNDLE_IDENTIFIER)" \
		./scripts/ios-screenshots.sh

ios-accessory-setup-check: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" ./scripts/ios-accessory-setup-run.sh check

ios-accessory-spike-check: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" ./scripts/ios-accessory-setup-run.sh spike

ios-advertisement-probe-check: ios-project
	DEVELOPER_DIR="$(IOS_DEVELOPER_DIR)" ./scripts/ios-accessory-setup-run.sh probe
