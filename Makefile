MAC_PROTOTYPE_DIR := $(CURDIR)/prototype/EstroboMac
BUILD_DIR ?= $(MAC_PROTOTYPE_DIR)/Build
DIST_DIR ?= $(CURDIR)/Dist

.PHONY: poc poc-build poc-clean mac-prototype mac-prototype-build mac-prototype-check mac-prototype-test mac-prototype-signing-certificate-check mac-prototype-universal mac-prototype-release mac-prototype-release-verify mac-prototype-release-verify-existing mac-prototype-package mac-prototype-package-existing mac-prototype-developer-id-tools-test mac-prototype-developer-id-certificate-check mac-prototype-developer-id-release mac-prototype-developer-id-release-verify mac-prototype-developer-id-local-release mac-prototype-developer-id-verify-signed-existing mac-prototype-developer-id-notarize-existing mac-prototype-developer-id-local-notarize-existing mac-prototype-developer-id-resume-notarization-existing mac-prototype-developer-id-local-resume-notarization-existing mac-prototype-developer-id-verify-existing mac-prototype-developer-id-package-existing mac-prototype-developer-id-local-source-verify mac-prototype-developer-id-dmg-create-existing mac-prototype-developer-id-dmg-resume-existing mac-prototype-developer-id-dmg-verify-existing mac-prototype-developer-id-local-approval-finalize mac-prototype-developer-id-local-approval-verify mac-prototype-clean

poc:
	$(MAKE) -C prototype/EstroboBLEPoC run

poc-build:
	$(MAKE) -C prototype/EstroboBLEPoC build

poc-clean:
	$(MAKE) -C prototype/EstroboBLEPoC clean

mac-prototype:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" run BUILD_DIR="$(abspath $(BUILD_DIR))"

mac-prototype-build:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" build BUILD_DIR="$(abspath $(BUILD_DIR))"

mac-prototype-check:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" check BUILD_DIR="$(abspath $(BUILD_DIR))"

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
