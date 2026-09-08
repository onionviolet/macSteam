import Foundation

struct SaveBackupRecord: Codable, Equatable {
    let schemaVersion: Int
    let gameID: String
    let gameTitle: String
    let createdAt: Date
    let backupDirectory: URL
    let originalName: String
}

enum SaveBackupError: LocalizedError {
    case invalidIdentifier
    case unsafePath(String)
    case cancelled
    case missingPayload

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier: return "The game identifier is not safe."
        case .unsafePath(let detail): return "Unsafe save path: \(detail)"
        case .cancelled: return "The operation was cancelled without changing existing data."
        case .missingPayload: return "The selected backup is incomplete."
        }
    }
}

final class SaveBackupManager {
    let root: URL
    private let fileManager: FileManager

    init(root: URL = Paths.saveBackupDir, fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
    }

    func createBackup(gameID: String, title: String, source: URL,
                      cancelled: () -> Bool = { false }) throws -> SaveBackupRecord {
        guard Self.safeIdentifier(gameID) else { throw SaveBackupError.invalidIdentifier }
        let source = source.standardizedFileURL
        try validateTree(source)
        if cancelled() { throw SaveBackupError.cancelled }
        let gameRoot = root.appendingPathComponent(gameID, isDirectory: true)
        try fileManager.createDirectory(at: gameRoot, withIntermediateDirectories: true)
        let name = Self.timestamp() + "-" + UUID().uuidString
        let staging = gameRoot.appendingPathComponent(".\(name).partial", isDirectory: true)
        let final = gameRoot.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            let payload = staging.appendingPathComponent("payload", isDirectory: source.hasDirectoryPath)
            try fileManager.copyItem(at: source, to: payload)
            if cancelled() { throw SaveBackupError.cancelled }
            let record = SaveBackupRecord(schemaVersion: 1, gameID: gameID, gameTitle: title,
                createdAt: Date(), backupDirectory: final, originalName: source.lastPathComponent)
            let metadata = try JSONEncoder.configured.encode(record)
            try metadata.write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
            try fileManager.moveItem(at: staging, to: final)
            return record
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func restore(_ record: SaveBackupRecord, to destination: URL,
                 cancelled: () -> Bool = { false }) throws -> SaveBackupRecord? {
        let backup = record.backupDirectory.standardizedFileURL
        guard Self.isDescendant(backup, of: root), !backup.lastPathComponent.hasPrefix(".") else {
            throw SaveBackupError.unsafePath("backup is outside the managed backup folder")
        }
        let payload = backup.appendingPathComponent("payload")
        guard fileManager.fileExists(atPath: payload.path) else { throw SaveBackupError.missingPayload }
        try validateTree(payload)
        let destination = destination.standardizedFileURL
        try validateDestination(destination)
        if cancelled() { throw SaveBackupError.cancelled }

        var safety: SaveBackupRecord?
        if fileManager.fileExists(atPath: destination.path) {
            safety = try createBackup(gameID: record.gameID, title: record.gameTitle + " restore safety",
                                      source: destination, cancelled: cancelled)
        }
        if cancelled() { throw SaveBackupError.cancelled }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".macsteam-restore-\(UUID().uuidString)", isDirectory: payload.hasDirectoryPath)
        try fileManager.copyItem(at: payload, to: staging)
        do {
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            if let safety {
                let safetyPayload = safety.backupDirectory.appendingPathComponent("payload")
                if !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.copyItem(at: safetyPayload, to: destination)
                }
            }
            throw error
        }
        return safety
    }

    func list(gameID: String) -> [SaveBackupRecord] {
        guard Self.safeIdentifier(gameID) else { return [] }
        let directory = root.appendingPathComponent(gameID, isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return entries.compactMap { entry in
            guard Self.isDescendant(entry.standardizedFileURL, of: root),
                  let data = try? Data(contentsOf: entry.appendingPathComponent("metadata.json")),
                  let record = try? JSONDecoder.configured.decode(SaveBackupRecord.self, from: data) else { return nil }
            return record
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func validateDestination(_ url: URL) throws {
        guard !url.path.isEmpty, url.path != "/", url.lastPathComponent != ".", url.lastPathComponent != ".." else {
            throw SaveBackupError.unsafePath("invalid restore destination")
        }
        var parent = url.deletingLastPathComponent()
        while parent.path != "/" && !fileManager.fileExists(atPath: parent.path) { parent.deleteLastPathComponent() }
        try rejectSymlink(parent)
    }

    private func validateTree(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { throw SaveBackupError.unsafePath("folder does not exist") }
        try rejectSymlink(url)
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                   options: [], errorHandler: { _, _ in false }) {
            while let item = enumerator.nextObject() as? URL { try rejectSymlink(item) }
        }
    }

    private func rejectSymlink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw SaveBackupError.unsafePath("symbolic links are not allowed")
        }
    }

    private static func safeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    private static func isDescendant(_ child: URL, of parent: URL) -> Bool {
        child.path.hasPrefix(parent.standardizedFileURL.path + "/")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private extension JSONEncoder {
    static var configured: JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder
    }
}

private extension JSONDecoder {
    static var configured: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}
