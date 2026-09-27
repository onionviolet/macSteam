import Foundation

enum ReadyCheckStepState: String, Equatable {
    case ready = "Ready"
    case attention = "Check"
    case blocked = "Action Needed"
}

struct ReadyCheckStep: Equatable {
    let title: String
    let state: ReadyCheckStepState
    let detail: String
}

struct ReadyCheckSnapshot: Equatable {
    let architectureSupported: Bool
    let steamInstalled: Bool
    let packagePresent: Bool
    let steamRunning: Bool
    let detectedBuild: String?
    let referenceBuild: String
    let installerStatus: SteamInstaller.Status
    let updateBlockEnabled: Bool

    static var live: ReadyCheckSnapshot {
        let fm = FileManager.default
        #if arch(arm64)
        let architectureSupported = true
        #else
        let architectureSupported = false
        #endif
        return ReadyCheckSnapshot(
            architectureSupported: architectureSupported,
            steamInstalled: fm.fileExists(atPath: Paths.steamAppExecutable.path),
            packagePresent: fm.fileExists(atPath: Paths.packageDir.path),
            steamRunning: MacCrab.isSteamRunning(),
            detectedBuild: MacCrab.detectedVersion(),
            referenceBuild: MacCrab.supportedVersion,
            installerStatus: SteamInstaller.status(),
            updateBlockEnabled: SteamInstaller.updateBlockEnabled()
        )
    }
}

struct ReadyCheckAssessment: Equatable {
    enum Action: Equatable { case none, openSteam, repair, install }

    let headline: String
    let summary: String
    let steps: [ReadyCheckStep]
    let action: Action
    let canInstall: Bool
}

enum ReadyCheck {
    static func evaluate(_ snapshot: ReadyCheckSnapshot = .live) -> ReadyCheckAssessment {
        var steps: [ReadyCheckStep] = []

        steps.append(ReadyCheckStep(
            title: "Mac architecture",
            state: snapshot.architectureSupported ? .ready : .blocked,
            detail: snapshot.architectureSupported ? "Apple silicon is supported." : "This build requires Apple silicon."
        ))

        steps.append(ReadyCheckStep(
            title: "Steam application",
            state: snapshot.steamInstalled ? .ready : .blocked,
            detail: snapshot.steamInstalled ? "Steam is installed and readable." : "Install Steam in Applications first."
        ))

        steps.append(ReadyCheckStep(
            title: "Steam client files",
            state: snapshot.packagePresent ? .ready : .blocked,
            detail: snapshot.packagePresent
                ? "Steam has unpacked its client package."
                : "Open Steam once and let setup finish, then quit and refresh."
        ))

        steps.append(ReadyCheckStep(
            title: "Steam process",
            state: snapshot.steamRunning ? .blocked : .ready,
            detail: snapshot.steamRunning
                ? "Quit Steam completely before repairing or installing."
                : "Steam is closed."
        ))

        let buildStep: ReadyCheckStep
        if let build = snapshot.detectedBuild {
            if build == snapshot.referenceBuild {
                buildStep = ReadyCheckStep(title: "Steam build", state: .ready,
                    detail: "Detected reference build \(build).")
            } else {
                buildStep = ReadyCheckStep(title: "Steam build", state: .attention,
                    detail: "Detected \(build). The bundled reference is \(snapshot.referenceBuild); a mismatch is advisory and does not require a downgrade.")
            }
        } else {
            buildStep = ReadyCheckStep(title: "Steam build", state: .attention,
                detail: "The client build could not be read. This does not by itself make Steam unsupported.")
        }
        steps.append(buildStep)

        let installStep: ReadyCheckStep
        let action: ReadyCheckAssessment.Action
        switch snapshot.installerStatus {
        case .steamMissing:
            installStep = ReadyCheckStep(title: "macSteam installation", state: .blocked,
                detail: "Steam must be installed first.")
            action = .none
        case .foreign:
            installStep = ReadyCheckStep(title: "macSteam installation", state: .blocked,
                detail: "Steam contains an unrecognized modification. Repair Steam before continuing.")
            action = .repair
        case .notInstalled:
            installStep = ReadyCheckStep(title: "macSteam installation", state: .attention,
                detail: "macSteam is not installed yet.")
            action = .install
        case .outdated(let bundled, let deployed):
            installStep = ReadyCheckStep(title: "macSteam installation", state: .attention,
                detail: "Installed component \(deployed) can be updated to \(bundled).")
            action = .install
        case .installed:
            installStep = ReadyCheckStep(title: "macSteam installation", state: .ready,
                detail: snapshot.updateBlockEnabled
                    ? "Installed with client updates blocked."
                    : "Installed, but Steam client updates are currently allowed.")
            action = snapshot.updateBlockEnabled ? .none : .install
        }
        steps.append(installStep)

        guard snapshot.architectureSupported else {
            return ReadyCheckAssessment(headline: "This Mac is not supported",
                summary: "The private build requires Apple silicon.", steps: steps,
                action: .none, canInstall: false)
        }
        guard snapshot.steamInstalled else {
            return ReadyCheckAssessment(headline: "Install Steam first",
                summary: "Steam was not found in Applications.", steps: steps,
                action: .none, canInstall: false)
        }
        guard snapshot.packagePresent else {
            return ReadyCheckAssessment(headline: "Finish Steam setup",
                summary: "Open Steam, let it finish updating, quit it, reopen it once, then quit and refresh this check.",
                steps: steps, action: .openSteam, canInstall: false)
        }
        guard !snapshot.steamRunning else {
            return ReadyCheckAssessment(headline: "Quit Steam to continue",
                summary: "Steam must be fully closed before Repair or Install changes its application bundle.",
                steps: steps, action: .openSteam, canInstall: false)
        }
        if snapshot.installerStatus == .foreign {
            return ReadyCheckAssessment(headline: "Repair Steam before installing",
                summary: "The current modification is not recognized, so a clean repair is the safe next step.",
                steps: steps, action: .repair, canInstall: false)
        }

        switch snapshot.installerStatus {
        case .installed where snapshot.updateBlockEnabled:
            return ReadyCheckAssessment(headline: "Ready",
                summary: "macSteam is installed and the verifiable safety checks pass.",
                steps: steps, action: .none, canInstall: true)
        case .installed:
            return ReadyCheckAssessment(headline: "Review update protection",
                summary: "macSteam is installed, but Steam client updates are allowed.",
                steps: steps, action: .install, canInstall: true)
        case .outdated:
            return ReadyCheckAssessment(headline: "Ready to update",
                summary: "Steam is closed and the bundled macSteam component can be applied without changing the Steam build.",
                steps: steps, action: .install, canInstall: true)
        case .notInstalled:
            return ReadyCheckAssessment(headline: "Ready to install",
                summary: "Steam is closed and ready. A different client build is advisory, so no downgrade is required.",
                steps: steps, action: .install, canInstall: true)
        case .steamMissing, .foreign:
            return ReadyCheckAssessment(headline: "Action needed",
                summary: "Complete the highlighted step before installing.",
                steps: steps, action: action, canInstall: false)
        }
    }
}
