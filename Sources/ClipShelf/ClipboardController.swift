import AppKit
import ApplicationServices
import Carbon
import ClipShelfCore
import Combine
import ImageIO
import UniformTypeIdentifiers

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32 = 9
    var key: String = "V"
    var control = true
    var option = false
    var shift = true
    var command = false
    var modifiers: UInt32 {
        (control ? UInt32(controlKey) : 0) | (option ? UInt32(optionKey) : 0) |
        (shift ? UInt32(shiftKey) : 0) | (command ? UInt32(cmdKey) : 0)
    }
    var label: String { (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key }
    static let keys: [(String, UInt32)] = [
        ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),("H",4),
        ("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),("O",31),("P",35),
        ("Q",12),("R",15),("S",1),("T",17),("U",32),("V",9),("W",13),("X",7),("Y",16),("Z",6),
        ("Space",49)
    ]
}

final class GlobalShortcut {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().onPress?()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: Shortcut) -> Bool {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        let identifier = EventHotKeyID(signature: 0x43534846, id: 1)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                   GetApplicationEventTarget(), 0, &reference) == noErr
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class ClipboardController: ObservableObject {
    @Published var history = History()
    @Published var query = ""
    @Published var filter = "all"
    @Published var selection: UUID?
    @Published var paused = false {
        didSet { changeCount = board.changeCount; screenshotScanStartedAt = Date(); screenshotObservations.removeAll() }
    }
    @Published var message: String?
    @Published var shortcut = Shortcut()
    @Published var limit = 200
    @Published var autoPaste = true
    @Published var importSavedScreenshots = true
    @Published var isCreatingSnippet = false
    @Published var snippetTitle = ""
    @Published var snippetBody = ""
    @Published var editingSnippetID: UUID?
    @Published var trusted = AXIsProcessTrusted()
    var targetApp: NSRunningApplication?
    var hide: (() -> Void)?
    var shortcutChanged: ((Shortcut) -> Bool)?
    private var timer: Timer?
    private var changeCount: Int
    private var screenshotScanStartedAt = Date()
    private var lastScreenshotScan = Date.distantPast
    private var screenshotObservations: [URL: (size: Int, firstSeen: Date)] = [:]
    private var importedScreenshotVersions = Set<String>()
    private var screenshotAccessNoticeShown = false
    private let board: NSPasteboard
    private let file: HistoryFile
    private let saveQueue = DispatchQueue(label: "clipshelf.persistence")
    private var persistenceEnabled = true
    let demo: Bool

    init(demo: Bool = false, testBoard: NSPasteboard? = nil, storageURL: URL? = nil) {
        self.demo = demo
        board = testBoard ?? (demo ? NSPasteboard(name: .init("ClipShelf.demo")) : .general)
        changeCount = board.changeCount
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = HistoryFile(url: storageURL ?? support.appendingPathComponent("ClipShelf/history.json"))
        if let data = UserDefaults.standard.data(forKey: "shortcut"),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) { shortcut = saved }
        let savedLimit = UserDefaults.standard.integer(forKey: "historyLimit")
        if [50, 100, 200, 500].contains(savedLimit) { limit = savedLimit }
        if UserDefaults.standard.object(forKey: "autoPaste") != nil { autoPaste = UserDefaults.standard.bool(forKey: "autoPaste") }
        if UserDefaults.standard.object(forKey: "importSavedScreenshots") != nil {
            importSavedScreenshots = UserDefaults.standard.bool(forKey: "importSavedScreenshots")
        }
        if demo {
            var pinned = Clip(text: "ایده‌های خوب را نگه دار.\nهر چیزی که کپی می‌کنی، همین‌جا در دسترس است.", source: "Notes"); pinned.pinned = true
            history = History(clips: [
                Clip(text: "جلسهٔ طراحی سه‌شنبه، ساعت ۱۰ صبح\nبررسی طرح اولیه و برنامهٔ هفتهٔ آینده", source: "Notes"),
                Clip(paths: ["/Users/demo/Documents/پیشنهاد پروژه.pdf", "/Users/demo/Documents/بودجه.xlsx"], source: "Finder"),
                Clip(text: "https://developer.apple.com/swift/", source: "Safari"),
                Clip(text: "let ideas = clipboard.history\nlet next = ideas.first", source: "Xcode"), pinned
            ])
        } else {
            do { history = try file.load(); history.trim(limit: limit) }
            catch {
                persistenceEnabled = false
                message = "خواندن تاریخچه ناموفق بود. برای حفظ فایل قبلی، این نشست فقط در حافظه نگه داشته می‌شود."
            }
            if testBoard == nil { timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() } }
        }
        selection = visible.first?.id
    }
    var visible: [Clip] {
        history.sorted.filter {
            $0.matches(query) && (filter == "all" || (filter == "pinned" ? $0.pinned : $0.kind.rawValue == filter))
        }
    }
    var selected: Clip? { visible.first { $0.id == selection } }
    func synchronizeSelection() {
        if !visible.contains(where: { $0.id == selection }) { selection = visible.first?.id }
    }
    func moveSelection(_ offset: Int) {
        let list = visible
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selection } ?? 0
        selection = list[min(max(current + offset, 0), list.count - 1)].id
    }
    func poll() {
        trusted = AXIsProcessTrusted()
        if !paused && importSavedScreenshots { scanForSavedScreenshots() }
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        guard !paused else { return }
        // Respect the common sensitive/transient pasteboard conventions.
        let blocked = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                       "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword",
                       "com.typeit4me.clipping", "net.antelle.keeweb",
                       "de.petermaurer.TransientPasteboardType", "Pasteboard generator type",
                       "com.apple.is-remote-clipboard"]
        guard !blocked.contains(where: { board.types?.contains(.init($0)) == true }) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let clip: Clip
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            clip = Clip(paths: urls.map(\.path), source: source)
        } else if let image = imagePayload(from: board) {
            clip = Clip(imageData: image.data, imageType: image.type, source: source)
        } else if let text = board.string(forType: .string), !text.isEmpty {
            var captured = Clip(text: text, source: source)
            for type in [NSPasteboard.PasteboardType.rtf, .html] {
                if let rich = board.data(forType: type), !rich.isEmpty {
                    captured.richType = type.rawValue
                    captured.richData = rich
                    break
                }
            }
            clip = captured
        } else { return }
        if history.insert(clip, limit: limit) { persist(); synchronizeSelection() }
        else { message = "این مورد ذخیره نشد؛ سقف اندازهٔ هر مورد ۸ مگابایت است." }
    }
    private func imagePayload(from pasteboard: NSPasteboard) -> (data: Data, type: String)? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), !data.isEmpty,
               data.count <= History.itemByteLimit,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int,
               width > 0, height > 0, width <= 16_000, height <= 16_000,
               width <= 24_000_000 / height {
                return (data, type.rawValue)
            }
        }
        return nil
    }
    private func scanForSavedScreenshots() {
        let now = Date()
        guard now.timeIntervalSince(lastScreenshotScan) >= 2 else { return }
        lastScreenshotScan = now
        let directory = screenshotDirectory()
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
            )
        } catch {
            if !screenshotAccessNoticeShown {
                message = "برای خواندن پوشهٔ اسکرین‌شات‌ها، دسترسی Files & Folders مک را به ClipShelf بدهید؛ ثبت کلیپ‌بورد همچنان فعال است."
                screenshotAccessNoticeShown = true
            }
            return
        }

        for url in files where isScreenshotFilename(url.lastPathComponent) &&
            ["png", "jpg", "jpeg", "tif", "tiff"].contains(url.pathExtension.lowercased()) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]),
                  values.isRegularFile == true, let size = values.fileSize,
                  let created = values.creationDate, created >= screenshotScanStartedAt.addingTimeInterval(-1),
                  size > 0, size <= History.itemByteLimit else { continue }
            let version = "\(url.path)|\(size)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            guard !importedScreenshotVersions.contains(version) else { continue }
            guard let observation = screenshotObservations[url], observation.size == size,
                  now.timeIntervalSince(observation.firstSeen) >= 1,
                  let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) >= 0.8 else {
                screenshotObservations[url] = (size, now)
                continue
            }
            importedScreenshotVersions.insert(version)
            screenshotObservations[url] = nil
            guard let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 16_000, height <= 16_000,
                  width <= 24_000_000 / height else { continue }
            let imageType = UTType(filenameExtension: url.pathExtension)?.identifier ?? NSPasteboard.PasteboardType.png.rawValue
            let clip = Clip(imageData: data, imageType: imageType, source: "اسکرین‌شات")
            if history.insert(clip, limit: limit) { persist(); synchronizeSelection() }
        }
    }
    private func screenshotDirectory() -> URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !location.isEmpty {
            let expanded = (location as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
    private func isScreenshotFilename(_ filename: String) -> Bool {
        let name = filename.lowercased()
        let prefixes = ["screenshot", "screen shot", "bildschirmfoto", "capture d’écran", "capture d'ecran",
                        "captura de pantalla", "снимок экрана", "スクリーンショット", "屏幕快照", "截屏", "ekran resmi"]
        return prefixes.contains { name.hasPrefix($0) }
    }
    func persist() {
        guard !demo, persistenceEnabled else { return }
        let snapshot = history, file = file
        saveQueue.async { [weak self] in
            do { try file.save(snapshot) }
            catch { DispatchQueue.main.async { self?.message = "ذخیره روی دیسک ناموفق بود؛ فضای خالی و مجوز پوشه را بررسی کنید." } }
        }
    }
    func flush() { saveQueue.sync {} }
    func togglePin(_ clip: Clip) {
        guard let index = history.clips.firstIndex(where: { $0.id == clip.id }) else { return }
        if !clip.pinned && history.clips.filter(\.pinned).count >= 20 {
            message = "حداکثر ۲۰ مورد را می‌توانید سنجاق کنید."; return
        }
        history.clips[index].pinned.toggle(); persist(); synchronizeSelection()
    }
    func beginSnippet(from clip: Clip? = nil) {
        isCreatingSnippet = true
        snippetTitle = clip.map { String($0.title.prefix(60)) } ?? ""
        snippetBody = clip?.text ?? ""
        editingSnippetID = clip?.kind == .snippet ? clip?.id : nil
    }
    func saveSnippet() {
        let title = snippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !snippetBody.isEmpty else {
            message = "برای اسنیپت یک عنوان و متن وارد کنید."; return
        }
        if let id = editingSnippetID, let index = history.clips.firstIndex(where: { $0.id == id && $0.kind == .snippet }) {
            var replacement = Clip(snippetTitle: String(title.prefix(60)), text: snippetBody)
            replacement.id = id
            let updatedSize = history.clips.reduce(0) { $0 + ($1.id == id ? replacement.size : $1.size) }
            guard replacement.size <= History.itemByteLimit, updatedSize <= History.byteLimit else {
                message = "اسنیپت از سقف اندازهٔ مجاز بزرگ‌تر است."; return
            }
            history.clips[index] = replacement
            persist(); synchronizeSelection()
        } else if !history.insert(Clip(snippetTitle: String(title.prefix(60)), text: snippetBody), limit: limit) {
            message = "اسنیپت ذخیره نشد؛ سقف تعداد یا اندازهٔ اسنیپت‌ها پر شده است."; return
        } else {
            persist(); synchronizeSelection()
        }
        filter = "snippet"; query = ""; isCreatingSnippet = false
        editingSnippetID = nil
        message = "اسنیپت ذخیره شد."
    }
    func cancelSnippet() { isCreatingSnippet = false; snippetTitle = ""; snippetBody = ""; editingSnippetID = nil }
    func delete(_ clip: Clip) {
        history.clips.removeAll { $0.id == clip.id }; persist(); synchronizeSelection()
    }
    func clear() {
        history.clips.removeAll(); selection = nil; persist()
    }
    func setLimit(_ value: Int) {
        limit = value; history.trim(limit: value)
        UserDefaults.standard.set(value, forKey: "historyLimit"); persist(); synchronizeSelection()
    }
    func setAutoPaste(_ value: Bool) {
        autoPaste = value; UserDefaults.standard.set(value, forKey: "autoPaste")
    }
    func setImportSavedScreenshots(_ value: Bool) {
        importSavedScreenshots = value
        UserDefaults.standard.set(value, forKey: "importSavedScreenshots")
        if value { screenshotScanStartedAt = Date(); screenshotObservations.removeAll() }
    }
    func setShortcut(_ value: Shortcut) -> Bool {
        guard value.control || value.option || value.command else {
            message = "میان‌بر باید Control، Option یا Command داشته باشد."; return false
        }
        let old = shortcut
        guard shortcutChanged?(value) == true else {
            _ = shortcutChanged?(old)
            message = "این میان‌بر در دسترس نیست؛ ترکیب دیگری انتخاب کنید."; return false
        }
        shortcut = value
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "shortcut")
        message = "میان‌بر جدید ذخیره شد: \(value.label)"
        return true
    }
    func paste(_ clip: Clip, copyOnly: Bool = false) {
        guard !demo else { message = "این پنجره پیش‌نمایش آزمایشی است."; return }
        if clip.kind == .files {
            let missing = clip.paths.filter { !FileManager.default.fileExists(atPath: $0) }
            guard missing.isEmpty else {
                message = "فایل پیدا نشد: \(URL(fileURLWithPath: missing[0]).lastPathComponent). آن را از Finder دوباره کپی کنید."; return
            }
        }
        board.clearContents()
        let success: Bool
        switch clip.kind {
        case .files:
            success = board.writeObjects(clip.paths.map { NSURL(fileURLWithPath: $0) })
        case .image:
            let item = NSPasteboardItem()
            if let data = clip.imageData, let type = clip.imageType {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: type))
                success = board.writeObjects([item])
            } else { success = false }
        case .text, .snippet:
            if let data = clip.richData, let type = clip.richType {
                let item = NSPasteboardItem()
                item.setString(clip.text, forType: .string)
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: type))
                success = board.writeObjects([item])
            } else { success = board.setString(clip.text, forType: .string) }
        }
        changeCount = board.changeCount
        guard success else { message = "کپی انجام نشد؛ دوباره امتحان کنید."; return }
        trusted = AXIsProcessTrusted()
        let destination = targetApp
        let shouldPaste = !copyOnly && autoPaste && trusted && destination != nil && destination?.isTerminated == false
        hide?()
        destination?.activate(options: [.activateIgnoringOtherApps])
        guard shouldPaste, let destination else { return }
        // Wait for the destination and released shortcut modifiers, then verify focus.
        sendPaste(to: destination, attempts: 20)
    }
    private func sendPaste(to app: NSRunningApplication, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let held = !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, !held else {
                if attempts > 0 { self.sendPaste(to: app, attempts: attempts - 1) }
                return
            }
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
        }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
