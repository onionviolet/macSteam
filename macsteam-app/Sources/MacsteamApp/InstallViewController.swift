// Install pane
import AppKit

final class InstallViewController: NSViewController {

    private var statusGlyph: NSImageView!
    private var headlineLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var installButton: NSButton!
    private var uninstallButton: NSButton!
    private var updateBlockButton: NSButton!
    private var openButton: NSButton!
    private var spinner: NSProgressIndicator!

    private var bundledDylib: URL? {
        Bundle.main.url(forResource: "macsteam", withExtension: "dylib")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))

        statusGlyph = NSImageView()
        statusGlyph.symbolConfiguration = .init(pointSize: 40, weight: .regular)
        statusGlyph.setAccessibilityElement(false)
        statusGlyph.translatesAutoresizingMaskIntoConstraints = false

        headlineLabel = NSTextField(labelWithString: "")
        headlineLabel.font = Typography.largeTitle
        headlineLabel.textColor = .labelColor
        headlineLabel.alignment = .center
        headlineLabel.lineBreakMode = .byWordWrapping
        headlineLabel.maximumNumberOfLines = 0
        headlineLabel.setAccessibilityLabel("Installation status")
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel = NSTextField(labelWithString: "")
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Typography.body
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 0
        detailLabel.setAccessibilityLabel("Installation details")

        installButton = makeButton(title: "Install", target: self, action: #selector(doInstall))
        installButton.keyEquivalent = "\r"
        installButton.setAccessibilityHelp("Installs the bundled macSteam patch into Steam.")
        uninstallButton = makeButton(title: "Uninstall", target: self, action: #selector(doUninstall))
        uninstallButton.setAccessibilityHelp("Restores a clean Valve-signed Steam installation after confirmation.")
        updateBlockButton = makeButton(title: "Allow Updates", target: self, action: #selector(toggleUpdateBlock))
        updateBlockButton.setAccessibilityHelp("Changes whether Steam may update its client.")
        openButton = makeButton(title: "Open Steam", target: self, action: #selector(openSteam))

        spinner = NSProgressIndicator()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.setAccessibilityLabel("Installation in progress")

        let footerDivider = NSBox()
        footerDivider.boxType = .separator
        footerDivider.translatesAutoresizingMaskIntoConstraints = false

        let statusGroup = NSStackView(views: [statusGlyph, headlineLabel, detailLabel])
        statusGroup.orientation = .vertical
        statusGroup.alignment = .centerX
        statusGroup.spacing = 6
        statusGroup.setCustomSpacing(12, after: statusGlyph)
        statusGroup.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(statusGroup)
        root.addSubview(footerDivider)
        root.addSubview(openButton)
        root.addSubview(updateBlockButton)
        root.addSubview(uninstallButton)
        root.addSubview(installButton)
        root.addSubview(spinner)

        let M = Metrics.paneMargin
        NSLayoutConstraint.activate([
            statusGroup.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            statusGroup.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            statusGroup.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            statusGroup.topAnchor.constraint(greaterThanOrEqualTo: root.topAnchor, constant: M),
            statusGroup.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: M),

            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380),

            footerDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerDivider.bottomAnchor.constraint(equalTo: installButton.topAnchor, constant: -12),
            footerDivider.topAnchor.constraint(greaterThanOrEqualTo: statusGroup.bottomAnchor, constant: Metrics.headerGap),

            installButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -M),
            installButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -M),

            uninstallButton.trailingAnchor.constraint(equalTo: installButton.leadingAnchor, constant: -10),
            uninstallButton.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),

            updateBlockButton.trailingAnchor.constraint(equalTo: uninstallButton.leadingAnchor, constant: -10),
            updateBlockButton.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),

            openButton.trailingAnchor.constraint(equalTo: updateBlockButton.leadingAnchor, constant: -10),
            openButton.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),

            spinner.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: M),
        ])

        view = root
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    // MARK: - Status rendering

    private func refresh() {
        let status = SteamInstaller.status()
        let hasPayload = (bundledDylib != nil)
        let blockOn = SteamInstaller.updateBlockEnabled()

        let summary = summarize(status: status, blockOn: blockOn)
        statusGlyph.image = NSImage(systemSymbolName: summary.tone.symbol, accessibilityDescription: nil)
        statusGlyph.contentTintColor = summary.tone.color
        updateAccessibleStatus(headlineLabel, text: summary.headline)
        updateAccessibleStatus(detailLabel, text: summary.detail, announce: false)

        switch status {
        case .installed:
            installButton.title = "Reinstall"
            uninstallButton.isEnabled = true
            openButton.isEnabled = true
        case .outdated:
            installButton.title = "Update"
            uninstallButton.isEnabled = true
            openButton.isEnabled = true
        case .notInstalled:
            installButton.title = "Install"
            uninstallButton.isEnabled = false
            openButton.isEnabled = true
        case .foreign:
            installButton.title = "Install"
            uninstallButton.isEnabled = true
            openButton.isEnabled = true
        case .steamMissing:
            installButton.title = "Install"
            uninstallButton.isEnabled = false
            openButton.isEnabled = false
        }

        updateBlockButton.title = blockOn ? "Allow Updates" : "Block Updates"
        switch status {
        case .installed, .outdated: updateBlockButton.isEnabled = true
        default: updateBlockButton.isEnabled = false
        }

        installButton.isEnabled = hasPayload && status != .steamMissing
    }

    private struct Summary {
        let tone: StatusTone
        let headline: String
        let detail: String
    }

    private func summarize(status: SteamInstaller.Status, blockOn: Bool) -> Summary {
        switch status {
        case .steamMissing:
            return Summary(tone: .bad, headline: "Steam not found",
                           detail: "Steam isn't in your Applications folder. Install it from Valve, then come back.")
        case .installed:
            return blockOn
                ? Summary(tone: .ok, headline: "Installed", detail: "")
                : Summary(tone: .warn, headline: "Installed, updates allowed",
                          detail: "Steam can update its client. A future update will break macSteam until macSteam is updated to match.")
        case .outdated(let bundled, let deployed):
            return Summary(tone: .warn, headline: "Update available",
                           detail: "A newer dylib is bundled (v\(bundled)). The installed version is v\(deployed). Click Update to apply it.")
        case .notInstalled, .foreign:
            return Summary(tone: .ok, headline: "Ready to install",
                           detail: "Steam is present. Click Install to patch it.")
        }
    }

    // MARK: - Actions

    @objc private func doInstall() {
        guard let dylib = bundledDylib else { return }

        switch MacCrab.status() {
        case .unsupported(let version):
            promptVersionFix(currentBuild: version, dylib: dylib)
        default:
            runInstall(dylib: dylib, pinFirst: false)
        }
    }

    private func promptVersionFix(currentBuild: String, dylib: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Steam build differs from the bundled reference"
        alert.informativeText = "Detected \(currentBuild); bundled reference \(MacCrab.supportedVersion). "
            + "Current Steam builds may remain compatible. Installing without changing Steam is recommended."
        alert.addButton(withTitle: "Install Without Changing Steam")
        alert.addButton(withTitle: "Use Reference Build")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:  runInstall(dylib: dylib, pinFirst: false)
        case .alertSecondButtonReturn: runInstall(dylib: dylib, pinFirst: true)
        default: return
        }
    }

    private func runInstall(dylib: URL, pinFirst: Bool) {
        runBusy(verb: "Installing") {
            switch SteamInstaller.status() {
            case .installed, .outdated:
                try SteamInstaller.install(sourceDylib: dylib)
            default:
                try MacCrab.ensurePristineBundle()
                if pinFirst { try MacCrab.pinToSupported() }
                try SteamInstaller.install(sourceDylib: dylib)
            }
        }
    }

    @objc private func doUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall macSteam from Steam?"
        alert.informativeText = "This downloads a clean, Valve-signed Steam and replaces the "
            + "installed one, removing macSteam completely. Takes a few minutes."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runBusy(verb: "Uninstalling") { try MacCrab.uninstallToStock() }
    }

    @objc private func toggleUpdateBlock() {
        guard SteamInstaller.updateBlockEnabled() else {
            runBusy { try SteamInstaller.enableUpdateBlock() }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Allow Steam to update?"
        alert.informativeText = "macSteam blocks the Steam client from updating the client "
            + "itself. If you disable this behavior, a future Steam update will break macSteam "
            + "until macSteam is updated to match. You have been warned."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runBusy { try SteamInstaller.disableUpdateBlock() }
    }

    @objc private func openSteam() {
        NSWorkspace.shared.open(Paths.steamApp)
    }

    private func runBusy(verb: String = "Working", _ work: @escaping @Sendable () throws -> Void) {
        statusGlyph.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                    accessibilityDescription: nil)
        statusGlyph.contentTintColor = .secondaryLabelColor
        updateAccessibleStatus(headlineLabel, text: "\(verb)…")
        updateAccessibleStatus(detailLabel, text: "", announce: false)

        MacsteamApp.runBusy(spinner: spinner, operation: verb.lowercased(), setBusy: { [self] busy in
            installButton.isEnabled = !busy && bundledDylib != nil
            uninstallButton.isEnabled = !busy
            updateBlockButton.isEnabled = !busy
            openButton.isEnabled = !busy
        }, refresh: { [self] in refresh() }, work: work)
    }
}
