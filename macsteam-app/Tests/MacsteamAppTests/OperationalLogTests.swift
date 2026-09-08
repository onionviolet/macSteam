import XCTest
@testable import MacsteamApp

final class OperationalLogTests: XCTestCase {
    func testRetentionAndRedaction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = OperationalLog(fileURL: root.appendingPathComponent("log.jsonl"), maximumEntries: 2)
        log.record(.info, operation: "scan", message: "first")
        log.record(.warning, operation: "backup", message: "token=secret /Users/alice/save")
        log.record(.error, operation: "restore", message: "third")
        let entries = log.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.operation), ["backup", "restore"])
        XCTAssertFalse(log.exportText().contains("secret"))
        XCTAssertFalse(log.exportText().contains("alice"))
    }

    func testSearchAndClear() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = OperationalLog(fileURL: root.appendingPathComponent("log.jsonl"))
        log.record(.info, operation: "scan", message: "found games")
        log.record(.info, operation: "backup", message: "saved")
        XCTAssertTrue(log.exportText(filter: "games").contains("scan"))
        XCTAssertFalse(log.exportText(filter: "games").contains("backup"))
        try log.clear()
        XCTAssertTrue(log.entries().isEmpty)
    }

    func testExportReredactsPersistedLegacyEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("log.jsonl")
        try #"{"level":"info","message":"token=legacy","operation":"scan","timestamp":"2026-09-07T12:00:00Z"}"#
            .write(to: file, atomically: true, encoding: .utf8)
        let output = OperationalLog(fileURL: file).exportText()
        XCTAssertFalse(output.contains("legacy"))
    }

    func testRetentionAlsoBoundsFileSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("log.jsonl")
        let log = OperationalLog(fileURL: file, maximumEntries: 100, maximumBytes: 300)
        for index in 0..<20 {
            log.record(.info, operation: "scan", message: "entry \(index) with bounded content")
        }
        _ = log.entries()
        XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 300)
        XCTAssertLessThan(log.entries().count, 20)
    }
}
