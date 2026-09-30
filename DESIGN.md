# ClipShelf interface

Mode: Operate. Native macOS utility with a right-to-left Persian reading flow. The picker has a heading, search, type filters, history on the right, preview on the left, and a keyboard-help footer. Image preview and the snippet editor share the existing preview pane. Settings occupy a separate native window.

System typography at 25 pt for the picker heading, 13–15 pt for primary content, and 10–12 pt for supporting text. Use semantic window/control background and label colors so the interface follows the system appearance. The accent is RGB (0.12, 0.44, 0.38). Selected rows use the accent at 11% opacity. Primary horizontal padding is 24 pt, preview padding 22 pt, rows 12 pt, and row radius 9 pt.

Use SF Symbols for controls, native file icons for file previews, and standard macOS focus/selection behavior. Do not turn the utility into a decorative dashboard. Search and content remain primary; settings and recording pause remain visible but secondary. Keyboard guidance stays in the footer.

Verified visually in the running macOS application: empty picker, populated search/history, and settings. New screenshot, image, and snippet states still need a visual check on the rebuilt app. Automatic paste and Finder/screenshot image round trips still need end-to-end validation.
