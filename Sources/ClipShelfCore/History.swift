import Foundation

public struct Clip: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable { case text, files, image, snippet }
    public var id: UUID
    public var kind: Kind
    public var text: String
    public var paths: [String]
    public var date: Date
    public var source: String
    public var pinned: Bool
    public var displayTitle: String?
    public var richType: String?
    public var richData: Data?
    public var imageType: String?
    public var imageData: Data?

    public init(text: String, source: String = "", date: Date = Date()) {
        id = UUID(); kind = .text; self.text = text; paths = []
        self.date = date; self.source = source; pinned = false
        displayTitle = nil; richType = nil; richData = nil; imageType = nil; imageData = nil
    }
    public init(paths: [String], source: String = "", date: Date = Date()) {
        id = UUID(); kind = .files; text = ""; self.paths = paths
        self.date = date; self.source = source; pinned = false
        displayTitle = nil; richType = nil; richData = nil; imageType = nil; imageData = nil
    }
    public init(imageData: Data, imageType: String, source: String = "", date: Date = Date()) {
        id = UUID(); kind = .image; text = ""; paths = []
        self.date = date; self.source = source; pinned = false
        displayTitle = nil; richType = nil; richData = nil
        self.imageType = imageType; self.imageData = imageData
    }
    public init(snippetTitle: String, text: String, date: Date = Date()) {
        id = UUID(); kind = .snippet; self.text = text; paths = []
        self.date = date; source = "اسنیپت"; pinned = false
        displayTitle = snippetTitle; richType = nil; richData = nil
        imageType = nil; imageData = nil
    }
    public var title: String {
        if kind == .files { return paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "، ") }
        if let displayTitle, !displayTitle.isEmpty { return displayTitle }
        if kind == .image { return "تصویر کپی‌شده" }
        return text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(180)) } ?? text
    }
    public var size: Int {
        let raw = text.utf8.count + paths.reduce(0) { $0 + $1.utf8.count } +
            (richData?.count ?? 0) + (imageData?.count ?? 0) + (displayTitle?.utf8.count ?? 0)
        return raw + raw / 3 + 512 // JSON metadata and base64 expansion.
    }
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || ([text, source, displayTitle ?? ""] + paths).contains { $0.localizedStandardContains(q) }
    }
    public func hasSameContent(as other: Clip) -> Bool {
        kind == other.kind && text == other.text && paths == other.paths &&
            richType == other.richType && richData == other.richData &&
            imageType == other.imageType && imageData == other.imageData && displayTitle == other.displayTitle
    }
}

public struct History: Codable {
    public var clips: [Clip] = []
    public init(clips: [Clip] = []) { self.clips = clips }
    public static let byteLimit = 20 * 1024 * 1024
    public static let itemByteLimit = 8 * 1024 * 1024
    public static let snippetLimit = 100

    @discardableResult public mutating func insert(_ clip: Clip, limit: Int) -> Bool {
        guard clip.size <= Self.itemByteLimit, isValid(clip) else { return false }
        if clip.kind == .snippet && clips.filter({ $0.kind == .snippet }).count >= Self.snippetLimit { return false }
        var next = clip
        if let i = clips.firstIndex(where: { $0.hasSameContent(as: clip) }) {
            next.id = clips[i].id
            next.pinned = clips[i].pinned
            clips.remove(at: i)
        }
        clips.insert(next, at: 0)
        trim(limit: limit)
        return clips.contains { $0.id == next.id }
    }
    public mutating func trim(limit: Int) {
        while clips.filter({ $0.kind != .snippet }).count > max(1, limit) || clips.reduce(0, { $0 + $1.size }) > Self.byteLimit {
            guard let i = clips.lastIndex(where: { !$0.pinned && $0.kind != .snippet }) else { break }
            clips.remove(at: i)
        }
    }
    public var sorted: [Clip] {
        clips.filter { $0.pinned && $0.kind != .snippet } +
            clips.filter { !$0.pinned && $0.kind != .snippet } +
            clips.filter { $0.kind == .snippet }
    }
    private func isValid(_ clip: Clip) -> Bool {
        switch clip.kind {
        case .text: return !clip.text.isEmpty
        case .files: return !clip.paths.isEmpty
        case .image: return clip.imageData?.isEmpty == false && clip.imageType != nil
        case .snippet: return !clip.text.isEmpty && !(clip.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}

public struct HistoryFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> History {
        guard FileManager.default.fileExists(atPath: url.path) else { return History() }
        return try JSONDecoder().decode(History.self, from: Data(contentsOf: url))
    }
    public func save(_ history: History) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(history).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
