import AppKit

final class ReadyCheckViewController: NSViewController {
    private let onRepair: () -> Void
    private let onInstall: () -> Void
    private let headline = NSTextField(labelWithString: "")
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let checklist = NSTextField(wrappingLabelWithString: "")
    private var steamButton: NSButton!
    private var repairButton: NSButton!
    private var installButton: NSButton!
    private var steamIsRunning = false

    init(onRepair: @escaping () -> Void, onInstall: @escaping () -> Void) {
        self.onRepair = onRepair
        self.onInstall = onInstall
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))

        headline.font = Typography.largeTitle
        headline.lineBreakMode = .byWordWrapping
        headline.maximumNumberOfLines = 0
        headline.setAccessibilityLabel("Readiness status")

        summary.font = Typography.body
        summary.textColor = .secondaryLabelColor
        summary.setAccessibilityLabel("Recommended next step")

        checklist.isSelectable = true
        checklist.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        checklist.textColor = .labelColor
        checklist.lineBreakMode = .byWordWrapping
        checklist.maximumNumberOfLines = 0
        checklist.setAccessibilityLabel("Ready Check results")

        let refreshButton = makeButton(title: "Refresh", target: self, action: #selector(refresh))
        refreshButton.keyEquivalent = "r"
        refreshButton.keyEquivalentModifierMask = [.command]
        steamButton = makeButton(title: "Open Steam", target: self, action: #selector(toggleSteam))
        repairButton = makeButton(title: "Review Repair", target: self, action: #selector(reviewRepair))
        installButton = makeButton(title: "Review Install", target: self, action: #selector(reviewInstall))
        let buttons = makeAdaptiveButtonStack([refreshButton, steamButton, repairButton, installButton])

        let stack = NSStackView(views: [headline, summary, checklist, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.paneMargin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.paneMargin),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.paneMargin),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Metrics.paneMargin),
            checklist.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    @objc private func refresh() {
        let snapshot = ReadyCheckSnapshot.live
        let assessment = ReadyCheck.evaluate(snapshot)
        updateAccessibleStatus(headline, text: assessment.headline)
        updateAccessibleStatus(summary, text: assessment.summary, announce: false)
        let checklistText = assessment.steps.map { step in
            "[\(step.state.rawValue.uppercased())] \(step.title)\n\(step.detail)"
        }.joined(separator: "\n\n")
        checklist.stringValue = checklistText

        let steamPresent = FileManager.default.fileExists(atPath: Paths.steamApp.path)
        steamIsRunning = snapshot.steamRunning
        steamButton.title = steamIsRunning ? "Quit Steam" : "Open Steam"
        steamButton.setAccessibilityLabel(steamButton.title)
        steamButton.isEnabled = steamPresent
        repairButton.isEnabled = steamPresent && !snapshot.steamRunning
        installButton.isEnabled = assessment.canInstall

        switch assessment.action {
        case .repair: repairButton.keyEquivalent = "\r"; installButton.keyEquivalent = ""
        case .install: installButton.keyEquivalent = "\r"; repairButton.keyEquivalent = ""
        default: repairButton.keyEquivalent = ""; installButton.keyEquivalent = ""
        }
    }

    @objc private func toggleSteam() {
        if steamIsRunning {
            MacCrab.quitSteam()
            refresh()
        } else {
            NSWorkspace.shared.open(Paths.steamApp)
        }
    }
    @objc private func reviewRepair() { onRepair() }
    @objc private func reviewInstall() { onInstall() }
}
