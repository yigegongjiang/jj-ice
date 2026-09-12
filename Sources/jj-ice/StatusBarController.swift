//
//  StatusBarController.swift
//  jj-ice
//

import AppKit
import OSLog
import ServiceManagement

/// Classic divider + toggle menu bar item layout, implemented without private APIs.
/// Left to right: `[hideable items] [divider] [toggle] [sections] [system items]`.
///
/// On macOS 27 the divider is gone and the layout is `[toggle] [sections] [system items]`,
/// because the OS no longer allows anything to be pushed off screen - see `supportsCollapse`.
///
/// Arranging and the shared menu live here; each readout lives in its own `StatusSection`
/// subclass (see `Sections/StatusSection.swift` for the layering).
@MainActor
final class StatusBarController {
    /// Nil where the OS no longer lets a widened item push its neighbours off screen; see
    /// `supportsCollapse`. Nil also means "this build has no divider" everywhere below.
    private let separatorItem: NSStatusItem?
    private let toggleItem: NSStatusItem
    private let sections: [StatusSection]

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "jj-ice", category: "StatusBar")

    private static let collapsedDefaultsKey = "jj-ice.isCollapsed"
    private static let didApplyDefaultLaunchAtLoginKey = "jj-ice.didApplyDefaultLaunchAtLogin"
    private static let repositoryURL = URL(string: "https://github.com/yigegongjiang/jj-ice")!

    /// macOS 27 rebuilt the menu bar as a single window and clamps status item layout, which
    /// kills the widen-the-divider trick this app collapses with. Measured on 27.0 (26A428):
    /// a widened item stops moving left at a positive x (~130pt on a 1440pt-wide screen, never
    /// negative), its width caps at 5000pt, and past roughly 400pt of length the neighbours it
    /// should have pushed away reflow back to its right instead. No length hides anything.
    /// Every menu bar manager that still hides items on 27 drives private SkyLight/XPC paths
    /// Apple can revoke in any build, so this app drops the feature there rather than take on
    /// a mechanism that rots. The readouts are unaffected and stay.
    private static let supportsCollapse: Bool = {
        if #available(macOS 27.0, *) { return false }
        return true
    }()

    private var isCollapsed: Bool {
        didSet {
            guard isCollapsed != oldValue else { return }
            defaults.set(isCollapsed, forKey: Self.collapsedDefaultsKey)
            applyCollapsedState()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isCollapsed = defaults.bool(forKey: Self.collapsedDefaultsKey)

        // Without a saved position, newer status items appear to the left, so create right to
        // left: sections, toggle, divider. Every section must end up right of the divider,
        // otherwise collapsing would hide the very thing the user wants to watch - each one
        // seeds its own slot for that (see `StatusSection`). Within this list, earlier means
        // further right on a first launch; afterwards AppKit owns the order.
        self.sections = [
            NetworkSpeedSection(defaults: defaults),
            AirPodsBatterySection(defaults: defaults),
        ]
        let statusBar = NSStatusBar.system
        self.toggleItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        // Never created rather than created and hidden: hiding an item makes AppKit discard its
        // saved slot for good (see `StatusSection.setVisible`), which would cost the user their
        // divider position if a later macOS brought collapsing back.
        self.separatorItem = Self.supportsCollapse
            ? statusBar.statusItem(withLength: NSStatusItem.variableLength)
            : nil

        configureSeparatorItem()
        configureToggleItem()
        configureSections()
        applyCollapsedState()
        enableLaunchAtLoginByDefaultIfNeeded()
    }

    // MARK: - Setup

    private func configureSeparatorItem() {
        guard let separatorItem else { return }
        separatorItem.autosaveName = "jj-ice.Separator"
        guard let button = separatorItem.button else { return }
        button.image = makeSeparatorImage()
        button.toolTip = "jj-ice divider - items on the left are hidden when collapsed"
    }

    private func configureToggleItem() {
        toggleItem.autosaveName = "jj-ice.Toggle"
        guard let button = toggleItem.button else { return }
        button.target = self
        button.action = #selector(handleToggleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// A readout answers a click only when it has settings to open; the rest stay inert. The arrow
    /// keeps the shared menu to itself - left click collapses, right click opens the menu that holds
    /// every section's switch and settings entry.
    private func configureSections() {
        for section in sections {
            if section.settingsTitle != nil, let button = section.item.button {
                button.target = self
                button.action = #selector(handleSectionClick)
            }
            section.activate()
        }
    }

    /// Draw a centered divider line. Template images adapt to light and dark menu bars.
    private func makeSeparatorImage() -> NSImage {
        let size = NSSize(width: 7, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        let lineWidth: CGFloat = 1
        NSRect(x: (size.width - lineWidth) / 2, y: 3, width: lineWidth, height: size.height - 6).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Collapse State

    /// Use the widest display plus margin so collapsed items are pushed off screen.
    private var expandedLength: CGFloat {
        let widestScreen = NSScreen.screens.map(\.frame.width).max() ?? 0
        return max(10_000, widestScreen + 200)
    }

    private func applyCollapsedState() {
        guard let separatorItem else {
            // Nothing collapses here, so an arrow would promise something the item cannot do.
            let description = "jj-ice menu - collapsing is unavailable on macOS 27"
            toggleItem.button?.image = NSImage(systemSymbolName: "ellipsis.circle",
                                               accessibilityDescription: description)
            toggleItem.button?.toolTip = description
            return
        }

        if isCollapsed {
            // Widen the divider to push left-side items away, then hide the divider itself.
            separatorItem.length = expandedLength
            separatorItem.button?.alphaValue = 0
        } else {
            separatorItem.length = NSStatusItem.variableLength
            separatorItem.button?.alphaValue = 1
        }

        // Arrow direction describes the next action.
        let symbolName = isCollapsed ? "chevron.right" : "chevron.left"
        let description = isCollapsed ? "Show hidden menu bar items" : "Hide menu bar items on the left"
        toggleItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        toggleItem.button?.toolTip = description
    }

    // MARK: - Interaction

    @objc private func handleSectionClick(_ sender: NSButton) {
        sections.first { $0.item.button === sender }?.openSettings()
    }

    @objc private func handleToggleClick() {
        // Without a divider every click opens the menu: it is the only route to the section
        // switches, Launch at Login and Quit, and the AirPods readout that also carries a menu
        // entry disappears whenever no headphones are connected.
        guard separatorItem != nil else {
            presentMenu()
            return
        }

        // Right click and Control-click open the menu; other clicks toggle collapse.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            presentMenu()
        } else {
            isCollapsed.toggle()
        }
    }

    /// The arrow is the only entry point to the menu, so it is also the only way back after hiding
    /// a section.
    private func presentMenu() {
        guard let button = toggleItem.button else { return }
        toggleItem.menu = makeMenu()
        defer { toggleItem.menu = nil }
        button.performClick(nil)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        // A user who upgraded to macOS 27 finds the arrow inert; say why where they will look.
        if separatorItem == nil {
            menu.addItem(NSMenuItem(title: "Collapsing Unavailable on macOS 27", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
        }

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
        let collapsingLine = separatorItem == nil
            ? "macOS 27 rebuilt the menu bar so that no app can push items off screen, so collapsing is unavailable here and the icon only opens this menu. The readouts below still work. Use the system's own overflow button, which appears once the icons no longer fit."
            : "Click the arrow to collapse or expand, right-click it for the menu; hold Command and drag items to the left side of the divider to hide them."
        let alert = NSAlert()
        alert.messageText = "jj-ice \(version)"
        alert.informativeText = """
        Menu bar item organizer with a network speed and AirPods battery readout.
        \(collapsingLine)
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
