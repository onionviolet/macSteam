import AppKit

final class LibraryViewController: NSViewController, NSSearchFieldDelegate {
    private let search = NSSearchField()
    private let summary = NSTextField(labelWithString: "")
    private let content = NSTextView()
    private var refreshButton: NSButton!
    private var result = LibraryScanResult(games: [], warnings: [])
    private var isScanning = false

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        search.placeholderString = "Filter installed games"
        search.delegate = self
        search.setAccessibilityLabel("Filter installed games")
        summary.font = Typography.body
        summary.textColor = .secondaryLabelColor
        summary.setAccessibilityLabel("Library scan status")
        content.isEditable = false
        content.isSelectable = true
        content.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        content.textContainerInset = NSSize(width: 10, height: 10)
        content.setAccessibilityLabel("Installed games")
        let scroll = NSScrollView()
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        refreshButton = makeButton(title: "Scan Again", target: self, action: #selector(scanLibrary))
        refreshButton.keyEquivalent = "r"
        refreshButton.keyEquivalentModifierMask = [.command]
        refreshButton.setAccessibilityHelp("Scans every configured Steam library again.")
        search.nextKeyView = content
        content.nextKeyView = refreshButton
        refreshButton.nextKeyView = search
        let stack = NSStackView(views: [search, summary, scroll, refreshButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.paneMargin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.paneMargin),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.paneMargin),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Metrics.paneMargin),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
        view = root
    }

    override func viewDidAppear() { super.viewDidAppear(); scanLibrary() }
    func controlTextDidChange(_ obj: Notification) { render(announce: false) }

    @objc private func scanLibrary() {
        guard !isScanning else { return }
        isScanning = true
        refreshButton?.isEnabled = false
        updateAccessibleStatus(summary, text: "Scanning configured Steam libraries…")
        OperationalLog.shared.record(.info, operation: "scan", message: "Installed-game scan started")
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = SteamLibraryScanner.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScanning = false
                self.refreshButton.isEnabled = true
                self.result = scanned
                OperationalLog.shared.record(scanned.warnings.isEmpty ? .info : .warning, operation: "scan",
                                             message: "Found \(scanned.games.count) installed game(s) with \(scanned.warnings.count) warning(s)")
                self.render(announce: true)
            }
        }
    }

    private func render(announce: Bool) {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let games = query.isEmpty ? result.games : result.games.filter {
            $0.title.localizedCaseInsensitiveContains(query) || String($0.appID).contains(query)
        }
        if result.games.isEmpty {
            updateAccessibleStatus(summary, text: "No installed Steam games were found. \(result.warnings.first ?? "Open Steam once, then choose Scan Again.")", announce: announce)
        } else if games.isEmpty {
            updateAccessibleStatus(summary, text: "No installed games match “\(query)”. Clear the filter to show all \(result.games.count) games.", announce: announce)
        } else {
            let warnings = result.warnings.isEmpty ? "" : " \(result.warnings.count) scan warning(s)."
            updateAccessibleStatus(summary, text: "Showing \(games.count) of \(result.games.count) installed game(s).\(warnings)", announce: announce)
        }
        let formatter = ByteCountFormatter()
        let listing = games.map { game in
            let size = game.sizeOnDisk.map { formatter.string(fromByteCount: $0) } ?? "Size unavailable"
            let backup = game.lastBackup.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? "Never"
            return "\(game.title)\nApp ID \(game.appID) | \(game.libraryLabel) | \(size)\nsteamapps/common/\(game.installDirectory.lastPathComponent)\n\(game.compatibility.rawValue) | \(game.configState) | Last backup: \(backup)"
        }.joined(separator: "\n\n")
        content.string = listing.isEmpty ? "No games to show. Use the filter above or choose Scan Again." : listing
    }
}
