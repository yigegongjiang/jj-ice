//
//  ReadoutImage.swift
//  jj-ice
//

import AppKit

/// Draws the whole menu bar readout into one template image: `[two speed lines][gap][battery]`.
///
/// One image rather than an image plus a button title, because the two blocks need different fonts
/// and baselines - and because the system re-tints template images, so the readout follows light
/// and dark menu bars plus accessibility tints for free.
enum ReadoutImage {
    /// Monospaced in both blocks so a changing reading never changes the width.
    private static let speedFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
    private static let batteryFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    /// Enough to read as two separate numbers, not enough to waste menu bar width.
    private static let gap: CGFloat = 5

    /// `%` inks past the advance width `size()` reports, so its column is drawn left-aligned with
    /// a couple of points of slack on the right; right-aligning it clips the glyph no matter how
    /// wide the box is, because the text just moves with the right edge (measured).
    private static let batteryInkAllowance: CGFloat = 2

    /// - Parameters:
    ///   - speed: latest sample, nil while no rate exists yet - draws the `  0K` placeholder.
    ///   - showsSpeed: false leaves the speed block out entirely; the user switched it off.
    ///   - percent: battery level, nil when switched off or no AirPods are connected.
    static func make(speed: NetworkSpeed?, showsSpeed: Bool, percent: Int?) -> NSImage {
        let speedLines = showsSpeed
            ? [line(format(speed?.uploadBytesPerSecond), speedFont, .right),
               line(format(speed?.downloadBytesPerSecond), speedFont, .right)]
            : []
        // Fixed four-character field - `  5%`, ` 61%`, `100%` - so the item does not twitch as the
        // level drops. The leading spaces do the right-aligning that the paragraph style cannot.
        let battery = percent.map { line(String(format: "%3d%%", $0), batteryFont, .left) }

        // With both blocks switched off there is nothing to draw, but the item has to stay on the
        // menu bar: it is the only way back to the menu, and to Quit.
        guard !speedLines.isEmpty || battery != nil else { return menuGlyph() }

        // Two speed lines must fit the menu bar, and squeezing them below the font's own line
        // height clips the glyphs (measured), so take whichever of the two limits is smaller.
        let speedLineHeight = min((speedFont.ascender - speedFont.descender).rounded(.up),
                                  ((NSStatusBar.system.thickness - 2) / 2).rounded(.down))
        let height = speedLineHeight * 2
        let speedWidth = speedLines.map { $0.size().width }.max()?.rounded(.up) ?? 0
        let batteryWidth = battery.map { $0.size().width.rounded(.up) + batteryInkAllowance } ?? 0
        let gapWidth = (speedWidth > 0 && batteryWidth > 0) ? gap : 0
        let width = max(1, speedWidth + gapWidth + batteryWidth)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        if speedLines.count == 2 {
            speedLines[0].draw(in: NSRect(x: 0, y: speedLineHeight, width: speedWidth, height: speedLineHeight))
            speedLines[1].draw(in: NSRect(x: 0, y: 0, width: speedWidth, height: speedLineHeight))
        }
        if let battery {
            // Centre the single line against the two-line block instead of sitting on its baseline.
            let batteryHeight = min((batteryFont.ascender - batteryFont.descender).rounded(.up), height)
            battery.draw(in: NSRect(x: speedWidth + gapWidth,
                                    y: ((height - batteryHeight) / 2).rounded(.down),
                                    width: batteryWidth,
                                    height: batteryHeight))
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func line(_ string: String, _ font: NSFont, _ alignment: NSTextAlignment) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        return NSAttributedString(string: string, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
            .kern: -0.2,  // menu bar space is scarce: tighten the tracking as far as stays legible
            .foregroundColor: NSColor.black,  // template image: only coverage matters, not the color
        ])
    }

    /// Stand-in for an empty readout, and a hint that the item still opens a menu.
    private static func menuGlyph() -> NSImage {
        let image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "jj-ice menu")
            ?? NSImage(size: NSSize(width: 1, height: 1))
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
