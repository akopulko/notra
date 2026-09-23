SHELL := /bin/sh

.DEFAULT_GOAL := help

.PHONY: help lint build build-ios build-ios-simulator build-macos run-ios run-ios-phone run-ios-ipad run-macos privacy hooks

ifeq ($(origin CODE_SIGNING_ALLOWED),undefined)
run_code_signing_allowed := $(if $(wildcard Config/LocalSigning.xcconfig),YES,NO)
else
run_code_signing_allowed := $(CODE_SIGNING_ALLOWED)
endif


help:
	@printf '%s\n' 'Notra commands:'
	@printf '%s\n' '  make lint           Run SwiftFormat and SwiftLint checks'
	@printf '%s\n' '  make build          Build iOS, then macOS'
	@printf '%s\n' '  make build-ios      Build iOS simulator and device targets'
	@printf '%s\n' '  make build-macos    Build macOS target'
	@printf '%s\n' '  make run-ios        Build, sign when configured, and run the iOS phone simulator'
	@printf '%s\n' '  make run-ios-phone  Build, sign when configured, and run the iOS phone simulator'
	@printf '%s\n' '  make run-ios-ipad   Build, sign when configured, and run the iOS iPad simulator'
	@printf '%s\n' '  make run-macos      Build, sign when configured, and run macOS'
	@printf '%s\n' '  make privacy        Check staged files for private data'
	@printf '%s\n' '  make hooks          Install local git hooks'

lint:
	Scripts/lint.sh

build: build-ios build-macos

build-ios:
	Scripts/build_iOS.sh

build-ios-simulator:
	Scripts/build_iOS.sh simulator

build-macos:
	Scripts/build_macOS.sh

run-ios: run-ios-phone

run-ios-phone:
	CODE_SIGNING_ALLOWED="$(run_code_signing_allowed)" $(MAKE) build-ios-simulator
	Scripts/run_iOS.sh phone

run-ios-ipad:
	CODE_SIGNING_ALLOWED="$(run_code_signing_allowed)" $(MAKE) build-ios-simulator
	Scripts/run_iOS.sh ipad

run-macos:
	CODE_SIGNING_ALLOWED="$(run_code_signing_allowed)" $(MAKE) build-macos
	Scripts/run_macOS.sh

privacy:
	Scripts/check_privacy.sh

hooks:
	Scripts/install_git_hooks.sh
