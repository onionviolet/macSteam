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
        XCTAssertThrowsError(try manager.createBackup(gameID: ".", title: "Game", source: save))
        XCTAssertThrowsError(try manager.createBackup(gameID: "..", title: "Game", source: save))
        let link = save.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sandbox)
        XCTAssertThrowsError(try manager.createBackup(gameID: "42", title: "Game", source: save))
    }

    func testRestoreCancellationAfterCopyLeavesDestinationUntouched() throws {
        let source = try makeSave("old")
        let record = try manager.createBackup(gameID: "42", title: "Game", source: source)
        let destination = sandbox.appendingPathComponent("new-save")
        var checks = 0
        XCTAssertThrowsError(try manager.restore(record, to: destination, cancelled: {
            checks += 1
            return checks >= 2
        }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: sandbox.path).contains { $0.hasPrefix(".macsteam-restore") })
    }

    func testRestoreCreatesSafetyBackupBeforeOverwrite() throws {
        let save = try makeSave("old")
        let record = try manager.createBackup(gameID: "42", title: "Game", source: save)
        try "new".write(to: save.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)
        let safety = try manager.restore(record, to: save)
        XCTAssertEqual(try String(contentsOf: save.appendingPathComponent("data.txt")), "old")
        XCTAssertEqual(try String(contentsOf: safety!.backupDirectory.appendingPathComponent("payload/data.txt")), "new")
    }

    func testRestoreRejectsSymlinkedDestinationAncestor() throws {
        let source = try makeSave("old")
        let record = try manager.createBackup(gameID: "42", title: "Game", source: source)
        let outside = sandbox.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = sandbox.appendingPathComponent("destination-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try manager.restore(record, to: link.appendingPathComponent("save")))
    }

    func testListRejectsTamperedBackupMetadata() throws {
        let source = try makeSave("old")
        let record = try manager.createBackup(gameID: "42", title: "Game", source: source)
        let tampered = SaveBackupRecord(schemaVersion: 1, gameID: "42", gameTitle: "Game", createdAt: record.createdAt,
            backupDirectory: sandbox.appendingPathComponent("backups/42/elsewhere"), originalName: record.originalName)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(tampered).write(to: record.backupDirectory.appendingPathComponent("metadata.json"), options: .atomic)
        XCTAssertTrue(manager.list(gameID: "42").isEmpty)
        XCTAssertThrowsError(try manager.restore(tampered, to: source))
    }

    func testBackupRejectsSymlinkedGameRoot() throws {
        let source = try makeSave("old")
        let outside = sandbox.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let backupRoot = sandbox.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: backupRoot.appendingPathComponent("42"), withDestinationURL: outside)
        XCTAssertThrowsError(try manager.createBackup(gameID: "42", title: "Game", source: source))
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: outside.path)).isEmpty)
    }

    func testRejectsOverlappingSourceAndDestinationTrees() throws {
        let backupRoot = sandbox.appendingPathComponent("nested/backups")
        let overlapping = SaveBackupManager(root: backupRoot)
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        XCTAssertThrowsError(try overlapping.createBackup(gameID: "42", title: "Game", source: sandbox))

        let source = try makeSave("old")
        let record = try manager.createBackup(gameID: "42", title: "Game", source: source)
        XCTAssertThrowsError(try manager.restore(record, to: manager.root.appendingPathComponent("destination")))
        XCTAssertThrowsError(try manager.restore(record, to: sandbox))
    }

    private func makeSave(_ contents: String) throws -> URL {
        let save = sandbox.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try contents.write(to: save.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)
        return save
    }
}
