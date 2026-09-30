# ClipShelf

Native macOS clipboard history for the owner of this Mac. The confirmed task is to collect copied text and files, browse the history, and choose an earlier item with a configurable keyboard shortcut.

Implementation decisions: Swift/AppKit/SwiftUI, Persian UI, local persistence, menu-bar presence, plain text with optional RTF/HTML, clipboard images, newly saved macOS screenshot images, file-URL payloads, and user-authored snippets. Screenshot-folder import is optional and may require macOS Files & Folders access. These are implementation assumptions, not additional user requirements. The application does not upload history. Native paste automation requires Accessibility permission; manual copy remains available. OCR, cloud sync, and AI transformations are excluded to keep the app lightweight and local-first.
