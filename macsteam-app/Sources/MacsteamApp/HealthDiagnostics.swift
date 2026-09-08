import Foundation

enum InstallationHealthState: String, Codable {
    case healthy = "Healthy"
    case needsRepair = "Needs Repair"
    case unsupported = "Unsupported"
    case missing = "Missing"
}

struct InstallationHealth: Equatable {
    let state: InstallationHealthState
    let summary: String
    let checks: [HealthCheck]
}

struct HealthCheck: Equatable {
    enum Status: String { case pass, warning, failure }
    let name: String
    let status: Status
    let detail: String
}

struct HealthEnvironment {
    let steamApp: URL
    let steamExecutable: URL
    let injectedDylib: URL
    let configFile: URL
    let packageDirectory: URL
    let supportedBuild: String
    let detectedBuild: String?
    let bundledVersion: String?
    let installedVersion: String?
    let architecture: String

    static var live: HealthEnvironment {
        HealthEnvironment(
            steamApp: Paths.steamApp,
            steamExecutable: Paths.steamAppExecutable,
            injectedDylib: Paths.steamAppInjectedDylib,
            configFile: Paths.configFile,
            packageDirectory: Paths.packageDir,
            supportedBuild: MacCrab.supportedVersion,
            detectedBuild: MacCrab.detectedVersion(),
            bundledVersion: SteamInstaller.bundledDylibVersion(),
            installedVersion: SteamInstaller.deployedDylibVersion(),
            architecture: Self.hostArchitecture
        )
    }

    private static var hostArchitecture: String {
        #if arch(arm64)
        return "Apple silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }
}

enum HealthDiagnostics {
    static func inspect(_ environment: HealthEnvironment = .live,
                        fileManager: FileManager = .default) -> InstallationHealth {
        func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }
        func readable(_ url: URL) -> Bool { fileManager.isReadableFile(atPath: url.path) }

        guard exists(environment.steamApp), exists(environment.steamExecutable) else {
            return InstallationHealth(state: .missing, summary: "Steam is not installed in /Applications.", checks: [
                HealthCheck(name: "Steam application", status: .failure, detail: "Not found")
            ])
        }

        var checks = [
            HealthCheck(name: "Steam application", status: readable(environment.steamExecutable) ? .pass : .failure,
                        detail: readable(environment.steamExecutable) ? "Present and readable" : "Executable is unreadable"),
            HealthCheck(name: "Host architecture", status: environment.architecture.contains("arm64") ? .pass : .warning,
                        detail: environment.architecture),
            HealthCheck(name: "Client package", status: exists(environment.packageDirectory) ? .pass : .warning,
                        detail: exists(environment.packageDirectory) ? "Present" : "Open Steam once to unpack it"),
            HealthCheck(name: "Configuration", status: exists(environment.configFile) ? .pass : .warning,
                        detail: exists(environment.configFile) ? "Present and readable: \(readable(environment.configFile))" : "Not created yet"),
            HealthCheck(name: "Managed component", status: exists(environment.injectedDylib) ? .pass : .warning,
                        detail: exists(environment.injectedDylib) ? "Present" : "Not installed")
        ]

        if let detected = environment.detectedBuild, detected != environment.supportedBuild {
            checks.append(HealthCheck(name: "Steam build", status: .failure,
                                      detail: "Detected \(detected); supported \(environment.supportedBuild)"))
            return InstallationHealth(state: .unsupported, summary: "This Steam build is not supported.", checks: checks)
        }
        checks.append(HealthCheck(name: "Steam build", status: environment.detectedBuild == nil ? .warning : .pass,
                                  detail: environment.detectedBuild ?? "Could not determine build"))

        if let bundled = environment.bundledVersion, let installed = environment.installedVersion,
           bundled != installed {
            checks.append(HealthCheck(name: "Component version", status: .failure,
                                      detail: "Installed \(installed); bundled \(bundled)"))
            return InstallationHealth(state: .needsRepair, summary: "The installed component needs an update.", checks: checks)
        }
        if checks.contains(where: { $0.status == .failure }) {
            return InstallationHealth(state: .needsRepair, summary: "Steam needs repair before it can be managed safely.", checks: checks)
        }
        return InstallationHealth(state: .healthy, summary: "Steam is ready for management.", checks: checks)
    }

    static func report(_ health: InstallationHealth, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let body = ([
            "macSteam diagnostic report",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "State: \(health.state.rawValue)",
            "Summary: \(health.summary)"
        ] + health.checks.map { "\($0.status.rawValue.uppercased()): \($0.name): \($0.detail)" }).joined(separator: "\n")
        return DiagnosticRedactor.redact(body, home: home)
    }
}

enum DiagnosticRedactor {
    private static let sensitiveKey = try! NSRegularExpression(
        pattern: #"(?i)\b(token|password|passwd|credential|secret|api[_-]?key|steamid|accountid)\b\s*[:=]\s*[^\s,;]+"#)
    private static let steamID = try! NSRegularExpression(pattern: #"\b7656119\d{10}\b|\bSTEAM_[0-5]:[01]:\d+\b|\b\[U:1:\d+\]"#)
    private static let userPath = try! NSRegularExpression(pattern: #"/Users/[^/\s]+"#)

    static func redact(_ input: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        var output = input.replacingOccurrences(of: home.path, with: "<HOME>")
        for regex in [sensitiveKey, steamID, userPath] {
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "<REDACTED>")
        }
        return output
    }
}
