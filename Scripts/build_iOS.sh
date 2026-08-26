#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

"$script_dir/lint.sh"

code_signing_allowed="${CODE_SIGNING_ALLOWED:-NO}"

printf '%s\n' "Building iOS Simulator app..."
xcodebuild build \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED="$code_signing_allowed"

printf '%s\n' "Building physical iOS device app..."
xcodebuild build \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED="$code_signing_allowed"
