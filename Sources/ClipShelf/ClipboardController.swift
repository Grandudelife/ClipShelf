import AppKit
import ApplicationServices
import Carbon
import ClipShelfCore
import Combine

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
    @Published var paused = false { didSet { changeCount = board.changeCount } }
    @Published var message: String?
    @Published var shortcut = Shortcut()
    @Published var limit = 200
    @Published var autoPaste = true
    @Published var trusted = AXIsProcessTrusted()
    var targetApp: NSRunningApplication?
    var hide: (() -> Void)?
    var shortcutChanged: ((Shortcut) -> Bool)?
    private var timer: Timer?
    private var changeCount: Int
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
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        guard !paused else { return }
        // Respect the common sensitive/transient pasteboard conventions.
        let blocked = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                       "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType"]
        guard !blocked.contains(where: { board.types?.contains(.init($0)) == true }) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let clip: Clip
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            clip = Clip(paths: urls.map(\.path), source: source)
        } else if let text = board.string(forType: .string), !text.isEmpty {
            clip = Clip(text: text, source: source)
        } else { return }
        if history.insert(clip, limit: limit) { persist(); synchronizeSelection() }
        else { message = "این مورد ذخیره نشد؛ سقف اندازهٔ هر متن ۱ مگابایت است." }
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
        if clip.kind == .files { success = board.writeObjects(clip.paths.map { NSURL(fileURLWithPath: $0) }) }
        else { success = board.setString(clip.text, forType: .string) }
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
