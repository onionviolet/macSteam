import Foundation

struct SaveBackupRecord: Codable, Equatable {
    let schemaVersion: Int
    let gameID: String
    let gameTitle: String
    let createdAt: Date
    let backupDirectory: URL
    let originalName: String
}

struct SaveBackupProfile: Codable, Equatable {
    let schemaVersion: Int
    let gameID: String
    let gameTitle: String
    let sourceDirectory: URL
    let updatedAt: Date
}

enum SaveBackupError: LocalizedError {
    case invalidIdentifier
    case unsafePath(String)
    case cancelled
    case missingPayload
    case invalidProfile
    case invalidProfileStore

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier: return "The game identifier is not safe."
        case .unsafePath(let detail): return "Unsafe save path: \(detail)"
        case .cancelled: return "The operation was cancelled without changing existing data."
        case .missingPayload: return "The selected backup is incomplete."
        case .invalidProfile: return "The saved backup profile is invalid or no longer safe. Choose the save folder again."
        case .invalidProfileStore: return "The saved backup profiles could not be read safely."
        }
    }
}

final class SaveBackupManager: @unchecked Sendable {
    let root: URL
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let profileLock = NSLock()

    private var profileStore: URL { root.appendingPathComponent("profiles.json") }

    init(root: URL = Paths.saveBackupDir, fileManager: FileManager = .default,
         homeDirectory: URL? = nil) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        self.homeDirectory = (homeDirectory ?? fileManager.homeDirectoryForCurrentUser).standardizedFileURL
    }

    func saveProfile(gameID: String, title: String, sourceDirectory: URL) throws -> SaveBackupProfile {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.safeIdentifier(gameID), !cleanTitle.isEmpty else { throw SaveBackupError.invalidIdentifier }
        let source = sourceDirectory.standardizedFileURL
        try validateProfileSource(source)
        let profile = SaveBackupProfile(schemaVersion: 1, gameID: gameID, gameTitle: cleanTitle,
                                        sourceDirectory: source, updatedAt: Date())
        try profileLock.withLock {
            var profiles = try readProfilesUnlocked()
            profiles.removeAll { $0.gameID == gameID }
            profiles.append(profile)
            try writeProfilesUnlocked(profiles)
        }
        return profile
    }

    func listProfiles() throws -> [SaveBackupProfile] {
        try profileLock.withLock {
            try readProfilesUnlocked().sorted {
                $0.gameTitle.localizedCaseInsensitiveCompare($1.gameTitle) == .orderedAscending
            }
        }
    }

    @discardableResult
    func removeProfile(gameID: String) throws -> Bool {
        guard Self.safeIdentifier(gameID) else { throw SaveBackupError.invalidIdentifier }
        return try profileLock.withLock {
            var profiles = try readProfilesUnlocked()
            let previousCount = profiles.count
            profiles.removeAll { $0.gameID == gameID }
            guard profiles.count != previousCount else { return false }
            try writeProfilesUnlocked(profiles)
            return true
        }
    }

    func createBackup(using profile: SaveBackupProfile,
                      cancelled: () -> Bool = { false }) throws -> SaveBackupRecord {
        guard profile.schemaVersion == 1, Self.safeIdentifier(profile.gameID),
              !profile.gameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SaveBackupError.invalidProfile
        }
        let saved = try listProfiles().first { $0.gameID == profile.gameID }
        guard let saved,
              saved.schemaVersion == profile.schemaVersion,
              saved.gameID == profile.gameID,
              saved.gameTitle == profile.gameTitle,
              saved.sourceDirectory.standardizedFileURL.path == profile.sourceDirectory.standardizedFileURL.path,
              abs(saved.updatedAt.timeIntervalSince(profile.updatedAt)) < 1 else {
            throw SaveBackupError.invalidProfile
        }
        try validateProfileSource(profile.sourceDirectory)
        return try createBackup(gameID: profile.gameID, title: profile.gameTitle,
                                source: profile.sourceDirectory, cancelled: cancelled)
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

    private func validateProfileSource(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), url.path != "/" else {
            throw SaveBackupError.unsafePath("choose a local save folder")
        }
        let home = homeDirectory
        guard url.path != home.path, Self.treesAreDisjoint(url, root) else {
            throw SaveBackupError.unsafePath("choose the game's save folder, not a broad or managed folder")
        }
        guard !Self.broadProfileRoots(home: home).contains(where: { $0.path == url.path }) else {
            throw SaveBackupError.unsafePath("choose the game's save folder, not an entire personal folder")
        }
        for protected in Self.protectedRoots(home: home) where url.path == protected.path || url.path.hasPrefix(protected.path + "/") {
            throw SaveBackupError.unsafePath("credential and cloud-storage folders cannot be backup profiles")
        }
        try rejectSymlinkChain(url)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey, .volumeIsLocalKey])
        guard values.isDirectory == true else { throw SaveBackupError.unsafePath("backup profiles must point to a folder") }
        guard values.isUbiquitousItem != true, values.volumeIsLocal != false else {
            throw SaveBackupError.unsafePath("backup profiles must stay on a local, non-cloud volume")
        }
        try validateTree(url)
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

    private static func protectedRoots(home: URL) -> [URL] {
        [
            ".ssh", ".gnupg", ".aws", ".config/gcloud",
            "Library/Keychains", "Library/Mobile Documents", "Library/CloudStorage",
        ].map { home.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
    }

    private static func broadProfileRoots(home: URL) -> [URL] {
        ["Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures"]
            .map { home.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
    }

    private func readProfilesUnlocked() throws -> [SaveBackupProfile] {
        guard fileManager.fileExists(atPath: profileStore.path) else { return [] }
        do {
            try rejectSymlinkChain(profileStore)
            let profiles = try JSONDecoder.configured.decode([SaveBackupProfile].self,
                                                               from: Data(contentsOf: profileStore))
            guard profiles.allSatisfy({
                $0.schemaVersion == 1 && Self.safeIdentifier($0.gameID)
                    && !$0.gameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.sourceDirectory.isFileURL
                    && Self.treesAreDisjoint($0.sourceDirectory.standardizedFileURL, root)
            }), Set(profiles.map(\.gameID)).count == profiles.count else {
                throw SaveBackupError.invalidProfileStore
            }
            return profiles
        } catch let error as SaveBackupError {
            throw error
        } catch {
            throw SaveBackupError.invalidProfileStore
        }
    }

    private func writeProfilesUnlocked(_ profiles: [SaveBackupProfile]) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try rejectSymlinkChain(root)
        if fileManager.fileExists(atPath: profileStore.path) {
            try rejectSymlinkChain(profileStore)
        }
        let data = try JSONEncoder.configured.encode(profiles.sorted { $0.gameID < $1.gameID })
        try data.write(to: profileStore, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: profileStore.path)
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
