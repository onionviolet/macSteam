import Foundation

struct PortableSettings: Codable, Equatable {
    let schemaVersion: Int
    let settings: Settings

    struct Settings: Codable, Equatable {
        let hideWhatsNew: Bool
    }
}

struct SettingsChange: Equatable {
    let name: String
    let oldValue: String
    let newValue: String
}

enum ConfigurationPortabilityError: LocalizedError {
    case invalidDocument
    case unsupportedVersion(Int)
    case unknownFields([String])

    var errorDescription: String? {
        switch self {
        case .invalidDocument: return "The file is not a valid macSteam settings document."
        case .unsupportedVersion(let version): return "Settings schema version \(version) is not supported."
        case .unknownFields(let fields): return "Unknown fields were rejected: \(fields.joined(separator: ", "))."
        }
    }
}

enum ConfigurationPortability {
    static func export(config: MacsteamConfig) throws -> Data {
        let document = PortableSettings(schemaVersion: 1,
            settings: .init(hideWhatsNew: config.hideWhatsNew))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> PortableSettings {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = root["settings"] as? [String: Any] else { throw ConfigurationPortabilityError.invalidDocument }
        let rootUnknown = Set(root.keys).subtracting(["schemaVersion", "settings"])
        let settingsUnknown = Set(settings.keys).subtracting(["hideWhatsNew"])
        let unknown = rootUnknown.map { $0 } + settingsUnknown.map { "settings.\($0)" }
        guard unknown.isEmpty else { throw ConfigurationPortabilityError.unknownFields(unknown.sorted()) }
        let decoder = JSONDecoder()
        guard let document = try? decoder.decode(PortableSettings.self, from: data) else {
            throw ConfigurationPortabilityError.invalidDocument
        }
        guard document.schemaVersion == 1 else {
            throw ConfigurationPortabilityError.unsupportedVersion(document.schemaVersion)
        }
        return document
    }

    static func preview(_ document: PortableSettings, current: MacsteamConfig) -> [SettingsChange] {
        guard document.settings.hideWhatsNew != current.hideWhatsNew else { return [] }
        return [SettingsChange(name: "Hide What's New", oldValue: current.hideWhatsNew ? "On" : "Off",
                               newValue: document.settings.hideWhatsNew ? "On" : "Off")]
    }
}
