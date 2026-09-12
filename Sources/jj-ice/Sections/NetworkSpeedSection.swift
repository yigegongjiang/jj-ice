//
//  NetworkSpeedSection.swift
//  jj-ice
//

import AppKit

/// Two stacked lines of throughput: upload on top, download below.
///
/// Display only: clicking it does nothing. The `Show Network Speed` switch that hides and restores
/// it lives in the jj-ice menu.
final class NetworkSpeedSection: StatusSection {
    override var menuToggleTitle: String? { "Show Network Speed" }
    override var refreshInterval: Duration { .seconds(1) }

    private let monitor = NetworkSpeedMonitor()

    init(defaults: UserDefaults) {
        // Both names are shipped state: the first holds this item's menu bar slot, the second the
        // user's switch. Renaming either would move the item or silently re-enable it.
        super.init(
            autosaveName: "jj-ice.NetSpeed",
            visibilityDefaultsKey: "jj-ice.showNetworkSpeed",
            defaults: defaults
        )
        item.button?.toolTip = "Physical network links - top line: upload, bottom line: download"
        render(nil)
    }

    /// The rate is derived from the measured elapsed time, so timer drift, coalescing and
    /// sleep/wake cannot distort it - only the baseline needs resetting when the loop restarts.
    override func start() {
        monitor.reset()
        render(nil)
        super.start()
    }

    override func refresh() async -> Bool {
        if let speed = monitor.sample() {
            render(speed)
        }
        // The idle placeholder stands in until the first rate exists, so there is always
        // something worth showing.
        return true
    }

    // MARK: - Drawing

    private func render(_ speed: NetworkSpeed?) {
        item.button?.image = Self.makeSpeedImage(for: speed)
    }

    /// Two stacked monospaced lines drawn into a single template image: the system re-tints
    /// template images, so the readout follows light and dark menu bars plus accessibility
    /// tints for free. Nil renders the idle placeholder shown before the first rate exists.
    private static func makeSpeedImage(for speed: NetworkSpeed?) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .kern: -0.2,  // menu bar space is scarce: tighten the tracking as far as stays legible
            .foregroundColor: NSColor.black,  // template image: only coverage matters, not the color
        ]
        let lines = [
            NSAttributedString(string: format(speed?.uploadBytesPerSecond), attributes: attributes),
            NSAttributedString(string: format(speed?.downloadBytesPerSecond), attributes: attributes),
        ]

        // Two lines must fit the menu bar, and squeezing them below the font's own line height
        // clips the glyphs (measured), so take whichever of the two limits is smaller.
        let lineHeight = min((font.ascender - font.descender).rounded(.up),
                             ((NSStatusBar.system.thickness - 2) / 2).rounded(.down))
        let width = max(1, lines.map { $0.size().width }.max()?.rounded(.up) ?? 1)
        let image = NSImage(size: NSSize(width: width, height: lineHeight * 2))
        image.lockFocus()
        lines[0].draw(in: NSRect(x: 0, y: lineHeight, width: width, height: lineHeight))
        lines[1].draw(in: NSRect(x: 0, y: 0, width: width, height: lineHeight))
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Fixed four-character field - `  0K`, ` 12K`, `999K`, `1.5M`, ` 12M`, `1.4G` - which keeps the
    /// width constant (no jitter between readings) and as narrow as the menu bar allows. No arrows
    /// and no `/s`: the top line is upload, the bottom download, which the tooltip spells out.
    /// Units are binary (1K = 1024 bytes per second).
    private static func format(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "  0K" }
        let kilobytes = bytesPerSecond / 1024
        if kilobytes < 999.5 { return String(format: "%3.0fK", kilobytes) }
        let megabytes = kilobytes / 1024
        if megabytes < 9.95 { return String(format: "%3.1fM", megabytes) }
        if megabytes < 999.5 { return String(format: "%3.0fM", megabytes) }
        return String(format: "%3.1fG", megabytes / 1024)
    }
}
