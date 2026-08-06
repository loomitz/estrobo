SHELL := /bin/zsh

.DEFAULT_GOAL := build

APP_NAME := GodoxBLEPoC
BUILD_DIR := Build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
EXECUTABLE := $(MACOS_DIR)/$(APP_NAME)
INFO_PLIST := Info.plist
ENTITLEMENTS := GodoxBLEPoC.entitlements
SOURCES := $(sort $(wildcard Sources/*.swift))

SWIFTC := $(shell xcrun --find swiftc)
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
TARGET_ARCH ?= $(shell uname -m)
MACOSX_DEPLOYMENT_TARGET ?= 13.0
SWIFTFLAGS ?= -parse-as-library

.PHONY: build run clean

build: $(EXECUTABLE)

$(EXECUTABLE): $(SOURCES) $(INFO_PLIST) $(ENTITLEMENTS)
	@if [[ -z "$(strip $(SOURCES))" ]]; then \
		print -u2 "No hay fuentes Swift en Sources/. Agrega main.swift antes de construir."; \
		exit 1; \
	fi
	@/usr/bin/plutil -lint $(INFO_PLIST) $(ENTITLEMENTS)
	@/bin/mkdir -p "$(MACOS_DIR)"
	@/bin/cp "$(INFO_PLIST)" "$(CONTENTS_DIR)/Info.plist"
	"$(SWIFTC)" \
		-emit-executable \
		-sdk "$(SDKROOT)" \
		-target "$(TARGET_ARCH)-apple-macosx$(MACOSX_DEPLOYMENT_TARGET)" \
		-framework Foundation \
		-framework CoreBluetooth \
		$(SWIFTFLAGS) \
		-o "$(EXECUTABLE)" \
		$(SOURCES)
	/usr/bin/codesign --force --sign - \
		--entitlements "$(ENTITLEMENTS)" \
		"$(APP_BUNDLE)"
	@/usr/bin/codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"
	@print "Construida: $(APP_BUNDLE)"

run: build
	@exec "$(EXECUTABLE)"

clean:
	@/bin/rm -rf -- "$(APP_BUNDLE)"
	@print "Eliminada: $(APP_BUNDLE)"
