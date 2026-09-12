//
//  HotKeyShortcut.swift
//  jj-ice
//

import Carbon.HIToolbox
import Foundation

/// One global key combination, written the way the user types it: `cmd+space`, `ctrl+opt+k`.
///
/// Pure value type - it turns text into a Carbon key code plus modifier mask and back, and knows
/// nothing about AppKit, `UserDefaults` or the registration itself. Parsing and formatting round
/// trip, so what the editor shows is exactly what got stored.
nonisolated struct HotKeyShortcut: Equatable {
    /// Carbon virtual key code (`kVK_*`), what `RegisterEventHotKey` takes.
    let keyCode: UInt32

    /// Carbon modifier mask (`cmdKey` etc.), what `RegisterEventHotKey` takes.
    let carbonModifiers: UInt32

    /// Canonical name of the non-modifier key, lowercase, as it appears in `text`.
    private let keyName: String

    /// Shipped default. ⌘Space is Spotlight's out of the box, so `QuickCopyController` checks the
    /// system's own shortcut table before trusting a registration - see `systemConflict(for:)`.
    static let fallback = HotKeyShortcut(
        keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey), keyName: "space"
    )

    static var fallbackText: String { fallback.text }

    /// Modifiers first, in the order macOS prints them, then the key: `ctrl+opt+shift+cmd+space`.
    var text: String {
        var parts: [String] = []
        for (mask, name) in Self.modifierOrder where carbonModifiers & mask != 0 {
            parts.append(name)
        }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    /// `⌃⌥⇧⌘Space`, for the one place a person reads rather than edits it.
    var symbols: String {
        var out = ""
        for (mask, symbol) in Self.modifierSymbols where carbonModifiers & mask != 0 {
            out += symbol
        }
        return out + (Self.displayNames[keyName] ?? keyName.uppercased())
    }

    /// Throws `HotKeyShortcutError` with a message meant to be shown to the user as is.
    static func parse(_ text: String) throws -> HotKeyShortcut {
        let tokens = text.lowercased()
            .split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            throw HotKeyShortcutError("Type a shortcut, for example \(fallbackText).")
        }

        var modifiers: UInt32 = 0
        var key: (name: String, code: UInt32)?
        for token in tokens {
            if let mask = modifierAliases[token] {
                guard modifiers & mask == 0 else {
                    throw HotKeyShortcutError("\"\(token)\" is listed twice.")
                }
                modifiers |= mask
                continue
            }
            guard let code = keyCodes[token] else {
                throw HotKeyShortcutError(
                    "\"\(token)\" is not a key jj-ice knows. Use a letter, a digit, f1-f20, or one "
                        + "of: \(namedKeys.joined(separator: ", "))."
                )
            }
            guard key == nil else {
                throw HotKeyShortcutError("A shortcut takes one key, not two (\"\(key!.name)\" and \"\(token)\").")
            }
            key = (token, code)
        }

        guard let key else {
            throw HotKeyShortcutError("A shortcut needs a key after the modifiers, for example \(fallbackText).")
        }
        // A bare key would be swallowed app-wide the moment it is registered: every press of it,
        // in every app, would open the jj-ice window instead of typing.
        guard modifiers != 0 else {
            throw HotKeyShortcutError("A global shortcut needs at least one of cmd, ctrl, opt or shift.")
        }
        return HotKeyShortcut(keyCode: key.code, carbonModifiers: modifiers, keyName: key.name)
    }

    // MARK: - Tables

    private static let modifierOrder: [(UInt32, String)] = [
        (UInt32(controlKey), "ctrl"), (UInt32(optionKey), "opt"),
        (UInt32(shiftKey), "shift"), (UInt32(cmdKey), "cmd"),
    ]

    private static let modifierSymbols: [(UInt32, String)] = [
        (UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"),
        (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘"),
    ]

    private static let modifierAliases: [String: UInt32] = [
        "cmd": UInt32(cmdKey), "command": UInt32(cmdKey), "⌘": UInt32(cmdKey),
        "ctrl": UInt32(controlKey), "control": UInt32(controlKey), "⌃": UInt32(controlKey),
        "opt": UInt32(optionKey), "option": UInt32(optionKey), "alt": UInt32(optionKey),
        "⌥": UInt32(optionKey),
        "shift": UInt32(shiftKey), "⇧": UInt32(shiftKey),
    ]

    /// Listed in the editor's help text, so keep it in step with `keyCodes`.
    private static let namedKeys = [
        "space", "return", "tab", "escape", "delete", "up", "down", "left", "right",
        "home", "end", "pageup", "pagedown",
    ]

    /// ANSI layout positions. `RegisterEventHotKey` matches on position, not on the character the
    /// user's layout produces, so this table is the layout jj-ice assumes.
    private static let keyCodes: [String: UInt32] = {
        var map: [String: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
            "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
            "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
            "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
            "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
            "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
            "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
            "-": UInt32(kVK_ANSI_Minus), "=": UInt32(kVK_ANSI_Equal),
            "[": UInt32(kVK_ANSI_LeftBracket), "]": UInt32(kVK_ANSI_RightBracket),
            "\\": UInt32(kVK_ANSI_Backslash), ";": UInt32(kVK_ANSI_Semicolon),
            "'": UInt32(kVK_ANSI_Quote), ",": UInt32(kVK_ANSI_Comma),
            ".": UInt32(kVK_ANSI_Period), "/": UInt32(kVK_ANSI_Slash),
            "`": UInt32(kVK_ANSI_Grave),
            "space": UInt32(kVK_Space), "return": UInt32(kVK_Return), "enter": UInt32(kVK_Return),
            "tab": UInt32(kVK_Tab), "escape": UInt32(kVK_Escape), "esc": UInt32(kVK_Escape),
            "delete": UInt32(kVK_Delete), "backspace": UInt32(kVK_Delete),
            "forwarddelete": UInt32(kVK_ForwardDelete), "help": UInt32(kVK_Help),
            "home": UInt32(kVK_Home), "end": UInt32(kVK_End),
            "pageup": UInt32(kVK_PageUp), "pagedown": UInt32(kVK_PageDown),
            "up": UInt32(kVK_UpArrow), "down": UInt32(kVK_DownArrow),
            "left": UInt32(kVK_LeftArrow), "right": UInt32(kVK_RightArrow),
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
            kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() {
            map["f\(index + 1)"] = UInt32(code)
        }
        return map
    }()

    private static let displayNames: [String: String] = [
        "space": "Space", "return": "Return", "enter": "Return", "tab": "Tab",
        "escape": "Esc", "esc": "Esc", "delete": "Delete", "backspace": "Delete",
        "forwarddelete": "Fwd Delete", "help": "Help", "home": "Home", "end": "End",
        "pageup": "Page Up", "pagedown": "Page Down",
        "up": "↑", "down": "↓", "left": "←", "right": "→",
    ]
}

/// Carries a message written for the dialog, so the editor can show it without translating.
nonisolated struct HotKeyShortcutError: LocalizedError {
    private let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
