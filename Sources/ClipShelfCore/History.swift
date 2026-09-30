import Foundation

public struct Clip: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable { case text, files }
    public var id: UUID
    public var kind: Kind
    public var text: String
    public var paths: [String]
    public var date: Date
    public var source: String
    public var pinned: Bool

    public init(text: String, source: String = "", date: Date = Date()) {
        id = UUID(); kind = .text; self.text = text; paths = []
        self.date = date; self.source = source; pinned = false
    }
    public init(paths: [String], source: String = "", date: Date = Date()) {
        id = UUID(); kind = .files; text = ""; self.paths = paths
        self.date = date; self.source = source; pinned = false
    }
    public var title: String {
        if kind == .files { return paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "، ") }
        return text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(180)) } ?? text
    }
    public var size: Int { text.utf8.count + paths.reduce(0) { $0 + $1.utf8.count } }
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || ([text, source] + paths).contains { $0.localizedStandardContains(q) }
    }
    public func hasSameContent(as other: Clip) -> Bool {
        kind == other.kind && text == other.text && paths == other.paths
    }
}

public struct History: Codable {
    public var clips: [Clip] = []
    public init(clips: [Clip] = []) { self.clips = clips }
    public static let byteLimit = 20 * 1024 * 1024
    public static let itemByteLimit = 1024 * 1024

    @discardableResult public mutating func insert(_ clip: Clip, limit: Int) -> Bool {
        guard clip.size <= Self.itemByteLimit,
              (clip.kind == .text ? !clip.text.isEmpty : !clip.paths.isEmpty) else { return false }
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
        while clips.count > max(1, limit) || clips.reduce(0, { $0 + $1.size }) > Self.byteLimit {
            guard let i = clips.lastIndex(where: { !$0.pinned }) else { break }
            clips.remove(at: i)
        }
    }
    public var sorted: [Clip] { clips.filter(\.pinned) + clips.filter { !$0.pinned } }
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
