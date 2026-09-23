#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

configuration="${CONFIGURATION:-Debug}"
derived_data_path="${TMPDIR:-/tmp}/NotraDerivedData-macOS"
app_path="${derived_data_path}/Build/Products/${configuration}/Notra.app"

if [ ! -d "$app_path" ]; then
  printf '%s\n' "Notra.app was not found at: ${app_path}" >&2
  printf '%s\n' "Run make build-macos before running the app." >&2
  exit 1
fi

if ! bundle_identifier="$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleIdentifier' \
  "$app_path/Contents/Info.plist" 2>/dev/null)"; then
  printf '%s\n' "Could not resolve the app bundle identifier." >&2
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
