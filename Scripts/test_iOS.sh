#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

configuration="${CONFIGURATION:-Debug}"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/NotraIOSTests.XXXXXXXX")"
bundle_identifier="app.notra.Notra.verification$(date +%s)$$"
destination="${IOS_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=27.0}"

printf '%s\n' "Running iOS unit tests with local storage. Results: ${verification_dir}"

xcodebuild test \
  -project Notra.xcodeproj \
  -scheme Notra \
  -configuration "$configuration" \
  -destination "$destination" \
  -derivedDataPath "$verification_dir/DerivedData" \
  -resultBundlePath "$verification_dir/TestResults.xcresult" \
  -clonedSourcePackagesDirPath "$verification_dir/SourcePackages" \
  -packageCachePath "$verification_dir/PackageCache" \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 300 \
  -collect-test-diagnostics never \
  -enablePerformanceTestsDiagnostics NO \
  -only-testing:NotraTests \
  NOTRA_BUNDLE_IDENTIFIER="$bundle_identifier" \
  NOTRA_INFO_PLIST_FILE=NotraInfo.plist \
  NOTRA_CODE_SIGN_ENTITLEMENTS=Notra/Notra.entitlements \
  NOTRA_IOS_CODE_SIGN_ENTITLEMENTS=Notra/Notra-iOS.entitlements \
  NOTRA_APP_GROUP_IDENTIFIER="group.$bundle_identifier" \
  NOTRA_ICLOUD_CONTAINER_IDENTIFIER= \
  DEVELOPMENT_TEAM= \
  CODE_SIGNING_ALLOWED=NO \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_SUPPRESS_WARNINGS=NO \
  SDKROOT=iphonesimulator \
  'SUPPORTED_PLATFORMS=iphoneos iphonesimulator macosx' \
  'OTHER_LDFLAGS=$(inherited) -Wl,-fatal_warnings'
