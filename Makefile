MAC_PROTOTYPE_DIR := $(CURDIR)/prototype/GodoxMacControlPrototype
BUILD_DIR ?= $(MAC_PROTOTYPE_DIR)/Build
DIST_DIR ?= $(CURDIR)/Dist

.PHONY: poc poc-build poc-clean mac-prototype mac-prototype-build mac-prototype-check mac-prototype-test mac-prototype-signing-certificate-check mac-prototype-universal mac-prototype-release mac-prototype-release-verify mac-prototype-release-verify-existing mac-prototype-package mac-prototype-package-existing mac-prototype-clean

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

mac-prototype-clean:
	$(MAKE) -C "$(MAC_PROTOTYPE_DIR)" clean BUILD_DIR="$(abspath $(BUILD_DIR))" DIST_DIR="$(abspath $(DIST_DIR))"
