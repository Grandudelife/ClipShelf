import AppKit
import SwiftUI

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let demo = CommandLine.arguments.contains("--demo")
    private lazy var model = ClipboardController(demo: demo)
    private let hotKey = GlobalShortcut()
    private var status: NSStatusItem!
    private var panel: ShelfPanel!
    private var settings: NSWindow?
    private var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "خروج از ClipShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.clipshelf.app")
        if !demo, others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            others.first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?.activate()
            NSApp.terminate(nil); return
        }
        panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 610),
                           styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "ClipShelf"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ShelfView(model: model, openSettings: { [weak self] in self?.showSettings() }))
        model.hide = { [weak self] in self?.panel.orderOut(nil) }
        model.shortcutChanged = { [weak self] in self?.hotKey.register($0) ?? false }
        hotKey.onPress = { [weak self] in self?.toggle() }
        if !demo, !hotKey.register(model.shortcut) { model.message = "میان‌بر قابل ثبت نیست؛ از تنظیمات ترکیب دیگری انتخاب کنید." }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipShelf")
        status.button?.target = self
        status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.toolTip = "ClipShelf — \(model.shortcut.label)"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            if event.keyCode == 53 { self.dismiss(); return nil }
            if event.keyCode == 125 { self.model.moveSelection(1); return nil }
            if event.keyCode == 126 { self.model.moveSelection(-1); return nil }
            if event.keyCode == 36 || event.keyCode == 76 {
                if self.model.isCreatingSnippet { self.model.saveSnippet() }
                else if let clip = self.model.selected { self.model.paste(clip) }
                return nil
            }
            if event.modifierFlags.contains(.command) {
                if let key = event.charactersIgnoringModifiers, let number = Int(key), (1...9).contains(number) {
                    let clips = self.model.visible
                    if number <= clips.count { self.model.paste(clips[number - 1]) }; return nil
                }
                if event.charactersIgnoringModifiers == "," { self.showSettings(); return nil }
                if event.keyCode == 51, let clip = self.model.selected { self.model.delete(clip); return nil }
                if event.charactersIgnoringModifiers == "w" { self.dismiss(); return nil }
            }
            return event
        }
        show()
    }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "نمایش تاریخچه", action: #selector(showFromMenu), keyEquivalent: "")
            menu.addItem(withTitle: model.paused ? "ادامهٔ ثبت" : "توقف ثبت", action: #selector(togglePause), keyEquivalent: "")
            menu.addItem(withTitle: "تنظیمات…", action: #selector(showSettings), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "خروج از ClipShelf", action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else { toggle() }
    }
    @objc private func showFromMenu() { show() }
    @objc private func togglePause() { model.paused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    private func toggle() { panel.isVisible && panel.isKeyWindow ? dismiss() : show() }
    private func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { model.targetApp = front }
        model.query = ""; model.synchronizeSelection()
        model.trusted = AXIsProcessTrusted()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .shelfOpened, object: nil)
    }
    private func dismiss() { panel.orderOut(nil); model.targetApp?.activate(options: [.activateIgnoringOtherApps]) }
    @objc private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 630),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "تنظیمات ClipShelf"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.level = .floating
            settings = window
        }
        panel.orderOut(nil); settings?.center(); settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationWillResignActive(_ notification: Notification) { panel?.orderOut(nil) }
    func applicationWillTerminate(_ notification: Notification) { model.flush(); if let monitor { NSEvent.removeMonitor(monitor) } }
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--self-test") {
    do { try runClipboardChecks(); exit(0) }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
