//
//  StatusBarController.swift
//  jj-ice
//

import AppKit
import OSLog
import ServiceManagement

/// Menu bar layout, left to right: `[menu] [sections] [system items]`.
///
/// Arranging and the shared menu live here; each readout lives in its own `StatusSection`
/// subclass (see `Sections/StatusSection.swift` for the layering).
@MainActor
final class StatusBarController {
    private let menuItem: NSStatusItem
    private let sections: [StatusSection]

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "jj-ice", category: "StatusBar")

    private static let menuAutosaveName = "jj-ice.Menu"
    private static let didApplyDefaultLaunchAtLoginKey = "jj-ice.didApplyDefaultLaunchAtLogin"
    private static let repositoryURL = URL(string: "https://github.com/yigegongjiang/jj-ice")!

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // AppKit drops an item with no saved slot on the far left, so every item seeds its own
        // rightmost slot (see `StatusSection`). Within this list, earlier means further right on a
        // first launch; afterwards AppKit owns the order.
        self.sections = [
            NetworkSpeedSection(defaults: defaults),
            AirPodsBatterySection(defaults: defaults),
        ]
        StatusSection.seedRightmostPosition(Self.menuAutosaveName, defaults)
        self.menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureMenuItem()
        configureSections()
        enableLaunchAtLoginByDefaultIfNeeded()
    }

    // MARK: - Setup

    private func configureMenuItem() {
        menuItem.autosaveName = Self.menuAutosaveName
        guard let button = menuItem.button else { return }
        let description = "jj-ice menu"
        button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: description)
        button.toolTip = description
        button.target = self
        button.action = #selector(handleMenuItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// A readout answers a click only when it has settings to open; the rest stay inert. Every
    /// section's switch and settings entry lives in the shared menu instead.
    private func configureSections() {
        for section in sections {
            if section.settingsTitle != nil, let button = section.item.button {
                button.target = self
                button.action = #selector(handleSectionClick)
            }
            section.activate()
        }
    }

    // MARK: - Interaction

    @objc private func handleSectionClick(_ sender: NSButton) {
        sections.first { $0.item.button === sender }?.openSettings()
    }

    @objc private func handleMenuItemClick() {
        presentMenu()
    }

    /// The menu item is the only entry point to the menu, so it is also the only way back after
    /// hiding a section.
    private func presentMenu() {
        guard let button = menuItem.button else { return }
        menuItem.menu = makeMenu()
        defer { menuItem.menu = nil }
        button.performClick(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        for section in sections {
            guard let title = section.menuToggleTitle else { continue }
            let item = makeMenuItem(title: title, action: #selector(menuToggleSection))
            item.state = section.isEnabled ? .on : .off
            item.representedObject = section
            menu.addItem(item)
        }

        for section in sections {
            guard let title = section.settingsTitle else { continue }
            let item = makeMenuItem(title: title, action: #selector(menuOpenSectionSettings))
            item.representedObject = section
            menu.addItem(item)
        }

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

    @objc private func menuToggleSection(_ sender: NSMenuItem) {
        guard let section = sender.representedObject as? StatusSection else { return }
        section.isEnabled.toggle()
    }

    @objc private func menuOpenSectionSettings(_ sender: NSMenuItem) {
        guard let section = sender.representedObject as? StatusSection else { return }
        section.openSettings()
    }

    @objc private func menuOpenHelp() {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    @objc private func menuShowAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let alert = NSAlert()
        alert.messageText = "jj-ice \(version)"
        alert.informativeText = """
        Menu bar readouts: network speed and AirPods battery.
        Click the jj-ice icon for the menu: each readout's switch, its settings, and Launch at Login.
        The speed readout is display only and sums the physical links, so a VPN going up or down does not change the numbers.
        Click the AirPods readout to set up a low battery notification: a percentage and an HTTP request, written as JSON.
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
