import AppKit

final class LibraryViewController: NSViewController, NSSearchFieldDelegate {
    private let search = NSSearchField()
    private let summary = NSTextField(labelWithString: "")
    private let content = NSTextView()
    private var result = LibraryScanResult(games: [], warnings: [])

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        search.placeholderString = "Filter installed games"
        search.delegate = self
        search.setAccessibilityLabel("Filter installed games")
        summary.font = Typography.body
        summary.textColor = .secondaryLabelColor
        content.isEditable = false
        content.isSelectable = true
        content.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        content.textContainerInset = NSSize(width: 10, height: 10)
        content.setAccessibilityLabel("Installed games")
        let scroll = NSScrollView()
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let refresh = makeButton(title: "Scan Again", target: self, action: #selector(scanLibrary))
        refresh.keyEquivalent = "r"
        refresh.keyEquivalentModifierMask = [.command]
        let stack = NSStackView(views: [search, summary, scroll, refresh])
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
        scanLibrary()
    }

    override func viewDidAppear() { super.viewDidAppear(); scanLibrary() }
    func controlTextDidChange(_ obj: Notification) { render() }

    @objc private func scanLibrary() {
        result = SteamLibraryScanner.scan()
        render()
    }

    private func render() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let games = query.isEmpty ? result.games : result.games.filter {
            $0.title.localizedCaseInsensitiveContains(query) || String($0.appID).contains(query)
        }
        summary.stringValue = result.games.isEmpty
            ? "No installed Steam games were found. \(result.warnings.first ?? "Open Steam once, then scan again.")"
            : "\(result.games.count) installed game(s). \(result.warnings.count) scan warning(s)."
        let formatter = ByteCountFormatter()
        content.string = games.map { game in
            let size = game.sizeOnDisk.map { formatter.string(fromByteCount: $0) } ?? "Size unavailable"
            let backup = game.lastBackup.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? "Never"
            return "\(game.title)\nApp ID \(game.appID) | \(game.libraryLabel) | \(size)\n\(game.compatibility.rawValue) | \(game.configState) | Last backup: \(backup)"
        }.joined(separator: "\n\n")
    }
}
