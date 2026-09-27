import XCTest
@testable import MacsteamApp

final class ConfigurationPortabilityTests: XCTestCase {
    func testExportContainsOnlySafeVersionedSettings() throws {
        var config = MacsteamConfig(); config.hideWhatsNew = true; config.apps = [42]
        config.depotKeyGroups = [DepotKeyGroup(appID: 42, depots: [(7, "secret")])]
        let text = String(decoding: try ConfigurationPortability.export(config: config), as: UTF8.self)
        XCTAssertTrue(text.contains("schemaVersion"))
        XCTAssertTrue(text.contains("hideWhatsNew"))
        XCTAssertFalse(text.contains("42"))
        XCTAssertFalse(text.contains("secret"))
    }

    func testRejectsUnknownFieldsAndVersions() throws {
        XCTAssertThrowsError(try ConfigurationPortability.decode(Data(#"{"schemaVersion":1,"settings":{"hideWhatsNew":true,"path":"/tmp"}}"#.utf8)))
        XCTAssertThrowsError(try ConfigurationPortability.decode(Data(#"{"schemaVersion":2,"settings":{"hideWhatsNew":true}}"#.utf8)))
    }

    func testPreviewReportsOnlyChanges() throws {
        var current = MacsteamConfig(); current.hideWhatsNew = false
        let document = try ConfigurationPortability.decode(Data(#"{"schemaVersion":1,"settings":{"hideWhatsNew":true}}"#.utf8))
        XCTAssertEqual(ConfigurationPortability.preview(document, current: current),
                       [SettingsChange(name: "Hide What's New", oldValue: "Off", newValue: "On")])
    }

    func testApplyBacksUpPreviousConfigAndReplacesAtomically() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configURL = root.appendingPathComponent("config.yaml")
        let backupURL = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "HideWhatsNew: no\n".write(to: configURL, atomically: true, encoding: .utf8)
        let store = ConfigStore(configFile: configURL, backupDir: backupURL); store.load()
        let document = PortableSettings(schemaVersion: 1, settings: .init(hideWhatsNew: true))
        try store.apply(document)
        XCTAssertTrue(try String(contentsOf: configURL).contains("HideWhatsNew: yes"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backupURL.path).count, 1)
    }

    func testFailedBackupAbortsWriteAndRollsBackMemory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.yaml")
        let invalidBackup = root.appendingPathComponent("not-a-directory")
        try "HideWhatsNew: no\n".write(to: configURL, atomically: true, encoding: .utf8)
        try "file".write(to: invalidBackup, atomically: true, encoding: .utf8)
        let store = ConfigStore(configFile: configURL, backupDir: invalidBackup); store.load()
        XCTAssertThrowsError(try store.apply(PortableSettings(schemaVersion: 1, settings: .init(hideWhatsNew: true))))
        XCTAssertFalse(store.config.hideWhatsNew)
        XCTAssertTrue(try String(contentsOf: configURL).contains("HideWhatsNew: no"))
    }
}
