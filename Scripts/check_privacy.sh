#!/bin/sh
set -eu

staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"

if [ -z "$staged_files" ]; then
  printf '%s\n' "Privacy check: no staged files."
  exit 0
fi

failed=0

fail_file() {
  printf '%s\n' "Privacy check failed: $1" >&2
  failed=1
}

staged_content_contains() {
  file="$1"
  pattern="$2"
  allowed="${3:-}"

  matches="$(git show ":$file" 2>/dev/null | grep -En -- "$pattern" || true)"
  if [ -n "$allowed" ]; then
    matches="$(printf '%s\n' "$matches" | grep -Ev -- "$allowed" || true)"
  fi

  [ -n "$matches" ]
}

staged_content_contains_fixed() {
  file="$1"
  value="$2"

  git show ":$file" 2>/dev/null | grep -Fq "$value"
}

local_setting() {
  key="$1"
  file="Config/LocalSigning.xcconfig"

  if [ ! -f "$file" ]; then
    return 0
  fi

  awk -F '=' -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$file"
}

scan_private_value() {
  label="$1"
  value="$2"

  if [ -z "$value" ]; then
    return 0
  fi

  case "$value" in
  YOURTEAMID|com.yourname.Notra|iCloud.example.Notra|app.notra.Notra)
    return 0
    ;;
  esac

  old_ifs="$IFS"
  IFS='
'
  for file in $staged_files; do
    IFS="$old_ifs"
    if staged_content_contains_fixed "$file" "$value"; then
      printf '%s\n' "Privacy check failed: staged file contains local private ${label}: ${file}" >&2
      return 1
    fi
    IFS='
'
  done
  IFS="$old_ifs"
}

old_ifs="$IFS"
IFS='
'
for file in $staged_files; do
  IFS="$old_ifs"
  case "$file" in
  Config/LocalSigning.xcconfig|Config/LocalInfo-iCloud.plist|AGENTS.MD|AGENTS.md)
    fail_file "local-only file is staged: ${file}"
    ;;
  .env|.env.*|*/.env|*/.env.*)
    fail_file "environment file is staged: ${file}"
    ;;
  *.mobileprovision|*.provisionprofile|*.p12|*.p8|*.cer|*.pem|*.key)
    fail_file "signing or key material is staged: ${file}"
    ;;
  *.log|*.sqlite|*.sqlite-*|*.db|*.crash|*.ips|crashreport*|*/crashreport*)
    fail_file "log, database, or crash report is staged: ${file}"
    ;;
  *.xcuserstate|*/xcuserdata/*|.DS_Store|*/.DS_Store)
    fail_file "local Xcode or macOS file is staged: ${file}"
    ;;
  esac

  if staged_content_contains "$file" "-----BEGIN [A-Z ]*PRIVATE KEY-----"; then
    fail_file "private key block found in staged file: ${file}"
  fi

  if staged_content_contains "$file" "github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9_]{20,}"; then
    fail_file "GitHub token-looking value found in staged file: ${file}"
  fi

  if staged_content_contains "$file" "DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}" "YOURTEAMID"; then
    fail_file "Apple Developer Team ID-looking value found in staged file: ${file}"
  fi

  if staged_content_contains "$file" "iCloud\.[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+" "iCloud.example.Notra|LocalInfo-iCloud"; then
    fail_file "private iCloud container-looking value found in staged file: ${file}"
  fi

  if staged_content_contains "$file" "/Users/[A-Za-z0-9._-]+"; then
    fail_file "local user path found in staged file: ${file}"
  fi
  IFS='
'
done
IFS="$old_ifs"

private_team="$(local_setting DEVELOPMENT_TEAM || true)"
private_bundle="$(local_setting NOTRA_BUNDLE_IDENTIFIER || true)"
private_icloud="$(local_setting NOTRA_ICLOUD_CONTAINER_IDENTIFIER || true)"

if ! scan_private_value "Apple Developer Team ID" "$private_team"; then
  failed=1
fi
if ! scan_private_value "bundle identifier" "$private_bundle"; then
  failed=1
fi
if ! scan_private_value "iCloud container identifier" "$private_icloud"; then
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  printf '%s\n' "Privacy check blocked this commit." >&2
  exit 1
fi

printf '%s\n' "Privacy check passed."
