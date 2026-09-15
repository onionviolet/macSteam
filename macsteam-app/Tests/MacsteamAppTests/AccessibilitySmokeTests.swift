import AppKit
import XCTest
@testable import MacsteamApp

@MainActor
final class AccessibilitySmokeTests: XCTestCase {
    func testSidebarHasSpokenNameAndDefaultsToLibrary() {
        var selected: MainViewController.Item?
        let controller = SidebarViewController { selected = $0 }
        let root = controller.view

        let outline = descendants(of: root).compactMap { $0 as? NSOutlineView }.first
        XCTAssertEqual(outline?.accessibilityLabel(), "Sections")

        controller.selectDefault()
        XCTAssertEqual(selected, .library)
    }

    func testManagementPaneButtonsHaveSpokenNames() {
        let controllers: [NSViewController] = [
            DiagnosticsViewController(),
            LibraryViewController(),
            LogsViewController(),
            InstallViewController(),
            RepairViewController(),
        ]

        for controller in controllers {
            let buttons = descendants(of: controller.view).compactMap { $0 as? NSButton }
            XCTAssertFalse(buttons.isEmpty, "Expected controls in \(type(of: controller))")
            XCTAssertTrue(buttons.allSatisfy { !($0.accessibilityLabel() ?? "").isEmpty },
                          "Every button needs a stable spoken name in \(type(of: controller))")
        }
    }

    func testEmptyStateExposesPromptAndActionableHelp() {
        let empty = EmptyStateView(symbol: "tray", prompt: "Nothing here", hint: "Choose Refresh to try again.")
        XCTAssertEqual(empty.accessibilityLabel(), "Nothing here")
        XCTAssertEqual(empty.accessibilityHelp(), "Choose Refresh to try again.")
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants(of:))
    }
}
