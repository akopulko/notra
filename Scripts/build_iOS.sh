#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

configuration="${CONFIGURATION:-Debug}"
derived_data_path="${TMPDIR:-/tmp}/NotraDerivedData"
code_signing_allowed="${CODE_SIGNING_ALLOWED:-NO}"
build_scope="${1:-all}"

build_target() {
  description="$1"
  destination="$2"
  printf '%s\n' "Building ${description}..."
  xcodebuild build \
    -project Notra.xcodeproj \
    -scheme Notra \
    -configuration "$configuration" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    CODE_SIGNING_ALLOWED="$code_signing_allowed"
}

"$script_dir/lint.sh"

case "$build_scope" in
all)
  build_target "iOS Simulator app" 'generic/platform=iOS Simulator'
  build_target "physical iOS device app" 'generic/platform=iOS'
  ;;
simulator)
  build_target "iOS Simulator app" 'generic/platform=iOS Simulator'
  ;;
*)
  printf '%s\n' "Usage: Scripts/build_iOS.sh [all|simulator]" >&2
  exit 1
  ;;
esac
