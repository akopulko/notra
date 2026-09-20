#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

configuration="${CONFIGURATION:-Debug}"
derived_data_path="${TMPDIR:-/tmp}/NotraDerivedData"
code_signing_allowed="${CODE_SIGNING_ALLOWED:-NO}"

"$script_dir/lint.sh"

printf '%s\n' "Building iOS Simulator app..."
xcodebuild build \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration "$configuration" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED="$code_signing_allowed"

printf '%s\n' "Building physical iOS device app..."
xcodebuild build \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration "$configuration" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED="$code_signing_allowed"
