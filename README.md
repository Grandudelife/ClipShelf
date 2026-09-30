# ClipShelf

ClipShelf is a lightweight macOS clipboard history app for plain text and files copied in Finder. It lives in the menu bar, keeps history locally, and lets you bring back an earlier item with a configurable global shortcut.

The interface is currently Persian (RTL). English localization is a welcome contribution.

## Features

- Captures plain text and one or more file URLs copied in Finder
- Search by text, file path, or source app
- Pin frequently used clips and filter by text, files, or pinned items
- Configurable global shortcut; default: `Control + Shift + V`
- Keyboard-first picker: arrow keys to navigate, Return to use, `⌘1`–`⌘9` for quick selection
- Optional automatic paste back into the previous app through macOS Accessibility permission
- Local JSON persistence, deduplication, adjustable history limit, and a pause switch
- Respects common concealed and transient pasteboard markers

## Requirements

- macOS 13 or later
- Xcode Command Line Tools or Xcode, with Swift 6 or later, to build from source

The code has no third-party dependencies.

## Install from source

```sh
git clone <your-repository-url> ClipShelf
cd ClipShelf
./build.sh
open ../ClipShelf.app
```

The script builds a signed, ad-hoc `ClipShelf.app` next to the repository and runs the core checks first. Move the app to `/Applications` if you prefer. Because the app is not notarized, macOS may ask you to confirm that you want to open a locally built copy.

The packaging script uses SwiftPM's native build system because it is the most reliable option for the Command Line Tools setup used to develop this project. SwiftPM currently prints a deprecation warning for that implementation; it does not affect the generated app. GitHub CI uses the normal SwiftPM build system.

## Use

1. Launch ClipShelf. It appears in the menu bar.
2. Copy text in any app, or copy one or more files in Finder with `⌘C`.
3. Press the global shortcut to open the picker.
4. Select a clip and press Return, double-click it, or use `⌘1`–`⌘9`.

Without Accessibility permission, ClipShelf restores the selected item to the clipboard and returns you to the previous app; press `⌘V` yourself. To enable automatic paste, open ClipShelf settings and use the Accessibility button. This permission is required because macOS protects synthesized keyboard input.

## Privacy and limits

ClipShelf never sends clipboard content over the network. History is stored at:

```text
~/Library/Application Support/ClipShelf/history.json
```

The history file has user-only permissions but is not separately encrypted. Pause recording before copying sensitive material. The app records only clips made while it is running; macOS does not expose clipboard history from before launch.

This version stores plain text and paths to files. It does not preserve rich text, HTML, raw image clipboard data, screenshots, or file promises. File contents are not copied into the history: if a remembered file has moved or been deleted, copy it again from Finder.

Default limits: 200 clips, 1 MB per clip, 20 MB total history, and 20 pinned clips. Change the clip count in Settings.

## Development

```sh
swift build
swift run ClipShelfChecks
swift run ClipShelf --demo
```

`ClipShelfChecks` runs seven deterministic core checks: deduplication, pin preservation, persistence, Unicode search, size limits, corrupt-history reporting, and distinct file-path identity.

For an additional pasteboard integration check in a normal graphical macOS session:

```sh
CLIPSHELF_GUI_CHECKS=1 ./build.sh
```

It uses an isolated named pasteboard and a temporary directory, not your personal clipboard or history.

## Current status

ClipShelf was manually tested for text capture, search, restoring a previous text clip, manual paste, shortcut configuration, and its macOS interface. Automatic paste into another app and a Finder file round trip still need a full end-to-end desktop test. Please report results in an issue if you test either flow.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). This project is released under the [MIT License](LICENSE).
