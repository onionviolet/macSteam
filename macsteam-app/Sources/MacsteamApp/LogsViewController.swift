import AppKit

final class LogsViewController: NSViewController, NSSearchFieldDelegate {
    private let search = NSSearchField()
    private let content = NSTextView()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        search.placeholderString = "Search operations and messages"
        search.delegate = self
        search.setAccessibilityLabel("Search logs")
        content.isEditable = false
        content.isSelectable = true
        content.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        content.setAccessibilityLabel("Operational log")
        let scroll = NSScrollView(); scroll.documentView = content; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let refresh = makeButton(title: "Refresh", target: self, action: #selector(refreshLog))
        let copy = makeButton(title: "Copy", target: self, action: #selector(copyLog))
        let export = makeButton(title: "Export…", target: self, action: #selector(exportLog))
        let clear = makeButton(title: "Clear…", target: self, action: #selector(clearLog))
        let buttons = NSStackView(views: [refresh, copy, export, clear]); buttons.orientation = .horizontal; buttons.spacing = 8
        let stack = NSStackView(views: [search, scroll, buttons]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.paneMargin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.paneMargin),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.paneMargin),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Metrics.paneMargin),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
        view = root
        refreshLog()
    }

    override func viewDidAppear() { super.viewDidAppear(); refreshLog() }
    func controlTextDidChange(_ obj: Notification) { refreshLog() }
    @objc private func refreshLog() {
        let text = OperationalLog.shared.exportText(filter: search.stringValue)
        content.string = text.isEmpty ? "No matching operations have been recorded." : text
    }
    @objc private func copyLog() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(OperationalLog.shared.exportText(filter: search.stringValue), forType: .string)
    }
    @objc private func exportLog() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "macsteam-operations.txt"; panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try OperationalLog.shared.exportText(filter: search.stringValue).write(to: url, atomically: true, encoding: .utf8) }
        catch { NSAlert(error: error).runModal() }
    }
    @objc private func clearLog() {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "Clear the operational log?"; alert.informativeText = "This removes the local support history and cannot be undone."; alert.addButton(withTitle: "Clear"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try OperationalLog.shared.clear(); refreshLog() } catch { NSAlert(error: error).runModal() }
    }
}
