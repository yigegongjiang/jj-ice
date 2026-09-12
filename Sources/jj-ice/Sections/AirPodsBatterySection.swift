//
//  AirPodsBatterySection.swift
//  jj-ice
//

import AppKit

/// Battery percentage of the connected AirPods, shown as an icon plus `79%`.
///
/// Visibility is the switch AND live data, so the readout is there only while both hold - turning
/// the switch off also stops the polling, and with it the notification. Clicking it opens the low
/// battery notification editor, which the jj-ice menu also holds: the readout is gone exactly when
/// the AirPods are, which is a likely moment to want to change the rule.
final class AirPodsBatterySection: StatusSection {
    override var menuToggleTitle: String? { "Show AirPods Battery" }

    /// The level only moves a percent every few minutes, and connect/disconnect shows up as the
    /// reading appearing or vanishing rather than as a separate event. 15 s makes a freshly worn
    /// pair visible almost at once while costing ~60 ms of CPU per tick.
    override var refreshInterval: Duration { .seconds(15) }

    override var settingsTitle: String? { "AirPods Battery Notification..." }

    private let notifier: BatteryNotifier
    private var lastPercent: Int?
    private var isEditorOpen = false

    init(defaults: UserDefaults) {
        self.notifier = BatteryNotifier(defaults: defaults)
        // Both names are shipped state: the first holds this item's menu bar slot, the second the
        // user's switch. Renaming either would move the item or silently re-enable it.
        super.init(
            autosaveName: "jj-ice.AirPodsBattery",
            visibilityDefaultsKey: "jj-ice.showAirPodsBattery",
            defaults: defaults
        )
        // Deliberately left visible until the first sample decides: hiding the item inside `init`
        // makes AppKit drop its `NSStatusItem Preferred Position` entry (measured), which gives up
        // the seeded rightmost slot and lets the readout reappear on the far left. The cost is an
        // icon with no percentage for as long as the first read takes, about 60 ms.
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "airpods", accessibilityDescription: "AirPods battery")
        button.imagePosition = .imageLeading
        button.toolTip = """
        AirPods battery - one earbud; the pair drains together
        Click to set up the low battery notification
        """
    }

    override func refresh() async -> Bool {
        // ~60 ms of subprocess would hitch the menu bar if it ran on the main thread.
        let percent = await Task.detached { AirPodsBatteryMonitor.read() }.value
        lastPercent = percent
        item.button?.title = percent.map { "\($0)%" } ?? ""
        notifier.handle(percent: percent)
        return percent != nil
    }

    // MARK: - Notification Editor

    /// All of the AppKit for the editor lives here; `Notify/` stays free of UI.
    override func openSettings() {
        // A second dialog would edit a stale copy of the text and race the first one's save.
        guard !isEditorOpen else { return }
        isEditorOpen = true
        Task { [weak self] in
            await self?.runEditor()
            self?.isEditorOpen = false
        }
    }

    /// A loop rather than a single dialog: an invalid rule or a test result reports back and returns
    /// the user to their text, instead of throwing the edit away.
    private func runEditor() async {
        var text = notifier.editorText
        while true {
            let outcome = presentEditor(text: text)
            text = outcome.text
            switch outcome.response {
            case .alertFirstButtonReturn:
                do {
                    try notifier.save(text)
                    if !isEnabled {
                        // The switch stops the polling that feeds the notifier, so a rule saved now
                        // would sit there looking armed while doing nothing.
                        present(
                            title: "Saved, but Switched Off",
                            body: "Show AirPods Battery is off in the jj-ice menu, which stops the "
                                + "polling this notification needs. Switch it back on to arm the rule.",
                            isWarning: true
                        )
                    }
                    return
                } catch {
                    present(title: "Not Saved", body: error.localizedDescription, isWarning: true)
                }
            case .alertSecondButtonReturn:
                let result = await notifier.test(text: text, percent: lastPercent)
                present(
                    title: result.ok ? "Test Sent" : "Test Failed",
                    body: result.message,
                    isWarning: !result.ok
                )
            default:
                return
            }
        }
    }

    private func presentEditor(text: String) -> (response: NSApplication.ModalResponse, text: String) {
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

    private func present(title: String, body: String, isWarning: Bool) {
        let alert = NSAlert()
        alert.alertStyle = isWarning ? .warning : .informational
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
