# Notra

Notra is a SwiftUI notes app for iOS, iPadOS, and macOS. Notes are stored as TextBundle documents with Markdown content and local assets.

## Sidebar organisation

On iOS, iPadOS, and macOS, unpinned notes are grouped by month in the current year and by year otherwise. Headings use the system calendar, time zone, and locale. **Date Edited** or **Date Created** selects the grouping date; **Latest First** or **Oldest First** controls section and row order. Pinned notes stay first, ordered by their pin timestamps.

Section headings use semibold headline text with a native horizontal divider extending after the title. **Pinned** uses the Markdown theme's italic colour; month and year headings use its h3 colour. Colours adapt to light and dark appearance.

Filter-only browsing keeps date sections. Typing a search query uses the **Pinned** and **Notes** sections instead, preserving search relevance within unpinned results.

The leading sidebar lists tags shared by notes, ordered by how many notes use each tag. It shows the ten most-used tags with **Show All** to expand the list to at most 100; **Show Less** returns to ten. Each note can have up to ten tags. Select one or more tags to show notes matching **any** selection; the list intersects that filter with text search. On compact iPhone layouts, use the sidebar navigation button to switch between tag filters and notes.

The **Images** section contains linked local images from the whole library. Tapping a thumbnail reveals its owning row and clears filters only if they hide that note. On iOS and iPadOS, this only scrolls the notes list; tap the row to select and open the note. On macOS, the thumbnail also selects and opens its owning note.

The revealed row briefly zooms to 108% scale and back with a spring animation, without a background fill or outline. Each thumbnail tap replays the effect, including another image from the same note. **Reduce Motion** disables the zoom.

## Markdown import on macOS

Use **File → Import…** to select one or more Markdown files. Each file becomes a separate note; importing the same file again creates another note.

## Markdown diagrams

Mermaid fenced blocks render locally in the preview and PDF export. The bundled Mermaid 12.0.0 runtime works offline; its upstream MIT license is included with the app resources. Diagram source stays editable Markdown and is preserved in Markdown exports. Use **Insert Mermaid Diagram** in the editor toolbar or iOS keyboard accessory to add a starter flowchart.

## Screenshots

Notra keeps the same focused writing workflow across Apple devices.

<p align="center">
  <img src="docs/assets/screenshots/notra-macos.png" alt="Notra running on macOS" width="820">
</p>

<p align="center">
  <img src="docs/assets/screenshots/notra-iphone.png" alt="Notra running on iPhone" width="220">
  <img src="docs/assets/screenshots/notra-ipad.png" alt="Notra running on iPad in landscape" width="520">
</p>

See the [privacy policy](docs/privacy.html) used for the App Store submission.

## Requirements

- Xcode 27 with iOS 27 and macOS 27 SDKs
- SwiftFormat and SwiftLint available on your PATH

## Build

Run validation builds before opening a pull request:

```sh
make build
```

This builds iOS first, then macOS. To build one platform at a time:

```sh
make build-ios
make build-macos
```

The build targets run SwiftFormat and SwiftLint in lint mode before compiling.

## Continuous integration and unit tests

`.github/workflows/ci.yml` runs for pull requests targeting `master` and pushes to `master`. It uses `dorny/paths-filter` v4 in Git mode with inline filters, requiring no separate filter file or PR API permission. Changes confined to `docs/` skip app validation; the lightweight **CI result** check still completes so required checks do not block website-only pull requests. Changes outside `docs/`, including mixed app/website changes, run the full validation.

CI uses GitHub's [`xcode-27` preview runner](https://github.com/actions/runner-images/issues/14404), currently running macOS 27, and explicitly selects Xcode 27.0. It checks SwiftFormat and SwiftLint, builds iOS simulator/device targets, runs unit tests on iPhone 17 with iOS 27.0, then builds and tests macOS natively. Platform builds and test runs are sequential. Compiler and linker warnings are treated as errors.

The workflow has read-only repository access, pins actions to full commit SHAs, does not persist checkout credentials, and requires no Apple signing secrets. Version comments identify each pinned release; unlike tags such as `v7`, these references cannot move to different code. CI does not run UI tests or change the separate Pages deployment. Configure branch protection on `master` to require **CI result**, not the conditionally skipped validation job.

Unit-test commands live directly in `ci.yml`, with no extra helper scripts or Python files. They use the shared `Notra` scheme, select only `NotraTests`, and use the public local-only configuration without personal signing credentials. `NotraUITests` remains available in Xcode but is not executed by CI. Run the `NotraTests` target in Xcode for local unit testing.

## Run

The run targets build the selected Debug app before launching it and stream logs. If the ignored `Config/LocalSigning.xcconfig` exists, they sign the build automatically; otherwise they use an unsigned build:

```sh
make run-ios
make run-ios-ipad
make run-macos
```

`make run-ios` uses the iPhone 17 simulator on iOS 27. The iOS run targets use simulators. For a physical iPhone or iPad, open `Notra.xcodeproj` in Xcode and run the `Notra` scheme on the device.

To override the automatic signing choice:

```sh
CODE_SIGNING_ALLOWED=NO make run-macos
CODE_SIGNING_ALLOWED=YES make run-ios
```

## Local Signing and iCloud

The public project uses local-only storage by default and does not include a personal Apple Developer Team ID or iCloud container.

For private local signing, copy `Config/LocalSigning.xcconfig.example` to `Config/LocalSigning.xcconfig` and set your own values. The local file is ignored by git.

For private iCloud development:

```sh
cp Config/LocalSigning.xcconfig.example Config/LocalSigning.xcconfig
cp Config/LocalInfo-iCloud.plist.example Config/LocalInfo-iCloud.plist
```

Then replace the placeholder values with your own Apple Developer Team ID, bundle identifier, and iCloud container. Both local files are ignored by git.

Build scripts default to unsigned builds. Override signing explicitly when building:

```sh
CODE_SIGNING_ALLOWED=NO make build-macos
CODE_SIGNING_ALLOWED=YES make build-ios
```

## Contributing

Use focused branches and keep changes small. Before opening a pull request, run both build scripts, run `NotraTests` in Xcode, and make sure there are no warnings, SwiftFormat issues, SwiftLint violations, or failing unit tests.

Install the local pre-commit privacy hook before your first commit:

```sh
Scripts/install_git_hooks.sh
```

The hook blocks staged local signing files, iCloud identifiers, Apple Developer Team IDs, credentials, private keys, crash reports, logs, databases, local Xcode state, and local user paths. It also reads your ignored local signing config at runtime and blocks those private values if they accidentally appear in staged files.

Do not commit local signing configuration, generated build output, crash reports, logs, personal notes, or private data.
