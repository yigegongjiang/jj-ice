//
//  GlobalHotKey.swift
//  jj-ice
//

import Carbon.HIToolbox
import Foundation

/// A system-wide key combination, registered through the Carbon Event Manager.
///
/// `RegisterEventHotKey` is the only public API that delivers a key press to a background app
/// *and* swallows it: `NSEvent.addGlobalMonitorForEvents` and `CGEventTap` both need the
/// Accessibility permission, and the monitor cannot stop the key reaching the frontmost app.
/// Carbon needs neither permission nor an entitlement, which is why jj-ice stays install-and-run.
///
/// Measured on macOS 27: the handler must go on `GetApplicationEventTarget()` while the hot key
/// goes on `GetEventDispatcherTarget()`; that pairing delivers, and the C callback is reached on
/// the main run loop.
@MainActor
final class GlobalHotKey {
    /// Owner tag Carbon hands back with each press, so a stray registration from another framework
    /// in this process could never be mistaken for ours. 'jjic'.
    private static let signature = OSType(0x6a6a_6963)

    /// The C callback cannot capture context, so it can only look the press up by id.
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?

    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// Returns nil when Carbon refuses the combination - another process holds it
    /// (`eventHotKeyExistsErr`, -9878). A macOS system shortcut is *not* refused here; see
    /// `QuickCopyController.systemConflict(for:)`.
    init?(shortcut: HotKeyShortcut, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()

        id = Self.nextID
        Self.nextID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return nil }

        self.ref = ref
        Self.actions[id] = action
    }

    /// Must be called before dropping the object: Carbon holds the registration process-wide, so a
    /// forgotten one keeps eating the key for as long as jj-ice runs.
    func unregister() {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        Self.actions.removeValue(forKey: id)
    }

    // MARK: - Dispatch

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &handler)
    }

    fileprivate static func fire(id: UInt32) {
        actions[id]?()
    }
}

/// `nonisolated` on purpose: the package defaults to `MainActor` isolation, and an isolated
/// function cannot be converted to a C function pointer. Carbon calls this on the main run loop,
/// so hopping back with `assumeIsolated` is a statement of fact rather than a hop.
private nonisolated func hotKeyEventHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    MainActor.assumeIsolated { GlobalHotKey.fire(id: hotKeyID.id) }
    return noErr
}
