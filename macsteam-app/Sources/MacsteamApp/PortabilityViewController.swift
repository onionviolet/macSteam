import AppKit

final class PortabilityViewController: NSViewController {
    private let store: ConfigStore
    private let status = NSTextField(wrappingLabelWithString: "Export creates a versioned JSON document containing only safe app preferences.")

    init(store: ConfigStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        let explanation = NSTextField(wrappingLabelWithString:
            "Import validates the schema, rejects unknown fields, previews every change, and backs up the current config before an atomic write. Game access data is never exported.")
        explanation.textColor = .secondaryLabelColor
        let export = makeButton(title: "Export Settings…", target: self, action: #selector(exportSettings))
        export.keyEquivalent = "e"; export.keyEquivalentModifierMask = [.command, .shift]
        let importButton = makeButton(title: "Import Settings…", target: self, action: #selector(importSettings))
        let recovery = makeButton(title: "Show Recovery Backups", target: self, action: #selector(showBackups))
        let buttons = NSStackView(views: [export, importButton, recovery]); buttons.orientation = .horizontal; buttons.spacing = 8
        status.textColor = .secondaryLabelColor; status.setAccessibilityLabel("Portability status")
        let stack = NSStackView(views: [explanation, buttons, status]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        explanation.translatesAutoresizingMaskIntoConstraints = false; status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.paneMargin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.paneMargin),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.paneMargin),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        view = root
    }

    @objc private func exportSettings() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "macsteam-settings-v1.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ConfigurationPortability.export(config: store.config)
            try data.write(to: url, options: .atomic)
            OperationalLog.shared.record(.info, operation: "settings export", message: "Portable settings exported")
            status.stringValue = "Settings exported using schema version 1."
        } catch { OperationalLog.shared.record(.error, operation: "settings export", message: error.localizedDescription); status.stringValue = error.localizedDescription }
    }

    @objc private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = try ConfigurationPortability.decode(Data(contentsOf: url))
            let changes = ConfigurationPortability.preview(document, current: store.config)
            guard !changes.isEmpty else { status.stringValue = "The imported settings already match the current settings."; return }
            let alert = NSAlert(); alert.messageText = "Apply imported settings?"; alert.informativeText = changes.map { "\($0.name): \($0.oldValue) to \($0.newValue)" }.joined(separator: "\n") + "\n\nThe current config will be backed up first."; alert.addButton(withTitle: "Back Up and Apply"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try store.apply(document)
            OperationalLog.shared.record(.info, operation: "settings import", message: "Validated portable settings applied")
            status.stringValue = "Settings imported. The previous config is available in Recovery Backups."
        } catch { OperationalLog.shared.record(.error, operation: "settings import", message: error.localizedDescription); status.stringValue = error.localizedDescription }
    }

    @objc private func showBackups() {
        do { try Paths.ensureDir(Paths.configBackupDir); NSWorkspace.shared.activateFileViewerSelecting([Paths.configBackupDir]) }
        catch { status.stringValue = error.localizedDescription }
    }
}
