//
//  AirPodsNotifyEditor.swift
//  jj-ice
//

import AppKit

/// The JSON editor for the AirPods low battery rule. All of the AppKit for it lives here so
/// `Notify/` stays free of UI.
@MainActor
final class AirPodsNotifyEditor {
    private let readout: MenuBarReadout
    private var isOpen = false

    init(readout: MenuBarReadout) {
        self.readout = readout
    }

    func open() {
        // A second dialog would edit a stale copy of the text and race the first one's save.
        guard !isOpen else { return }
        isOpen = true
        Task { [weak self] in
            await self?.run()
            self?.isOpen = false
        }
    }

    /// A loop rather than a single dialog: an invalid rule or a test result reports back and returns
    /// the user to their text, instead of throwing the edit away.
    private func run() async {
        var text = readout.notifier.editorText
        while true {
            let outcome = present(text: text)
            text = outcome.text
            switch outcome.response {
            case .alertFirstButtonReturn:
                do {
                    try readout.notifier.save(text)
                    if !readout.showsBattery {
                        // The switch stops the polling that feeds the notifier, so a rule saved now
                        // would sit there looking armed while doing nothing.
                        report(
                            title: "Saved, but Switched Off",
                            body: "Show AirPods Battery is off in the jj-ice menu, which stops the "
                                + "polling this notification needs. Switch it back on to arm the rule.",
                            isWarning: true
                        )
                    }
                    return
                } catch {
                    report(title: "Not Saved", body: error.localizedDescription, isWarning: true)
                }
            case .alertSecondButtonReturn:
                let result = await readout.notifier.test(text: text, percent: readout.lastPercent)
                report(
                    title: result.ok ? "Test Sent" : "Test Failed",
                    body: result.message,
                    isWarning: !result.ok
                )
            default:
                return
            }
        }
    }

    private func present(text: String) -> (response: NSApplication.ModalResponse, text: String) {
        let size = NSSize(width: 460, height: 250)
        let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isRichText = false
        // Smart quotes and dashes would rewrite the JSON's own punctuation and break every parse.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let alert = NSAlert()
        alert.messageText = "AirPods Low Battery Notification"
        alert.informativeText = """
        A saved rule fires one request per percent from the threshold down: 30, 29, 28 and so on, \
        each sent once. Charging back above the threshold starts the count over. Clear the text to \
        turn notifications off.

        threshold  start at this percent, then every percent below (1-100)
        url        full http or https address
        method     GET, POST, PUT, PATCH, DELETE or HEAD
        query      appended to the url, escaped for you
        headers    sent as written
        body       POST, PUT and PATCH only; add a Content-Type header

        {percent} is replaced with the battery level.
        """
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Send Test")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        alert.window.initialFirstResponder = textView
        let response = alert.runModal()
        return (response, textView.string)
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
