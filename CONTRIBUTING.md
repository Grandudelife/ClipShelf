# Contributing to ClipShelf

Thank you for improving ClipShelf.

## Before opening a pull request

1. Create a focused branch and keep the change scoped to one problem.
2. Run `swift build` and `swift run ClipShelfChecks`.
3. If you change clipboard capture, automatic paste, shortcuts, or persistence, describe the manual macOS test you performed.
4. Update `README.md` when the user-facing behavior, a limit, or a requirement changes.

## Code style

- Use Swift and the existing AppKit/SwiftUI architecture; avoid adding dependencies for small utilities.
- Preserve the privacy model: do not add analytics, network requests, or clipboard uploads.
- Keep UI text accessible and account for right-to-left layout. New user-facing strings should be localizable.
- Do not log clipboard contents.

## Pull request description

State the user-visible problem, the resulting behavior, and validation. Screenshots help for UI changes. Include a note when a flow requires Accessibility permission.

## Reporting bugs

Please include macOS version, Mac architecture, ClipShelf revision, exact steps, expected behavior, actual behavior, and whether Accessibility permission was enabled. Never paste secrets or sensitive clipboard contents into an issue.
