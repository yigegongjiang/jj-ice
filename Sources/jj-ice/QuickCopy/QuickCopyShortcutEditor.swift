//
//  QuickCopyShortcutEditor.swift
//  jj-ice
//

import AppKit

/// The dialog behind `Quick Copy Shortcut...`. Typed rather than recorded: a text field says
/// exactly what is stored, and the error message doubles as the documentation.
@MainActor
final class QuickCopyShortcutEditor {
    private let controller: QuickCopyController
    private var isOpen = false

    init(controller: QuickCopyController) {
        self.controller = controller
    }

    func open() {
        // A second dialog would edit a stale copy of the text and race the first one's save.
        guard !isOpen else { return }
        isOpen = true
        defer { isOpen = false }

        // A loop rather than a single dialog: a rejected shortcut reports back and returns the user
        // to their text instead of throwing the edit away.
        var text = controller.shortcutText
        while true {
            let outcome = present(text: text)
            text = outcome.text
            guard outcome.response == .alertFirstButtonReturn else { return }
            do {
                try controller.save(text)
                let status = controller.status
                if status.isWarning {
                    report(title: "Saved, but Not Listening", body: status.message, isWarning: true)
                }
                return
            } catch {
                report(title: "Not Saved", body: error.localizedDescription, isWarning: true)
            }
        }
    }

    private func present(text: String) -> (response: NSApplication.ModalResponse, text: String) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = text
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.placeholderString = HotKeyShortcut.fallbackText

        let status = controller.status
        let alert = NSAlert()
        alert.messageText = "Quick Copy Shortcut"
        alert.informativeText = """
        \(status.message)

        The shortcut opens a text box in the middle of the screen the pointer is on. Return copies \
        what you typed to the clipboard and closes it, Shift+Return adds a line, Esc cancels.

        Write it as modifiers plus one key, joined by +: cmd+space, ctrl+opt+k, cmd+shift+f1.
        Modifiers  cmd, ctrl, opt, shift - at least one
        Key        a letter, a digit, f1-f20, or space, return, tab, escape, delete, an arrow
        """
        alert.alertStyle = status.isWarning ? .warning : .informational
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        return (response, field.stringValue)
    }

    private func report(title: String, body: String, isWarning: Bool) {
        let alert = NSAlert()
        alert.alertStyle = isWarning ? .warning : .informational
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
