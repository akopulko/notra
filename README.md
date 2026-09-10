# Notra

Notra is a SwiftUI notes app for iOS, iPadOS, and macOS. Notes are stored as TextBundle documents with Markdown content and local assets.

## Screenshots

Notra keeps the same focused writing workflow across Apple devices.

<p align="center">
  <img src="notra-app-landing-page/assets/screenshots/notra-macos.png" alt="Notra running on macOS" width="820">
</p>

<p align="center">
  <img src="notra-app-landing-page/assets/screenshots/notra-iphone.png" alt="Notra running on iPhone" width="220">
  <img src="notra-app-landing-page/assets/screenshots/notra-ipad.png" alt="Notra running on iPad in landscape" width="520">
</p>

See the [privacy policy](notra-app-landing-page/privacy.html) used for the App Store submission.

## Requirements

- Xcode with iOS 26+ and macOS 26+ SDKs
- SwiftFormat and SwiftLint available on your PATH

## Build

Run validation builds before opening a pull request:

```sh
make build
```

This builds iOS first, then macOS. To run one platform at a time:

```sh
make build-ios
make build-macos
```

The build targets run SwiftFormat and SwiftLint in lint mode before compiling.

## Run

The run scripts build a Debug app, launch it, and stream logs:

```sh
make run-ios
make run-ios-ipad
make run-macos
```

`make run-ios` uses the phone simulator. The iOS run targets use simulators. For a physical iPhone or iPad, open `Notra.xcodeproj` in Xcode and run the `Notra` scheme on the device.

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
