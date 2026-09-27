// Sparkle auto-update lifecycle
import AppKit
import Combine
import Sparkle

@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController
    private let updatesEnabled: Bool

    @Published var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get { updatesEnabled && controller.updater.automaticallyChecksForUpdates }
        set {
            guard updatesEnabled else { return }
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    private override init() {
        // Missing metadata fails closed. Only an explicitly update-enabled build may
        // initialize Sparkle, which prevents a private build from consuming the
        // upstream appcast even if feed metadata is accidentally added later.
        updatesEnabled = Bundle.main.object(forInfoDictionaryKey: "MacSteamUpdatesEnabled") as? Bool == true
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        if updatesEnabled {
            controller.updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
        }
    }

    func start() {
        guard updatesEnabled else {
            OperationalLog.shared.record(.info, operation: "update", message: "Updates disabled for this build")
            return
        }
        #if DEBUG
        return
        #else
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        OperationalLog.shared.record(.info, operation: "update", message: "Manual update check requested")
        guard updatesEnabled else {
            OperationalLog.shared.record(.info, operation: "update", message: "Update check ignored: updates disabled for this build")
            return
        }
        #if DEBUG
        return
        #else
        controller.checkForUpdates(nil)
        #endif
    }
}
