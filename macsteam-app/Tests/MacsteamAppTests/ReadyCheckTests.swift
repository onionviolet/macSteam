import XCTest
@testable import MacsteamApp

final class ReadyCheckTests: XCTestCase {
    func testDifferentSteamBuildDoesNotBlockInstall() {
        let result = ReadyCheck.evaluate(snapshot(detectedBuild: "new", installerStatus: .notInstalled))
        XCTAssertTrue(result.canInstall)
        XCTAssertEqual(result.action, .install)
        XCTAssertEqual(result.steps.first(where: { $0.title == "Steam build" })?.state, .attention)
    }

    func testRunningSteamBlocksInstall() {
        let result = ReadyCheck.evaluate(snapshot(steamRunning: true, installerStatus: .notInstalled))
        XCTAssertFalse(result.canInstall)
        XCTAssertEqual(result.headline, "Quit Steam to continue")
    }

    func testMissingPackageExplainsLaunchCycle() {
        let result = ReadyCheck.evaluate(snapshot(packagePresent: false, installerStatus: .notInstalled))
        XCTAssertFalse(result.canInstall)
        XCTAssertEqual(result.action, .openSteam)
        XCTAssertTrue(result.summary.contains("reopen it once"))
    }

    func testForeignModificationRoutesToRepair() {
        let result = ReadyCheck.evaluate(snapshot(installerStatus: .foreign))
        XCTAssertFalse(result.canInstall)
        XCTAssertEqual(result.action, .repair)
    }

    func testInstalledProtectedStateIsReady() {
        let result = ReadyCheck.evaluate(snapshot(installerStatus: .installed, updateBlockEnabled: true))
        XCTAssertTrue(result.canInstall)
        XCTAssertEqual(result.action, .none)
        XCTAssertEqual(result.headline, "Ready")
    }

    private func snapshot(architectureSupported: Bool = true,
                          steamInstalled: Bool = true,
                          packagePresent: Bool = true,
                          steamRunning: Bool = false,
                          detectedBuild: String? = "reference",
                          installerStatus: SteamInstaller.Status,
                          updateBlockEnabled: Bool = false) -> ReadyCheckSnapshot {
        ReadyCheckSnapshot(architectureSupported: architectureSupported,
            steamInstalled: steamInstalled, packagePresent: packagePresent,
            steamRunning: steamRunning, detectedBuild: detectedBuild,
            referenceBuild: "reference", installerStatus: installerStatus,
            updateBlockEnabled: updateBlockEnabled)
    }
}
