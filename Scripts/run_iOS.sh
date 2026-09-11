#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

configuration="${CONFIGURATION:-Debug}"
derived_data_path="${TMPDIR:-/tmp}/NotraDerivedData"
target="${1:-phone}"

if [ "${CODE_SIGNING_ALLOWED+x}" ]; then
  code_signing_allowed="$CODE_SIGNING_ALLOWED"
elif [ -f Config/LocalSigning.xcconfig ]; then
  code_signing_allowed="YES"
else
  code_signing_allowed="NO"
fi

case "$target" in
phone)
  device_name="iPhone 17"
  ;;
ipad)
  device_name="iPad (A16)"
  ;;
*)
  printf '%s\n' "Usage: Scripts/run_iOS.sh [phone|ipad]" >&2
  exit 1
  ;;
esac

device_id="$(xcrun simctl list devices available | awk -v name="$device_name" '
  index($0, "    " name " (") == 1 {
    for (field_index = 1; field_index <= NF; field_index++) {
      token = $field_index
      gsub(/[()]/, "", token)
      if (token ~ /^[[:xdigit:]-]{36}$/) {
        print token
        exit
      }
    }
  }
')"

if [ -z "$device_id" ]; then
  printf '%s\n' "The ${device_name} simulator is not available." >&2
  exit 1
fi

printf '%s\n' "Building Notra for ${device_name}..."
xcodebuild build \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration "$configuration" \
  -destination "platform=iOS Simulator,name=${device_name}" \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED="$code_signing_allowed"

build_settings="$(xcodebuild \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration "$configuration" \
  -destination "platform=iOS Simulator,name=${device_name}" \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED="$code_signing_allowed" \
  -showBuildSettings 2>/dev/null)"

app_path="$(printf '%s\n' "$build_settings" | awk -F ' = ' '
  $1 ~ /^[[:space:]]*TARGET_BUILD_DIR$/ {directory=$2}
  $1 ~ /^[[:space:]]*WRAPPER_NAME$/ {wrapper=$2}
  END {print directory "/" wrapper}
')"
bundle_identifier="$(printf '%s\n' "$build_settings" | awk -F ' = ' '
  $1 ~ /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER$/ {print $2; exit}
')"

if [ ! -d "$app_path" ]; then
  printf '%s\n' "Notra.app was not found at: ${app_path}" >&2
  exit 1
fi

if [ -z "$bundle_identifier" ]; then
  printf '%s\n' "Could not resolve PRODUCT_BUNDLE_IDENTIFIER." >&2
  exit 1
fi

device_state="$(xcrun simctl list devices | awk -v id="$device_id" '
  index($0, "(" id ")") > 0 {
    state = $0
    sub(/^.*\) \(/, "", state)
    sub(/\).*/, "", state)
    print state
    exit
  }
')"

if [ "$device_state" != "Booted" ]; then
  xcrun simctl boot "$device_id" 2>/dev/null || true
fi

# Xcode 27 replaces Simulator.app with Device Hub; retain the legacy fallback
# so this runner continues to work with older Xcode installations.
if open -a "Device Hub" 2>/dev/null; then
  :
else
  open -a Simulator
fi
xcrun simctl bootstatus "$device_id" -b
xcrun simctl terminate "$device_id" "$bundle_identifier" 2>/dev/null || true
xcrun simctl install "$device_id" "$app_path"
xcrun simctl launch "$device_id" "$bundle_identifier"

printf '%s\n' "Streaming Notra simulator logs. Press Ctrl-C to stop."
xcrun simctl spawn "$device_id" log stream \
  --style compact \
  --level debug \
  --predicate "subsystem == \"${bundle_identifier}\""
