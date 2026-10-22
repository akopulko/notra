#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Running SwiftFormat..."
swiftformat --lint --config ../.swiftformat --cache ignore ../Notra ../NotraShareExtension

echo "Running SwiftLint..."
swiftlint lint --config ../.swiftlint.yml --strict
