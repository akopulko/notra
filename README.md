# Notra

Notra is a SwiftUI notes app for iOS, iPadOS, and macOS. Notes are stored as TextBundle documents with Markdown content and local assets.

## Requirements

- Xcode with iOS 26+ and macOS 26+ SDKs
- SwiftFormat and SwiftLint available on your PATH

## Build

Run validation builds before opening a pull request:

```sh
Scripts/build_iOS.sh
Scripts/build_macOS.sh
```

The build scripts run SwiftFormat and SwiftLint in lint mode before compiling.

## Run

The run scripts build a Debug app, launch it, and stream logs:

```sh
Scripts/run_iOS.sh phone
Scripts/run_iOS.sh ipad
Scripts/run_macOS.sh
```

The iOS run script targets simulators. For a physical iPhone or iPad, open `Notra.xcodeproj` in Xcode and run the `Notra` scheme on the device.

## Local Signing and iCloud

The public project uses local-only storage by default and does not include a personal Apple Developer Team ID or iCloud container.

For private local signing, copy `Config/LocalSigning.xcconfig.example` to `Config/LocalSigning.xcconfig` and set your own values. The local file is ignored by git.

For private iCloud development:

```sh
cp Config/LocalSigning.xcconfig.example Config/LocalSigning.xcconfig
cp Config/LocalInfo-iCloud.plist.example Config/LocalInfo-iCloud.plist
```

Then replace the placeholder values with your own Apple Developer Team ID, bundle identifier, and iCloud container. Both local files are ignored by git.

When `Config/LocalSigning.xcconfig` exists, the run scripts allow code signing by default so private iCloud runs work without extra flags. You can still override this:

```sh
CODE_SIGNING_ALLOWED=NO Scripts/run_macOS.sh
CODE_SIGNING_ALLOWED=YES Scripts/run_iOS.sh phone
```

## Contributing

Use focused branches and keep changes small. Before opening a pull request, run both build scripts and make sure there are no warnings, SwiftFormat issues, or SwiftLint violations.

Install the local pre-commit privacy hook before your first commit:

```sh
Scripts/install_git_hooks.sh
```

The hook blocks staged local signing files, iCloud identifiers, Apple Developer Team IDs, credentials, private keys, crash reports, logs, databases, local Xcode state, and local user paths. It also reads your ignored local signing config at runtime and blocks those private values if they accidentally appear in staged files.

Do not commit local signing configuration, generated build output, crash reports, logs, personal notes, or private data.
