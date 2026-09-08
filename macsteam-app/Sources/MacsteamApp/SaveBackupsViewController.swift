import AppKit

final class SaveBackupsViewController: NSViewController {
    private let manager = SaveBackupManager()
    private let gameID = NSTextField(string: "")
    private let titleField = NSTextField(string: "")
    private let backups = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "No save folder selected.")
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let loadButton = NSButton(title: "Load Backups", target: nil, action: nil)
    private let createButton = NSButton(title: "Back Up Folder…", target: nil, action: nil)
    private let restoreButton = NSButton(title: "Restore Selected…", target: nil, action: nil)
    private var records: [SaveBackupRecord] = []
    private var activeCancellation: BackupCancellation?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        gameID.placeholderString = "App ID or local game identifier"
        gameID.setAccessibilityLabel("Game identifier")
        titleField.placeholderString = "Game title"
        titleField.setAccessibilityLabel("Game title")
        backups.setAccessibilityLabel("Available backups")
        status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Backup status")
        loadButton.target = self; loadButton.action = #selector(loadBackups)
        createButton.target = self; createButton.action = #selector(createBackup)
        createButton.keyEquivalent = "b"; createButton.keyEquivalentModifierMask = [.command]
        restoreButton.target = self; restoreButton.action = #selector(restoreBackup)
        cancelButton.target = self; cancelButton.action = #selector(cancelBackupOperation); cancelButton.isEnabled = false
        let buttons = NSStackView(views: [loadButton, createButton, restoreButton, cancelButton])
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
        OperationalLog.shared.record(.info, operation: "backup", message: "Local save backup started for game \(id)")
        let cancellation = beginOperation("Backing up…")
        DispatchQueue.global(qos: .userInitiated).async { [manager] in
            let result = Result { try manager.createBackup(gameID: id, title: title, source: source,
                                                            cancelled: { cancellation.isCancelled }) }
            DispatchQueue.main.async { [weak self] in self?.finishBackup(result, gameID: id) }
        }
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
        OperationalLog.shared.record(.info, operation: "restore", message: "Local save restore started for game \(record.gameID)")
        let cancellation = beginOperation("Restoring…")
        DispatchQueue.global(qos: .userInitiated).async { [manager] in
            let result = Result { try manager.restore(record, to: destination, cancelled: { cancellation.isCancelled }) }
            DispatchQueue.main.async { [weak self] in self?.finishRestore(result, gameID: record.gameID) }
        }
    }

    @objc private func cancelBackupOperation() { activeCancellation?.cancel(); status.stringValue = "Cancelling safely…" }

    private func beginOperation(_ message: String) -> BackupCancellation {
        let cancellation = BackupCancellation(); activeCancellation = cancellation; cancelButton.isEnabled = true
        gameID.isEnabled = false; titleField.isEnabled = false; backups.isEnabled = false; status.stringValue = message
        loadButton.isEnabled = false; createButton.isEnabled = false; restoreButton.isEnabled = false
        return cancellation
    }

    private func endOperation() {
        activeCancellation = nil; cancelButton.isEnabled = false; gameID.isEnabled = true; titleField.isEnabled = true
        loadButton.isEnabled = true; createButton.isEnabled = true; restoreButton.isEnabled = true
    }

    private func finishBackup(_ result: Result<SaveBackupRecord, Error>, gameID: String) {
        endOperation()
        switch result {
        case .success:
            OperationalLog.shared.record(.info, operation: "backup", message: "Local save backup completed for game \(gameID)")
            records = manager.list(gameID: gameID); status.stringValue = "Backup completed. Existing files were not changed."; renderBackups(keepStatus: true)
        case .failure(let error):
            OperationalLog.shared.record(.error, operation: "backup", message: error.localizedDescription); status.stringValue = error.localizedDescription; renderBackups(keepStatus: true)
        }
    }

    private func finishRestore(_ result: Result<SaveBackupRecord?, Error>, gameID: String) {
        endOperation()
        switch result {
        case .success:
            OperationalLog.shared.record(.info, operation: "restore", message: "Local save restore completed for game \(gameID)")
            records = manager.list(gameID: gameID); status.stringValue = "Restore completed and the previous data was saved as a safety backup."; renderBackups(keepStatus: true)
        case .failure(let error):
            OperationalLog.shared.record(.error, operation: "restore", message: error.localizedDescription); status.stringValue = error.localizedDescription; renderBackups(keepStatus: true)
        }
    }

    private func renderBackups(keepStatus: Bool = false) {
        backups.removeAllItems()
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        backups.addItems(withTitles: records.map { "\($0.gameTitle), \(formatter.string(from: $0.createdAt)), \($0.originalName)" })
        backups.isEnabled = !records.isEmpty
        restoreButton.isEnabled = !records.isEmpty && activeCancellation == nil
        if !keepStatus { status.stringValue = records.isEmpty ? "No backups found for this game." : "\(records.count) versioned backup(s) available." }
    }
}
