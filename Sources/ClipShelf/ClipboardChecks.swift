import AppKit
import ClipShelfCore

// Runs against a unique pasteboard and temporary history, never the user's clipboard.
func runClipboardChecks() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipShelf-check-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("history.json")
    let model = ClipboardController(testBoard: board, storageURL: storage)
    func put(_ text: String) { board.clearContents(); board.setString(text, forType: .string); model.poll() }
    put("  سلام\nworld  ")
    precondition(model.history.clips.first?.text == "  سلام\nworld  ")
    let original = model.history.clips[0]
    model.togglePin(original)
    put("second"); put(original.text)
    precondition(model.history.clips.count == 2 && model.history.clips[0].pinned)
    model.paused = true
    put("private while paused")
    model.paused = false
    model.poll()
    precondition(model.history.clips.count == 2)
    board.clearContents()
    board.setString("sensitive", forType: .string)
    board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    model.poll()
    precondition(model.history.clips.count == 2)
    model.paste(original, copyOnly: true)
    precondition(board.string(forType: .string) == original.text)
    model.poll()
    precondition(model.history.clips.count == 2)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let first = directory.appendingPathComponent("file one.txt")
    let second = directory.appendingPathComponent("فارسی.txt")
    try Data("one".utf8).write(to: first); try Data("two".utf8).write(to: second)
    board.clearContents(); board.writeObjects([first as NSURL, second as NSURL]); model.poll()
    let files = model.history.clips[0]
    precondition(files.kind == .files && files.paths == [first.path, second.path])
    model.paste(files, copyOnly: true)
    let restored = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    precondition(restored?.map(\.path) == [first.path, second.path])
    try FileManager.default.removeItem(at: first)
    model.message = nil; model.paste(files, copyOnly: true)
    precondition(model.message?.contains("فایل پیدا نشد") == true)
    model.flush()
    let saved = try HistoryFile(url: storage).load()
    precondition(saved.clips == model.history.clips)
    let reloaded = ClipboardController(testBoard: board, storageURL: storage)
    precondition(reloaded.history.clips == model.history.clips)
    reloaded.clear(); reloaded.flush()
    let cleared = try HistoryFile(url: storage).load()
    precondition(cleared.clips.isEmpty)
    print("PASS: 10 clipboard integration checks (capture, dedup, pause, concealed, restore text, suppress self-capture, files, missing file, reload, clear)")
}
