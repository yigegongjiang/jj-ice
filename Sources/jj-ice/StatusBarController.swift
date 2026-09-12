//
//  StatusBarController.swift
//  jj-ice
//

import AppKit
import OSLog
import ServiceManagement

/// The app's single menu bar item: the readout draws it, a click opens the menu.
///
/// One item on purpose - a menu bar is scarce space, and the two readouts plus the menu fit in one
/// slot (see `Readout/` for the layering).
@MainActor
final class StatusBarController {
    private let item: NSStatusItem
    private let readout: MenuBarReadout
    private let notifyEditor: AirPodsNotifyEditor

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "jj-ice", category: "StatusBar")

    private static let autosaveName = "jj-ice.Readout"
    private static let didApplyDefaultLaunchAtLoginKey = "jj-ice.didApplyDefaultLaunchAtLogin"
    private static let repositoryURL = URL(string: "https://github.com/yigegongjiang/jj-ice")!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.readout = MenuBarReadout(defaults: defaults)
        self.notifyEditor = AirPodsNotifyEditor(readout: readout)

        Self.seedRightmostPosition(defaults)
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName

        configureButton()
        readout.onRender = { [weak self] image, tooltip in
            self?.item.button?.image = image
            self?.item.button?.toolTip = tooltip
        }
        readout.start()
        enableLaunchAtLoginByDefaultIfNeeded()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// AppKit drops an item with no saved slot on the far left, away from the system's own. Seeding
    /// 0 asks for the rightmost slot available to a third-party item; AppKit clamps it into the
    /// usable range and owns the value from then on, so this is a no-op after the first launch.
    private static func seedRightmostPosition(_ defaults: UserDefaults) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(0, forKey: key)
    }

    // MARK: - Interaction

    /// Left and right both open the menu: it is the only route to the switches, the notification
    /// editor, Launch at Login and Quit.
    @objc private func handleClick() {
        guard let button = item.button else { return }
        item.menu = makeMenu()
        defer { item.menu = nil }
        button.performClick(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let speedItem = makeMenuItem(title: "Show Network Speed", action: #selector(menuToggleSpeed))
        speedItem.state = readout.showsSpeed ? .on : .off
        menu.addItem(speedItem)

        let batteryItem = makeMenuItem(title: "Show AirPods Battery", action: #selector(menuToggleBattery))
        batteryItem.state = readout.showsBattery ? .on : .off
        menu.addItem(batteryItem)

        menu.addItem(makeMenuItem(title: "AirPods Battery Notification...",
                                  action: #selector(menuOpenNotifyEditor)))

        let launchItem = makeMenuItem(title: "Launch at Login", action: #selector(menuToggleLaunchAtLogin))
        launchItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        menu.addItem(makeMenuItem(title: "Help", action: #selector(menuOpenHelp)))
        menu.addItem(makeMenuItem(title: "About", action: #selector(menuShowAbout)))
        menu.addItem(makeMenuItem(title: "Quit jj-ice", action: #selector(menuQuit), keyEquivalent: "q"))

        return menu
    }

    private func makeMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func menuToggleSpeed() {
        readout.showsSpeed.toggle()
    }

    @objc private func menuToggleBattery() {
        readout.showsBattery.toggle()
    }

    @objc private func menuOpenNotifyEditor() {
        notifyEditor.open()
    }

    @objc private func menuOpenHelp() {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    @objc private func menuShowAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let alert = NSAlert()
        alert.messageText = "jj-ice \(version)"
        alert.informativeText = """
        One menu bar item: network speed, with the AirPods battery level to its right.
        Click it for the menu: both switches, the battery notification and Launch at Login.
        The speed readout sums the physical links, so a VPN going up or down does not change the numbers.
        The AirPods percentage is one earbud's, and disappears when nothing is connected.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enable Launch at Login once on first launch, then respect the user's menu choice.
    private func enableLaunchAtLoginByDefaultIfNeeded() {
        guard !defaults.bool(forKey: Self.didApplyDefaultLaunchAtLoginKey) else { return }

        guard SMAppService.mainApp.status != .enabled else {
            defaults.set(true, forKey: Self.didApplyDefaultLaunchAtLoginKey)
            return
        }
        do {
            try SMAppService.mainApp.register()
            // Record the applied default only on success: a failed registration (an unsigned
            // bundle used to be one) must be retried next launch, not silently made permanent.
            defaults.set(true, forKey: Self.didApplyDefaultLaunchAtLoginKey)
        } catch {
            logger.error("Default Launch at Login registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func menuToggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("Launch at Login toggle failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unable to Change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            alert.runModal()
        }
    }
}
