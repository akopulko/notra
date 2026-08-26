SHELL := /bin/sh

.DEFAULT_GOAL := help

.PHONY: help lint build build-ios build-macos run-ios run-ios-phone run-ios-ipad run-macos privacy hooks

help:
	@printf '%s\n' 'Notra commands:'
	@printf '%s\n' '  make lint           Run SwiftFormat and SwiftLint checks'
	@printf '%s\n' '  make build          Build iOS, then macOS'
	@printf '%s\n' '  make build-ios      Build iOS simulator and device targets'
	@printf '%s\n' '  make build-macos    Build macOS target'
	@printf '%s\n' '  make run-ios        Build and run the phone simulator'
	@printf '%s\n' '  make run-ios-phone  Build and run the phone simulator'
	@printf '%s\n' '  make run-ios-ipad   Build and run the iPad simulator'
	@printf '%s\n' '  make run-macos      Build and run macOS'
	@printf '%s\n' '  make privacy        Check staged files for private data'
	@printf '%s\n' '  make hooks          Install local git hooks'

lint:
	Scripts/lint.sh

build: build-ios build-macos

build-ios:
	Scripts/build_iOS.sh

build-macos:
	Scripts/build_macOS.sh

run-ios: run-ios-phone

run-ios-phone:
	Scripts/run_iOS.sh phone

run-ios-ipad:
	Scripts/run_iOS.sh ipad

run-macos:
	Scripts/run_macOS.sh

privacy:
	Scripts/check_privacy.sh

hooks:
	Scripts/install_git_hooks.sh
