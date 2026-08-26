#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

configuration="${CONFIGURATION:-Debug}"
derived_data_path="${TMPDIR:-/tmp}/NotraDerivedData"

if [ "${CODE_SIGNING_ALLOWED+x}" ]; then
  code_signing_allowed="$CODE_SIGNING_ALLOWED"
elif [ -f Config/LocalSigning.xcconfig ]; then
  code_signing_allowed="YES"
else
  code_signing_allowed="NO"
fi

printf '%s\n' "Building Notra for macOS..."
xcodebuild build \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration "$configuration" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data_path" \
  CODE_SIGNING_ALLOWED="$code_signing_allowed"

build_settings="$(xcodebuild \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration "$configuration" \
  -destination 'generic/platform=macOS' \
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

if pgrep -x Notra >/dev/null; then
  printf '%s\n' "Stopping existing Notra process..."
  osascript -e "tell application id \"$bundle_identifier\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pkill -x Notra 2>/dev/null || true
fi

printf '%s\n' "Streaming Notra logs. Press Ctrl-C to stop."
/usr/bin/log stream \
  --style compact \
  --level debug \
  --predicate "subsystem == \"${bundle_identifier}\"" &
log_pid="$!"

trap 'kill "$log_pid" 2>/dev/null || true' EXIT INT TERM
open "$app_path"
wait "$log_pid"
