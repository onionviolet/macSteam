import Foundation

enum AppBuildFlavor {
    static var isPrivate: Bool {
        Bundle.main.object(forInfoDictionaryKey: "MacSteamBuildFlavor") as? String == "private"
    }
}
