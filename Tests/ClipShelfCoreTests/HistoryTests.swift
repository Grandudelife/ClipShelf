import Foundation
import ClipShelfCore

@main struct HistoryTests {
    static func testDuplicateMovesToFrontAndKeepsPinAndID() {
        var a = Clip(text: "سلام\nworld"); a.pinned = true
        var history = History(clips: [Clip(text: "second"), a])
        history.insert(Clip(text: a.text, source: "TextEdit"), limit: 200)
        expectEqual(history.clips.count, 2)
        expectEqual(history.clips[0].id, a.id)
        expect(history.clips[0].pinned)
        expectEqual(history.clips[0].source, "TextEdit")
    }
    static func testEvictionProtectsPinnedClips() {
        var pinned = Clip(text: "keep"); pinned.pinned = true
        var history = History(clips: [Clip(text: "old"), pinned])
        history.insert(Clip(text: "new"), limit: 2)
        expectEqual(history.sorted.map(\.text), ["keep", "new"])
    }
    static func testExactWhitespaceAndFileGroupRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = HistoryFile(url: directory.appendingPathComponent("history.json"))
        let history = History(clips: [Clip(text: "  فارسی\n\tcode  "), Clip(paths: ["/tmp/a b.txt", "/tmp/ب.pdf"])])
        try file.save(history)
        expectEqual(try file.load().clips, history.clips)
        let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
        expectEqual(permissions, 0o600)
    }
    static func testSearchFindsUnicodeSourceAndFilePath() {
        expect(Clip(text: "سلام دنیا").matches("دنیا"))
        expect(Clip(paths: ["/Users/test/Report.PDF"]).matches("report"))
        expect(Clip(text: "value", source: "Safari").matches("safari"))
        expectFalse(Clip(text: "value").matches("missing"))
    }
    static func testRejectsOversizedAndEmptyWithoutChangingHistory() {
        var history = History()
        expectFalse(history.insert(Clip(text: ""), limit: 20))
        expectFalse(history.insert(Clip(paths: []), limit: 20))
        expectFalse(history.insert(Clip(text: String(repeating: "a", count: History.itemByteLimit)), limit: 20))
        expect(history.clips.isEmpty)
    }
    static func testCorruptedFileReportsErrorInsteadOfSilentlyResetting() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        expectThrows(try HistoryFile(url: url).load())
    }
    static func testSameNameDifferentFilePathsRemainDistinct() {
        var history = History()
        history.insert(Clip(paths: ["/a/test.txt"]), limit: 200)
        history.insert(Clip(paths: ["/b/test.txt"]), limit: 200)
        expectEqual(history.clips.count, 2)
    }

    static func expect(_ value: Bool) { precondition(value, "Expectation failed") }
    static func expectFalse(_ value: Bool) { precondition(!value, "Expected false") }
    static func expectEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Values differ") }
    static func expectThrows<T>(_ expression: @autoclosure () throws -> T) {
        do { _ = try expression(); fatalError("Expected an error") } catch {}
    }
    static func main() throws {
        testDuplicateMovesToFrontAndKeepsPinAndID()
        testEvictionProtectsPinnedClips()
        try testExactWhitespaceAndFileGroupRoundTrip()
        testSearchFindsUnicodeSourceAndFilePath()
        testRejectsOversizedAndEmptyWithoutChangingHistory()
        try testCorruptedFileReportsErrorInsteadOfSilentlyResetting()
        testSameNameDifferentFilePathsRemainDistinct()
        print("PASS: 7 history checks (deduplication, pinning, persistence, Unicode search, size limits, corruption, file identity)")
    }
}
