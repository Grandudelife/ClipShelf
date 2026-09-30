import SwiftUI
import AppKit
import ClipShelfCore

private typealias StoredState<Value> = SwiftUI.State<Value>

private let accent = Color(red: 0.12, green: 0.44, blue: 0.38)

struct ShelfView: View {
    @ObservedObject var model: ClipboardController
    var openSettings: () -> Void
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("کپی‌های شما").font(.system(size: 25, weight: .bold))
                    Text(model.paused ? "ثبت تاریخچه متوقف است" : "متن‌ها و فایل‌ها، آمادهٔ استفادهٔ دوباره")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("ClipShelf").font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 17)) }
                    .buttonStyle(.plain).help("تنظیمات و میان‌بر").accessibilityLabel("تنظیمات")
            }.padding(.horizontal, 24).padding(.top, 23).padding(.bottom, 19)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("جست‌وجو در متن‌ها، فایل‌ها و برنامه‌ها…", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($searchFocused)
                    .onChange(of: model.query) { _ in model.synchronizeSelection() }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("پاک کردن جست‌وجو")
                }
                Text(model.shortcut.label).font(.system(size: 12, design: .monospaced))
                    .environment(\.layoutDirection, .leftToRight).foregroundStyle(.secondary)
            }.padding(13).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
            HStack(spacing: 6) {
                filterButton("همه", "all"); filterButton("متن", "text")
                filterButton("فایل", "files"); filterButton("سنجاق‌شده", "pinned")
                Spacer()
                Text("\(model.visible.count) مورد").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            HStack(spacing: 0) {
                clipList.frame(width: 357)
                Divider()
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let message = model.message {
                HStack {
                    Image(systemName: "info.circle")
                    Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.message = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("بستن پیام")
                }.foregroundStyle(.primary).padding(12).background(accent.opacity(0.09))
            }
            Divider()
            HStack(spacing: 14) {
                Button { model.paused.toggle() } label: {
                    Label(model.paused ? "ادامهٔ ثبت" : "توقف ثبت", systemImage: model.paused ? "play.circle" : "pause.circle")
                }.buttonStyle(.plain).foregroundStyle(model.paused ? Color.orange : .secondary)
                Spacer()
                Text("↑ ↓ انتخاب    ↩ استفاده    ⌘1…9 انتخاب سریع    esc بستن")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 13)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.layoutDirection, .rightToLeft)
        .tint(accent)
        .onAppear { searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .shelfOpened)) { _ in searchFocused = true }
    }
    private func filterButton(_ title: String, _ value: String) -> some View {
        Button { model.filter = value; model.synchronizeSelection() } label: {
            Text(title).font(.system(size: 12, weight: model.filter == value ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(model.filter == value ? accent.opacity(0.12) : .clear, in: Capsule())
                .foregroundStyle(model.filter == value ? accent : .secondary)
        }.buttonStyle(.plain)
    }
    private var clipList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if model.visible.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                                .font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                            Text(model.history.clips.isEmpty ? "اولین کپی، شروع کار است" : "موردی پیدا نشد")
                                .font(.system(size: 16, weight: .semibold))
                            Text(model.history.clips.isEmpty ? "در هر برنامه متنی را کپی کنید، یا در Finder یک فایل را با ⌘C کپی کنید." : "جست‌وجو یا فیلتر را تغییر دهید.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(30).padding(.top, 50)
                    }
                    ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, clip in
                        clipRow(clip, index: index).id(clip.id)
                    }
                }.padding(9)
            }
            .onChange(of: model.selection) { id in if let id { proxy.scrollTo(id, anchor: .center) } }
        }
    }
    private func clipRow(_ clip: Clip, index: Int) -> some View {
        let selected = model.selection == clip.id
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: clip.kind == .files ? "doc.on.doc" : "text.alignright")
                .font(.system(size: 16)).foregroundStyle(selected ? accent : .secondary)
                .frame(width: 24).padding(.top, 3)
            VStack(alignment: .leading, spacing: 7) {
                Text(clip.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if clip.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(accent) }
                    Text(clip.source)
                    if clip.kind == .files { Text("· \(clip.paths.count) فایل") }
                    Spacer()
                    if index < 9 { Text("⌘\(index + 1)").font(.system(size: 10, design: .monospaced)) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 73, alignment: .leading)
        .background(selected ? accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.paste(clip) }
        .onTapGesture { model.selection = clip.id }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityAction { model.selection = clip.id }
        .contextMenu {
            Button("استفاده") { model.paste(clip) }
            Button("فقط کپی") { model.paste(clip, copyOnly: true) }
            Button(clip.pinned ? "برداشتن سنجاق" : "سنجاق کردن") { model.togglePin(clip) }
            Divider()
            Button("حذف از تاریخچه", role: .destructive) { model.delete(clip) }
        }
    }
    @ViewBuilder private var preview: some View {
        if let clip = model.selected {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(clip.kind == .text ? "پیش‌نمایش متن" : "فایل‌های کپی‌شده")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.togglePin(clip) } label: { Image(systemName: clip.pinned ? "pin.fill" : "pin") }
                        .buttonStyle(.plain).foregroundStyle(clip.pinned ? accent : .secondary)
                        .help(clip.pinned ? "برداشتن سنجاق" : "سنجاق کردن")
                        .accessibilityLabel(clip.pinned ? "برداشتن سنجاق" : "سنجاق کردن")
                    Button { model.delete(clip) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("حذف از تاریخچه")
                        .accessibilityLabel("حذف از تاریخچه")
                }
                ScrollView {
                    if clip.kind == .text {
                        Text(clip.text).font(.system(size: 15)).lineSpacing(6).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(clip.paths, id: \.self) { path in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 14, weight: .medium))
                                        Text(path).font(.system(size: 10)).foregroundStyle(.secondary)
                                            .environment(\.layoutDirection, .leftToRight).textSelection(.enabled)
                                    }
                                }
                            }
                            Text("فایل اصلی باید در همین مسیر موجود باشد. خودِ فایل در تاریخچه تکثیر نمی‌شود.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 5) {
                    Text(clip.source + " · " + clip.date.formatted(date: .abbreviated, time: .shortened))
                    if clip.kind == .text { Text("\(clip.text.count) نویسه · متن ساده") }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                if model.autoPaste && !model.trusted {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("فعلاً مورد انتخابی کپی می‌شود؛ در برنامهٔ مقصد ⌘V بزنید.")
                        Button("فعال‌کردن Paste خودکار…") { model.requestAccessibility() }.buttonStyle(.link)
                    }.font(.system(size: 11))
                }
                HStack {
                    Button("فقط کپی") { model.paste(clip, copyOnly: true) }.buttonStyle(.bordered)
                    Spacer()
                    Button { model.paste(clip) } label: {
                        Text(model.autoPaste && model.trusted ? "Paste در برنامهٔ قبلی  ↩" : "کپی و بازگشت  ↩")
                            .font(.system(size: 12, weight: .semibold)).padding(.vertical, 4)
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(22)
        } else {
            VStack(spacing: 15) {
                Image(systemName: "square.on.square").font(.system(size: 35, weight: .ultraLight)).foregroundStyle(accent)
                Text("کپی کن. انتخاب کن. ادامه بده.").font(.system(size: 16, weight: .medium))
                Text("تاریخچه پس از اجرای ClipShelf ساخته می‌شود و روی همین مک می‌ماند.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(35)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: ClipboardController
    @StoredState<Shortcut> private var draft: Shortcut
    @StoredState<Bool> private var confirmClear = false
    init(model: ClipboardController) {
        self.model = model; _draft = State(initialValue: model.shortcut)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("تنظیمات ClipShelf").font(.system(size: 23, weight: .bold))
            VStack(alignment: .leading, spacing: 12) {
                Text("میان‌بر باز کردن تاریخچه").font(.headline)
                HStack {
                    Toggle("⌃ Control", isOn: $draft.control)
                    Toggle("⌥ Option", isOn: $draft.option)
                    Toggle("⇧ Shift", isOn: $draft.shift)
                    Toggle("⌘ Command", isOn: $draft.command)
                }.toggleStyle(.checkbox).font(.system(size: 11)).environment(\.layoutDirection, .leftToRight)
                HStack {
                    Picker("کلید", selection: $draft.keyCode) {
                        ForEach(Shortcut.keys, id: \.1) { item in Text(item.0).tag(item.1) }
                    }.frame(width: 150)
                    Spacer()
                    Text(draft.label).font(.system(size: 18, design: .monospaced)).environment(\.layoutDirection, .leftToRight)
                    Button("ذخیرهٔ میان‌بر") { _ = model.setShortcut(draft) }
                }
                Text("حروف بر اساس جای کلید در چیدمان انگلیسی هستند؛ با کیبورد فارسی هم همان کلید را بزنید.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Paste خودکار در برنامهٔ قبلی", isOn: Binding(get: { model.autoPaste }, set: model.setAutoPaste))
                HStack {
                    Text(model.trusted ? "دسترسی Accessibility فعال است" : "Paste خودکار به دسترسی Accessibility نیاز دارد")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("دسترسی…") { model.requestAccessibility() }
                }
                Picker("حداکثر تاریخچه", selection: Binding(get: { model.limit }, set: model.setLimit)) {
                    ForEach([50, 100, 200, 500], id: \.self) { Text("\($0) مورد").tag($0) }
                }.frame(width: 240)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("ذخیره‌سازی روی همین مک").font(.headline)
                Text("تاریخچه به اینترنت ارسال نمی‌شود و رمزگذاری جداگانه ندارد. برای کپی‌های حساس، ثبت را متوقف کنید. موارد علامت‌گذاری‌شده به‌عنوان محرمانه توسط برنامهٔ مبدأ نادیده گرفته می‌شوند.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("سقف هر مورد ۱ مگابایت، کل تاریخچه ۲۰ مگابایت و موارد سنجاق‌شده ۲۰ عدد است.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("پاک کردن تمام تاریخچه…", role: .destructive) { confirmClear = true }
            }
            if let message = model.message {
                Text(message).font(.system(size: 12)).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("ClipShelf 1.0 · ساخته‌شده برای macOS").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(28).frame(width: 520, height: 565).background(Color(nsColor: .windowBackgroundColor))
        .environment(\.layoutDirection, .rightToLeft).tint(accent)
        .onChange(of: draft.keyCode) { code in draft.key = Shortcut.keys.first { $0.1 == code }?.0 ?? "V" }
        .alert("تمام تاریخچه پاک شود؟", isPresented: $confirmClear) {
            Button("انصراف", role: .cancel) {}
            Button("پاک کردن", role: .destructive) { model.clear() }
        } message: { Text("موارد سنجاق‌شده هم حذف می‌شوند. فایل‌های اصلی و کلیپ‌بورد فعلی تغییری نمی‌کنند.") }
    }
}

extension Notification.Name { static let shelfOpened = Notification.Name("ClipShelf.opened") }
