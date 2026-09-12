//
//  QuickCopyPanel.swift
//  jj-ice
//

import AppKit

/// The floating text window the global shortcut opens: type, press Return, the text is on the
/// clipboard and the window is gone.
///
/// Borderless `NSPanel` rather than a titled window: there is nothing to put in a title bar, and a
/// title bar's drag region would steal clicks meant to place the caret. `canBecomeKey` has to be
/// overridden because a borderless window refuses key status by default, and without key status it
/// receives no typing at all.
@MainActor
final class QuickCopyPanel: NSObject, NSTextViewDelegate, NSWindowDelegate {
    private static let size = NSSize(width: 560, height: 160)

    private let panel: KeyablePanel
    private let textView: NSTextView

    /// The app that was frontmost when the panel opened, so dismissing puts the user back exactly
    /// where they were - the whole point is to press ⌘V there next.
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel.isVisible }

    override init() {
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        textView = NSTextView(frame: NSRect(origin: .zero, size: Self.size))
        super.init()

        configurePanel()
        panel.contentView = makeContentView()
        panel.delegate = self
        textView.delegate = self
    }

    // MARK: - Showing

    func toggle() {
        isVisible ? dismiss() : show()
    }

    func show() {
        // A type-and-go box, not a draft buffer: leftovers from last time would be copied by a
        // reflexive Return.
        textView.string = ""
        centerOnScreenWithMouse()

        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    /// The screen the pointer is on, not the one that happens to hold the key window.
    private func centerOnScreenWithMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.frame
        panel.setFrameOrigin(
            NSPoint(x: frame.midX - Self.size.width / 2, y: frame.midY - Self.size.height / 2)
        )
    }

    /// `restoringFocus` is false when the panel lost key status on its own: the user clicked
    /// somewhere, and pulling focus back to whatever was frontmost before would fight them.
    private func dismiss(restoringFocus: Bool = true) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        // Handing activation back by name beats `NSApp.hide`: an accessory app with no other
        // window has nothing to hide, and the user needs the *previous* app frontmost, not
        // whichever one macOS picks next. Measured on macOS 27: a `.nonactivatingPanel` never takes
        // frontmost away in the first place, so this is usually a no-op - it is the safety net for
        // the case where activation did go through.
        if restoringFocus {
            if let previousApp {
                previousApp.activate()
            } else {
                NSApp.hide(nil)
            }
        }
        previousApp = nil
    }

    /// Click anywhere else and the box goes away, Spotlight style. `hidesOnDeactivate` cannot do
    /// this job here: the app never becomes frontmost, so it never deactivates either.
    func windowDidResignKey(_ notification: Notification) {
        dismiss(restoringFocus: false)
    }

    /// Clipboard first, window second: the target app's ⌘V must never race a stale clipboard.
    private func commit() {
        let text = textView.string
        guard !text.isEmpty else { return dismiss() }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        dismiss()
    }

    // MARK: - Keys

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // Shift+Return arrives here too, only with the flag set; it is the way to type a
            // second line in a box whose plain Return means "done".
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            guard flags.contains(.shift) || flags.contains(.option) else {
                commit()
                return true
            }
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        // Esc reaches a text view as `complete:` (the completion binding) as often as
        // `cancelOperation:`, so both have to mean "go away".
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }

    // MARK: - Building

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .floating
        // Without these the panel lands on the Space it was built on: trigger the shortcut from a
        // full screen app and nothing appears to happen.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
    }

    private func makeContentView() -> NSView {
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        let inset: CGFloat = 14
        let hintHeight: CGFloat = 16
        let scrollFrame = NSRect(
            x: inset,
            y: inset + hintHeight + 8,
            width: Self.size.width - inset * 2,
            height: Self.size.height - (inset * 2 + hintHeight + 8)
        )

        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        textView.frame = NSRect(origin: .zero, size: scrollFrame.size)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollFrame.width, height: CGFloat.greatestFiniteMagnitude
        )
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.font = .systemFont(ofSize: 15)
        textView.isRichText = false
        textView.allowsUndo = true
        // The text goes straight to the clipboard and usually straight into code or a prompt:
        // curly quotes and en dashes substituted on the way in would be pasted out corrupted.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        scrollView.documentView = textView

        let hint = NSTextField(
            labelWithString: "Return copies and closes   ·   Shift+Return adds a line   ·   Esc cancels"
        )
        hint.frame = NSRect(x: inset, y: inset, width: Self.size.width - inset * 2, height: hintHeight)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.autoresizingMask = [.width]

        background.addSubview(scrollView)
        background.addSubview(hint)
        return background
    }
}

/// A borderless window returns false from `canBecomeKey`, which would leave the text view unable
/// to receive a single keystroke.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
