import XCTest
@testable import MacsteamApp

final class SaveBackupManagerTests: XCTestCase {
    private var sandbox: URL!
    private var manager: SaveBackupManager!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        manager = SaveBackupManager(root: sandbox.appendingPathComponent("backups"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    func testVersionedBackupCanBeListed() throws {
        let save = try makeSave("one")
        let record = try manager.createBackup(gameID: "42", title: "Game", source: save)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.backupDirectory.appendingPathComponent("payload/data.txt").path))
        XCTAssertEqual(manager.list(gameID: "42").map(\.gameTitle), ["Game"])
    }

    func testCancelledBackupLeavesNoPartialData() throws {
        let save = try makeSave("one")
        XCTAssertThrowsError(try manager.createBackup(gameID: "42", title: "Game", source: save, cancelled: { true }))
        XCTAssertTrue(manager.list(gameID: "42").isEmpty)
    }

    func testRejectsTraversalIdentifierAndSymlink() throws {
        let save = try makeSave("one")
        XCTAssertThrowsError(try manager.createBackup(gameID: "../bad", title: "Game", source: save))
        let link = save.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sandbox)
        XCTAssertThrowsError(try manager.createBackup(gameID: "42", title: "Game", source: save))
    }

    func testRestoreCreatesSafetyBackupBeforeOverwrite() throws {
        let save = try makeSave("old")
        let record = try manager.createBackup(gameID: "42", title: "Game", source: save)
        try "new".write(to: save.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)
        let safety = try manager.restore(record, to: save)
        XCTAssertEqual(try String(contentsOf: save.appendingPathComponent("data.txt")), "old")
        XCTAssertEqual(try String(contentsOf: safety!.backupDirectory.appendingPathComponent("payload/data.txt")), "new")
    }

    private func makeSave(_ contents: String) throws -> URL {
        let save = sandbox.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try contents.write(to: save.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)
        return save
    }
}
