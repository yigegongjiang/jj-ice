//
//  QuickCopyController.swift
//  jj-ice
//

import AppKit
import Carbon.HIToolbox
import OSLog

/// Quick Copy: a global shortcut opens a text box on the screen the pointer is on, Return puts what
/// was typed on the clipboard and gives the previous app its focus back.
///
/// Owns the switch, the stored shortcut and the Carbon registration; `QuickCopyPanel` owns the
/// window and `QuickCopyShortcutEditor` the dialog.
@MainActor
final class QuickCopyController {
    /// Frozen once shipped: renaming either key would silently re-enable the feature for someone
    /// who switched it off, or drop the shortcut they chose.
    static let enabledKey = "jj-ice.enableQuickCopy"
    static let shortcutKey = "jj-ice.quickCopyShortcut"

    /// What the editor prints about the shortcut's real state - registered is not the same as
    /// reachable, see `systemConflict(for:)`.
    struct Status {
        let message: String
        let isWarning: Bool
    }

    private let defaults: UserDefaults
    private let panel = QuickCopyPanel()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "jj-ice", category: "QuickCopy")

    private var hotKey: GlobalHotKey?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Self.enabledKey: true,
            Self.shortcutKey: HotKeyShortcut.fallbackText,
        ])
    }

    /// Register the shortcut if the switch is on. Call once at launch.
    func start() {
        applyHotKey()
    }

    // MARK: - Switch

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: Self.enabledKey)
            applyHotKey()
        }
    }

    // MARK: - Shortcut

    /// Falls back to ⌘Space if the stored text is missing or was hand-edited into something
    /// unparseable, so the feature can never end up with no shortcut at all.
    var shortcut: HotKeyShortcut {
        let text = defaults.string(forKey: Self.shortcutKey) ?? HotKeyShortcut.fallbackText
        return (try? HotKeyShortcut.parse(text)) ?? .fallback
    }

    /// What the editor opens with, always in canonical form.
    var shortcutText: String { shortcut.text }

    /// Throws `HotKeyShortcutError` when the text is not a shortcut. A saved shortcut is applied
    /// immediately; whether it is actually reachable is then in `status`.
    func save(_ text: String) throws {
        let parsed = try HotKeyShortcut.parse(text)
        defaults.set(parsed.text, forKey: Self.shortcutKey)
        applyHotKey()
    }

    var status: Status {
        let shortcut = self.shortcut
        if !isEnabled {
            return Status(
                message: "Quick Copy is switched off in the jj-ice menu, so \(shortcut.symbols) does nothing.",
                isWarning: true
            )
        }
        if hotKey == nil {
            return Status(
                message: "\(shortcut.symbols) is already taken by another app. Pick a different combination.",
                isWarning: true
            )
        }
        if let owner = Self.systemConflict(for: shortcut) {
            return Status(
                message: "macOS gives \(shortcut.symbols) to \(owner), and takes it first - jj-ice never sees "
                    + "the key. Turn that off in System Settings > Keyboard > Keyboard Shortcuts, or pick a "
                    + "different combination.",
                isWarning: true
            )
        }
        // Deliberately not "it works": an app that grabs the key through a `CGEventTap` (launchers
        // do) swallows it before Carbon dispatches, and nothing jj-ice can read shows that.
        return Status(
            message: "\(shortcut.symbols) is registered. If pressing it does nothing, another app is "
                + "taking the key first - a launcher holding it is invisible to jj-ice, so the fix is to "
                + "free it there or pick a different combination.",
            isWarning: false
        )
    }

    // MARK: - Registration

    private func applyHotKey() {
        hotKey?.unregister()
        hotKey = nil
        guard isEnabled else { return }

        let shortcut = self.shortcut
        hotKey = GlobalHotKey(shortcut: shortcut) { [weak self] in
            self?.panel.toggle()
        }
        if hotKey == nil {
            logger.error("Shortcut \(shortcut.text, privacy: .public) is held by another app")
        } else if let owner = Self.systemConflict(for: shortcut) {
            logger.warning("Shortcut \(shortcut.text, privacy: .public) is owned by macOS (\(owner, privacy: .public))")
        }
    }

    // MARK: - System shortcut table

    /// The handful of system shortcuts worth naming; everything else is reported generically.
    private static let systemShortcutNames: [String: String] = [
        "60": "the previous input source", "61": "the next input source",
        "64": "Spotlight", "65": "the Finder search window",
    ]

    /// Cocoa modifier bits, which is how the system's table stores them.
    private static let cocoaModifiers: [(UInt32, UInt32)] = [
        (1 << 17, UInt32(shiftKey)), (1 << 18, UInt32(controlKey)),
        (1 << 19, UInt32(optionKey)), (1 << 20, UInt32(cmdKey)),
    ]

    /// Which macOS shortcut owns this combination, if any.
    ///
    /// Measured on macOS 27: `RegisterEventHotKey` returns `noErr` for a combination the system has
    /// already claimed (⌘Space is Spotlight's by default) and the key simply never arrives. Reading
    /// the system's own table is the only way to tell that apart from a working registration.
    /// Readable from a plain unsandboxed process - also measured.
    private static func systemConflict(for shortcut: HotKeyShortcut) -> String? {
        guard let table = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")
        else { return nil }

        for (identifier, raw) in table {
            guard let entry = raw as? [String: Any],
                  entry["enabled"] as? Bool == true,
                  let value = entry["value"] as? [String: Any],
                  // [character, key code, Cocoa modifier mask]
                  let parameters = value["parameters"] as? [Any], parameters.count >= 3,
                  let keyCode = (parameters[1] as? NSNumber)?.uint32Value, keyCode == shortcut.keyCode,
                  let modifiers = (parameters[2] as? NSNumber)?.uint32Value,
                  carbonModifiers(from: modifiers) == shortcut.carbonModifiers
            else { continue }
            return systemShortcutNames[identifier] ?? "a macOS system shortcut"
        }
        return nil
    }

    private static func carbonModifiers(from cocoa: UInt32) -> UInt32 {
        cocoaModifiers.reduce(into: UInt32(0)) { result, pair in
            if cocoa & pair.0 != 0 { result |= pair.1 }
        }
    }
}
