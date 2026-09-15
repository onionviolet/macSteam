import AppKit

final class SaveBackupsViewController: NSViewController {
    private let manager = SaveBackupManager()
    private let profiles = NSPopUpButton()
    private let gameID = NSTextField(string: "")
    private let titleField = NSTextField(string: "")
    private let profilePath = NSTextField(wrappingLabelWithString: "No save folder saved.")
    private let backups = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "Choose a save folder to create a backup profile.")
    private let chooseButton = NSButton(title: "Choose Save Folder…", target: nil, action: nil)
    private let removeButton = NSButton(title: "Forget Profile", target: nil, action: nil)
    private let createButton = NSButton(title: "Back Up Now", target: nil, action: nil)
    private let restoreButton = NSButton(title: "Restore Selected…", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var savedProfiles: [SaveBackupProfile] = []
    private var records: [SaveBackupRecord] = []
    private var activeCancellation: BackupCancellation?

    private var selectedProfile: SaveBackupProfile? {
        let index = profiles.indexOfSelectedItem
        return savedProfiles.indices.contains(index) ? savedProfiles[index] : nil
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 500))
        profiles.setAccessibilityLabel("Saved game backup profiles")
        profiles.target = self; profiles.action = #selector(selectProfile)
        gameID.placeholderString = "Steam App ID or local game identifier"
        gameID.setAccessibilityLabel("Game identifier for backup profile")
        titleField.placeholderString = "Game title"
        titleField.setAccessibilityLabel("Game title for backup profile")
        profilePath.textColor = .secondaryLabelColor
        profilePath.setAccessibilityLabel("Saved local folder")
        backups.setAccessibilityLabel("Available versioned backups")
        status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Backup status")

        chooseButton.target = self; chooseButton.action = #selector(chooseSaveFolder)
        removeButton.target = self; removeButton.action = #selector(removeProfile)
        createButton.target = self; createButton.action = #selector(createBackup)
        createButton.keyEquivalent = "b"; createButton.keyEquivalentModifierMask = [.command]
        restoreButton.target = self; restoreButton.action = #selector(restoreBackup)
        cancelButton.target = self; cancelButton.action = #selector(cancelBackupOperation)
        cancelButton.isEnabled = false

        let profileButtons = NSStackView(views: [chooseButton, removeButton])
        profileButtons.orientation = .horizontal; profileButtons.spacing = 8
        let backupButtons = NSStackView(views: [createButton, restoreButton, cancelButton])
        backupButtons.orientation = .horizontal; backupButtons.spacing = 8
        let explanation = NSTextField(wrappingLabelWithString:
            "Save one local folder for each game, then use Back Up Now. macSteam never searches for saves or follows symbolic links, and restore captures the current destination first.")
        explanation.textColor = .secondaryLabelColor
        explanation.setAccessibilityLabel("How game save backup profiles work")
        let stack = NSStackView(views: [explanation, profiles, gameID, titleField, profilePath,
                                        profileButtons, backups, backupButtons, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        for item in [explanation, profiles, gameID, titleField, profilePath, backups, status] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.paneMargin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.paneMargin),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.paneMargin),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            profiles.widthAnchor.constraint(equalTo: stack.widthAnchor),
            gameID.widthAnchor.constraint(equalTo: stack.widthAnchor),
            titleField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            profilePath.widthAnchor.constraint(equalTo: stack.widthAnchor),
            backups.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
        reloadProfiles()
    }

    @objc private func selectProfile() {
        guard let profile = selectedProfile else { renderSelection(); return }
        gameID.stringValue = profile.gameID
        titleField.stringValue = profile.gameTitle
        records = manager.list(gameID: profile.gameID)
        renderSelection()
    }

    @objc private func chooseSaveFolder() {
        let id = gameID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !title.isEmpty else {
            status.stringValue = "Enter a game identifier and title first."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = false; panel.allowsMultipleSelection = false
        panel.prompt = "Use Save Folder"
        panel.message = "Choose only this game's local save folder. Cloud and credential folders are rejected."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let profile = try manager.saveProfile(gameID: id, title: title, sourceDirectory: source)
            reloadProfiles(selecting: profile.gameID)
            status.stringValue = "Profile saved. Back Up Now will use this folder without searching elsewhere."
            OperationalLog.shared.record(.info, operation: "backup-profile", message: "Saved local backup profile for game \(id)")
        } catch {
            status.stringValue = error.localizedDescription
            OperationalLog.shared.record(.error, operation: "backup-profile", message: error.localizedDescription)
        }
    }

    @objc private func removeProfile() {
        guard let profile = selectedProfile else { return }
        let alert = NSAlert()
        alert.messageText = "Forget \(profile.gameTitle)'s backup profile?"
        alert.informativeText = "This removes only the saved folder mapping. Existing backups and game files stay in place."
        alert.addButton(withTitle: "Forget Profile")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try manager.removeProfile(gameID: profile.gameID)
            reloadProfiles()
            status.stringValue = "Profile forgotten. Existing backups were not removed."
            OperationalLog.shared.record(.info, operation: "backup-profile", message: "Removed backup profile for game \(profile.gameID)")
        } catch {
            status.stringValue = error.localizedDescription
        }
    }

    @objc private func createBackup() {
        guard let profile = selectedProfile else {
            status.stringValue = "Choose or create a saved game profile first."
            return
        }
        OperationalLog.shared.record(.info, operation: "backup", message: "Profile backup started for game \(profile.gameID)")
        let cancellation = beginOperation("Backing up \(profile.gameTitle)…")
        DispatchQueue.global(qos: .userInitiated).async { [manager] in
            let result = Result { try manager.createBackup(using: profile,
                                                            cancelled: { cancellation.isCancelled }) }
            DispatchQueue.main.async { [weak self] in self?.finishBackup(result, gameID: profile.gameID) }
        }
    }

    @objc private func restoreBackup() {
        guard backups.indexOfSelectedItem >= 0, backups.indexOfSelectedItem < records.count else {
            status.stringValue = "Select a backup first."
            return
        }
        let record = records[backups.indexOfSelectedItem]
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false; panel.prompt = "Choose Current Save"
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

    @objc private func cancelBackupOperation() {
        activeCancellation?.cancel()
        status.stringValue = "Cancelling safely…"
    }

    private func reloadProfiles(selecting gameID: String? = nil) {
        do {
            let previousID = gameID ?? selectedProfile?.gameID
            savedProfiles = try manager.listProfiles()
            profiles.removeAllItems()
            if savedProfiles.isEmpty {
                profiles.addItem(withTitle: "No saved game profiles")
                profiles.isEnabled = false
                records = []
            } else {
                profiles.addItems(withTitles: savedProfiles.map { "\($0.gameTitle) (\($0.gameID))" })
                profiles.isEnabled = activeCancellation == nil
                if let previousID, let index = savedProfiles.firstIndex(where: { $0.gameID == previousID }) {
                    profiles.selectItem(at: index)
                }
                selectProfile()
                return
            }
            renderSelection()
        } catch {
            savedProfiles = []; records = []
            profiles.removeAllItems(); profiles.addItem(withTitle: "Profiles unavailable")
            profiles.isEnabled = false
            status.stringValue = error.localizedDescription
            renderSelection(keepStatus: true)
        }
    }

    private func beginOperation(_ message: String) -> BackupCancellation {
        let cancellation = BackupCancellation()
        activeCancellation = cancellation; cancelButton.isEnabled = true
        profiles.isEnabled = false; gameID.isEnabled = false; titleField.isEnabled = false
        chooseButton.isEnabled = false; removeButton.isEnabled = false
        backups.isEnabled = false; createButton.isEnabled = false; restoreButton.isEnabled = false
        status.stringValue = message
        return cancellation
    }

    private func endOperation() {
        activeCancellation = nil; cancelButton.isEnabled = false
        profiles.isEnabled = !savedProfiles.isEmpty
        gameID.isEnabled = true; titleField.isEnabled = true; chooseButton.isEnabled = true
        renderSelection(keepStatus: true)
    }

    private func finishBackup(_ result: Result<SaveBackupRecord, Error>, gameID: String) {
        endOperation()
        switch result {
        case .success:
            OperationalLog.shared.record(.info, operation: "backup", message: "Profile backup completed for game \(gameID)")
            records = manager.list(gameID: gameID)
            status.stringValue = "Backup completed. Existing game files were not changed."
            renderSelection(keepStatus: true)
        case .failure(let error):
            OperationalLog.shared.record(.error, operation: "backup", message: error.localizedDescription)
            status.stringValue = error.localizedDescription
            renderSelection(keepStatus: true)
        }
    }

    private func finishRestore(_ result: Result<SaveBackupRecord?, Error>, gameID: String) {
        endOperation()
        switch result {
        case .success:
            OperationalLog.shared.record(.info, operation: "restore", message: "Local save restore completed for game \(gameID)")
            records = manager.list(gameID: gameID)
            status.stringValue = "Restore completed and the previous data was saved as a safety backup."
            renderSelection(keepStatus: true)
        case .failure(let error):
            OperationalLog.shared.record(.error, operation: "restore", message: error.localizedDescription)
            status.stringValue = error.localizedDescription
            renderSelection(keepStatus: true)
        }
    }

    private func renderSelection(keepStatus: Bool = false) {
        profilePath.stringValue = selectedProfile.map {
            "Saved folder: \(($0.sourceDirectory.path as NSString).abbreviatingWithTildeInPath)"
        } ?? "No save folder saved."
        backups.removeAllItems()
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        backups.addItems(withTitles: records.map {
            "\($0.gameTitle), \(formatter.string(from: $0.createdAt)), \($0.originalName)"
        })
        let idle = activeCancellation == nil
        backups.isEnabled = !records.isEmpty && idle
        createButton.isEnabled = selectedProfile != nil && idle
        restoreButton.isEnabled = !records.isEmpty && idle
        removeButton.isEnabled = selectedProfile != nil && idle
        if !keepStatus {
            status.stringValue = selectedProfile == nil
                ? "Enter a game and choose its local save folder to create a profile."
                : records.isEmpty ? "Profile ready. No backups yet." : "\(records.count) versioned backup(s) available."
        }
    }
}
