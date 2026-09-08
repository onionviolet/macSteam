import Foundation

enum LogLevel: String, Codable, CaseIterable { case debug, info, warning, error }

struct LogEntry: Codable, Equatable {
    let timestamp: Date
    let level: LogLevel
    let operation: String
    let message: String
}

final class OperationalLog: @unchecked Sendable {
    static let shared = OperationalLog()
    let fileURL: URL
    private let maximumEntries: Int
    private let lock = NSLock()

    init(fileURL: URL = Paths.configDir.appendingPathComponent("operations.jsonl"), maximumEntries: Int = 500) {
        self.fileURL = fileURL
        self.maximumEntries = max(1, maximumEntries)
    }

    func record(_ level: LogLevel, operation: String, message: String) {
        let safeOperation = DiagnosticRedactor.redact(operation)
        let safeMessage = DiagnosticRedactor.redact(message)
        lock.withLock {
            var entries = readUnlocked()
            entries.append(LogEntry(timestamp: Date(), level: level, operation: safeOperation, message: safeMessage))
            if entries.count > maximumEntries { entries.removeFirst(entries.count - maximumEntries) }
            writeUnlocked(entries)
        }
    }

    func entries() -> [LogEntry] { lock.withLock { readUnlocked() } }

    func clear() throws {
        try lock.withLock {
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        }
    }

    func exportText(filter: String = "") -> String {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries().filter { query.isEmpty || $0.operation.localizedCaseInsensitiveContains(query) || $0.message.localizedCaseInsensitiveContains(query) }
            .map { "\(ISO8601DateFormatter().string(from: $0.timestamp)) [\($0.level.rawValue.uppercased())] \($0.operation): \($0.message)" }
            .joined(separator: "\n")
    }

    private func readUnlocked() -> [LogEntry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(LogEntry.self, from: Data($0.utf8)) }
    }

    private func writeUnlocked(_ entries: [LogEntry]) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let data = entries.compactMap { try? encoder.encode($0) }
        let text = data.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + (data.isEmpty ? "" : "\n")
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            // Logging must never break the operation being recorded.
        }
    }
}
