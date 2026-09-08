import AppKit

final class SaveBackupsViewController: NSViewController {
    private let manager = SaveBackupManager()
    private let gameID = NSTextField(string: "")
    private let titleField = NSTextField(string: "")
    private let backups = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "No save folder selected.")
    private var records: [SaveBackupRecord] = []

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        gameID.placeholderString = "App ID or local game identifier"
        gameID.setAccessibilityLabel("Game identifier")
        titleField.placeholderString = "Game title"
        titleField.setAccessibilityLabel("Game title")
        backups.setAccessibilityLabel("Available backups")
        status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Backup status")
        let refresh = makeButton(title: "Load Backups", target: self, action: #selector(loadBackups))
        let create = makeButton(title: "Back Up Folder…", target: self, action: #selector(createBackup))
        create.keyEquivalent = "b"
        create.keyEquivalentModifierMask = [.command]
        let restore = makeButton(title: "Restore Selected…", target: self, action: #selector(restoreBackup))
        let buttons = NSStackView(views: [refresh, create, restore])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let explanation = NSTextField(wrappingLabelWithString:
            "Choose a local save folder. Backups are versioned by game. Restore always captures the current destination first and never follows symbolic links.")
        explanation.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [explanation, gameID, titleField, backups, buttons, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [explanation, gameID, titleField, backups, status] { view.translatesAutoresizingMaskIntoConstraints = false }
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.paneMargin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.paneMargin),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.paneMargin),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            gameID.widthAnchor.constraint(equalTo: stack.widthAnchor),
            titleField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            backups.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        renderBackups()
    }

    @objc private func loadBackups() {
        records = manager.list(gameID: gameID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        renderBackups()
    }

    @objc private func createBackup() {
        let id = gameID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !title.isEmpty else { status.stringValue = "Enter a game identifier and title first."; return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Back Up"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            _ = try manager.createBackup(gameID: id, title: title, source: source)
            records = manager.list(gameID: id)
            status.stringValue = "Backup completed. Existing files were not changed."
            renderBackups(keepStatus: true)
        } catch { status.stringValue = error.localizedDescription }
    }

    @objc private func restoreBackup() {
        guard backups.indexOfSelectedItem >= 0, backups.indexOfSelectedItem < records.count else {
            status.stringValue = "Load and select a backup first."; return
        }
        let record = records[backups.indexOfSelectedItem]
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Current Save"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restore this backup?"
        alert.informativeText = "macSteam will create a safety backup of the selected destination before replacing it."
        alert.addButton(withTitle: "Create Safety Backup and Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try manager.restore(record, to: destination)
            records = manager.list(gameID: record.gameID)
            status.stringValue = "Restore completed and the previous data was saved as a safety backup."
            renderBackups(keepStatus: true)
        } catch { status.stringValue = error.localizedDescription }
    }

    private func renderBackups(keepStatus: Bool = false) {
        backups.removeAllItems()
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        backups.addItems(withTitles: records.map { "\($0.gameTitle), \(formatter.string(from: $0.createdAt)), \($0.originalName)" })
        backups.isEnabled = !records.isEmpty
        if !keepStatus { status.stringValue = records.isEmpty ? "No backups found for this game." : "\(records.count) versioned backup(s) available." }
    }
}
