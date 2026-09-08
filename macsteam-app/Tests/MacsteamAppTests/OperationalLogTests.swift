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
}
