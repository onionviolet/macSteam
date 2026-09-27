import XCTest
@testable import MacsteamApp

final class SaveBackupManagerTests: XCTestCase {
    private var sandbox: URL!
    private var manager: SaveBackupManager!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        manager = SaveBackupManager(root: sandbox.appendingPathComponent("backups"),
                                    homeDirectory: sandbox)
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

    func testProfilePersistsReplacesAndCanBeRemovedWithoutDeletingBackups() throws {
        let first = try makeSave("one")
        let profile = try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: first)
        XCTAssertEqual(try manager.listProfiles().map(\.gameID), ["42"])

        let backup = try manager.createBackup(using: profile)
        let second = sandbox.appendingPathComponent("second-save", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try "two".write(to: second.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)
        let replacement = try manager.saveProfile(gameID: "42", title: "Renamed Game", sourceDirectory: second)

        XCTAssertEqual(try manager.listProfiles().map(\.gameTitle), ["Renamed Game"])
        XCTAssertEqual(try manager.createBackup(using: replacement).gameTitle, "Renamed Game")
        XCTAssertTrue(try manager.removeProfile(gameID: "42"))
        XCTAssertFalse(try manager.removeProfile(gameID: "42"))
        XCTAssertTrue(try manager.listProfiles().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.backupDirectory.path))
    }

    func testProfileBackupRejectsStaleOrChangedMapping() throws {
        let first = try makeSave("one")
        let stale = try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: first)
        let second = sandbox.appendingPathComponent("second-save", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        _ = try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: second)

        XCTAssertThrowsError(try manager.createBackup(using: stale))
        XCTAssertTrue(manager.list(gameID: "42").isEmpty)
    }

    func testProfileRequiresDirectoryAndRejectsSymlinkedTree() throws {
        let file = sandbox.appendingPathComponent("single-save.dat")
        try "save".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: file))

        let save = sandbox.appendingPathComponent("linked-save", isDirectory: true)
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: save.appendingPathComponent("outside"),
                                                    withDestinationURL: sandbox)
        XCTAssertThrowsError(try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: save))
        XCTAssertTrue(try manager.listProfiles().isEmpty)
    }

    func testProfileIsRevalidatedBeforeEachBackup() throws {
        let save = try makeSave("one")
        let profile = try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: save)
        try FileManager.default.removeItem(at: save)
        let replacement = sandbox.appendingPathComponent("replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: save, withDestinationURL: replacement)

        XCTAssertThrowsError(try manager.createBackup(using: profile))
        XCTAssertTrue(manager.list(gameID: "42").isEmpty)
    }

    func testCorruptProfileStoreIsNotSilentlyOverwritten() throws {
        try FileManager.default.createDirectory(at: manager.root, withIntermediateDirectories: true)
        let store = manager.root.appendingPathComponent("profiles.json")
        try Data("not json".utf8).write(to: store)
        let save = try makeSave("one")

        XCTAssertThrowsError(try manager.listProfiles())
        XCTAssertThrowsError(try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: save))
        XCTAssertEqual(try String(contentsOf: store, encoding: .utf8), "not json")
    }

    func testProfileStoreIsPrivateAndRejectsSymlinkReplacement() throws {
        let save = try makeSave("one")
        _ = try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: save)
        let store = manager.root.appendingPathComponent("profiles.json")
        let permissions = try FileManager.default.attributesOfItem(atPath: store.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let outside = sandbox.appendingPathComponent("outside-profiles.json")
        try FileManager.default.moveItem(at: store, to: outside)
        try FileManager.default.createSymbolicLink(at: store, withDestinationURL: outside)
        XCTAssertThrowsError(try manager.listProfiles())
        XCTAssertThrowsError(try manager.saveProfile(gameID: "43", title: "Other", sourceDirectory: save))
    }

    func testProfileRejectsEntirePersonalFolderButAllowsGameSubfolder() throws {
        let documents = sandbox.appendingPathComponent("Documents", isDirectory: true)
        let gameSave = documents.appendingPathComponent("Example Game", isDirectory: true)
        try FileManager.default.createDirectory(at: gameSave, withIntermediateDirectories: true)

        XCTAssertThrowsError(try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: documents))
        XCTAssertNoThrow(try manager.saveProfile(gameID: "42", title: "Game", sourceDirectory: gameSave))
    }

    private func makeSave(_ contents: String) throws -> URL {
        let save = sandbox.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try contents.write(to: save.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)
        return save
    }
}
