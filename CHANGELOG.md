# Changelog

## 1.2.0

- Automatically add new macOS screenshot images saved in the configured screenshot folder to image history; PNG, JPEG, and TIFF are supported, and the feature can be disabled in settings.
- Wait for screenshot files to finish writing and enforce existing image size and pixel-count limits.

## 1.1.0

- Preserve available RTF and HTML clipboard representations alongside searchable plain text.
- Capture and preview PNG/TIFF clipboard images, and restore the original image representation on copy or paste. Image size and pixel-count limits help bound memory and disk use.
- Add a reusable snippet library with create, edit, search, filter, and paste actions.
- Ignore additional common transient, password-manager, typing-tool, and Universal Clipboard pasteboard markers.
- Raise the per-item cap to 8 MB while retaining the 20 MB total archive budget.

## 1.0.0

- Persian menu-bar clipboard history for plain text and Finder file URLs.
- Search, configurable global shortcut, pinning, local persistence, pause, and optional automatic paste.
