#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

derived_data_path="${TMPDIR:-/tmp}/NotraDerivedData-macOS"
code_signing_allowed="${CODE_SIGNING_ALLOWED:-NO}"

"$script_dir/lint.sh"

xcodebuild build \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED="$code_signing_allowed"
