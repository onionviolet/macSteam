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

final class SaveBackupManager: @unchecked Sendable {
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
        guard Self.treesAreDisjoint(source, root) else {
            throw SaveBackupError.unsafePath("save source and backup storage must be separate")
        }
        try validateTree(source)
        if cancelled() { throw SaveBackupError.cancelled }
        let gameRoot = root.appendingPathComponent(gameID, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try rejectSymlinkChain(root)
        guard Self.isDescendant(gameRoot, of: root) else { throw SaveBackupError.invalidIdentifier }
        if fileManager.fileExists(atPath: gameRoot.path) {
            try rejectSymlinkChain(gameRoot)
        } else {
            try fileManager.createDirectory(at: gameRoot, withIntermediateDirectories: false)
        }
        try rejectSymlinkChain(gameRoot)
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
        try rejectSymlinkChain(root)
        try rejectSymlinkChain(backup)
        guard record.schemaVersion == 1, Self.safeIdentifier(record.gameID),
              let stored = try? Data(contentsOf: backup.appendingPathComponent("metadata.json")),
              let decoded = try? JSONDecoder.configured.decode(SaveBackupRecord.self, from: stored),
              decoded.schemaVersion == record.schemaVersion,
              decoded.gameID == record.gameID,
              decoded.gameTitle == record.gameTitle,
              decoded.originalName == record.originalName,
              decoded.backupDirectory.standardizedFileURL.path == backup.path,
              abs(decoded.createdAt.timeIntervalSince(record.createdAt)) < 1 else {
            throw SaveBackupError.unsafePath("backup metadata does not match the selected backup")
        }
        let payload = backup.appendingPathComponent("payload")
        guard fileManager.fileExists(atPath: payload.path) else { throw SaveBackupError.missingPayload }
        try validateTree(payload)
        let destination = destination.standardizedFileURL
        guard Self.treesAreDisjoint(destination, root) else {
            throw SaveBackupError.unsafePath("restore destination and backup storage must be separate")
        }
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
        let previous = destination.deletingLastPathComponent()
            .appendingPathComponent(".macsteam-previous-\(UUID().uuidString)", isDirectory: destination.hasDirectoryPath)
        let hadDestination = fileManager.fileExists(atPath: destination.path)
        do {
            try fileManager.copyItem(at: payload, to: staging)
            if cancelled() { throw SaveBackupError.cancelled }
            if hadDestination { try fileManager.moveItem(at: destination, to: previous) }
            try fileManager.moveItem(at: staging, to: destination)
            if hadDestination { try? fileManager.removeItem(at: previous) }
        } catch {
            try? fileManager.removeItem(at: staging)
            if hadDestination && !fileManager.fileExists(atPath: destination.path) {
                do { try fileManager.moveItem(at: previous, to: destination) }
                catch { throw SaveBackupError.unsafePath("restore failed and the previous data remains at \(previous.lastPathComponent)") }
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
            guard (try? rejectSymlinkChain(entry)) != nil,
                  Self.isDescendant(entry.standardizedFileURL, of: root),
                  let data = try? Data(contentsOf: entry.appendingPathComponent("metadata.json")),
                  let record = try? JSONDecoder.configured.decode(SaveBackupRecord.self, from: data),
                  record.schemaVersion == 1, record.gameID == gameID,
                  record.backupDirectory.standardizedFileURL.path == entry.standardizedFileURL.path else { return nil }
            return record
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private func validateDestination(_ url: URL) throws {
        guard !url.path.isEmpty, url.path != "/", url.lastPathComponent != ".", url.lastPathComponent != ".." else {
            throw SaveBackupError.unsafePath("invalid restore destination")
        }
        var parent = url.deletingLastPathComponent()
        while parent.path != "/" && !fileManager.fileExists(atPath: parent.path) { parent.deleteLastPathComponent() }
        try rejectSymlinkChain(parent)
        if fileManager.fileExists(atPath: url.path) { try rejectSymlinkChain(url) }
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

    private func rejectSymlinkChain(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for (index, component) in standardized.pathComponents.dropFirst().enumerated() {
            current.appendPathComponent(component)
            guard fileManager.fileExists(atPath: current.path) else { break }
            let isSystemAlias = index == 0 && (component == "var" || component == "tmp")
            if !isSystemAlias { try rejectSymlink(current) }
        }
    }

    private static func safeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    private static func isDescendant(_ child: URL, of parent: URL) -> Bool {
        child.path.hasPrefix(parent.standardizedFileURL.path + "/")
    }

    private static func treesAreDisjoint(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = lhs.standardizedFileURL.path
        let right = rhs.standardizedFileURL.path
        return left != right && !left.hasPrefix(right + "/") && !right.hasPrefix(left + "/")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

final class BackupCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.withLock { value = true } }
    var isCancelled: Bool { lock.withLock { value } }
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
