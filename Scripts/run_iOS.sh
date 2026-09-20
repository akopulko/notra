#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

configuration="${CONFIGURATION:-Debug}"
derived_data_path="${TMPDIR:-/tmp}/NotraDerivedData"
runtime="iOS 27.0"
target="${1:-phone}"

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

device_id="$(xcrun simctl list devices available "$runtime" | awk -v name="$device_name" '
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
  printf '%s\n' "The ${device_name} simulator is not available on iOS 27." >&2
  exit 1
fi

app_path="${derived_data_path}/Build/Products/${configuration}-iphonesimulator/Notra.app"
if [ ! -d "$app_path" ]; then
  printf '%s\n' "Notra.app was not found at: ${app_path}" >&2
  printf '%s\n' "Run make build-ios before running the app." >&2
  exit 1
fi

if ! bundle_identifier="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleIdentifier' \
  "$app_path/Info.plist" 2>/dev/null)"; then
  printf '%s\n' "Could not resolve the app bundle identifier." >&2
  exit 1
fi

device_state="$(xcrun simctl list devices available "$runtime" | awk -v id="$device_id" '
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

open -a "Device Hub"
xcrun simctl bootstatus "$device_id" -b
xcrun simctl terminate "$device_id" "$bundle_identifier" 2>/dev/null || true
xcrun simctl install "$device_id" "$app_path"
xcrun simctl launch "$device_id" "$bundle_identifier"

printf '%s\n' "Streaming Notra simulator logs. Press Ctrl-C to stop."
xcrun simctl spawn "$device_id" log stream \
  --style compact \
  --level debug \
  --predicate "subsystem == \"${bundle_identifier}\""
