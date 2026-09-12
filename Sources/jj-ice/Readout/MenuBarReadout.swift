//
//  MenuBarReadout.swift
//  jj-ice
//

import AppKit

/// Everything the single menu bar item shows: the network speed block, the AirPods battery block,
/// and the two refresh loops that feed them.
///
/// The app is three layers:
/// - `Monitors/` reads a hardware value and knows nothing about AppKit.
/// - `Readout/` owns the loops, the drawing and the dialogs.
/// - `StatusBarController` owns the one `NSStatusItem` and the menu.
///
/// Each block has its own cadence and its own switch, so they start and stop independently; the
/// item itself is always on the menu bar, which is what keeps the menu reachable.
@MainActor
final class MenuBarReadout {
    /// Frozen once shipped: renaming either key would silently re-enable a block the user switched
    /// off.
    static let showSpeedKey = "jj-ice.showNetworkSpeed"
    static let showBatteryKey = "jj-ice.showAirPodsBattery"

    /// Handed the freshly drawn image and the tooltip that matches what it shows.
    var onRender: ((NSImage, String) -> Void)?

    /// The notification editor reads the rule and the last level through here.
    let notifier: BatteryNotifier
    private(set) var lastPercent: Int?

    private let defaults: UserDefaults
    private let speedMonitor = NetworkSpeedMonitor()
    private var speed: NetworkSpeed?
    private var speedTask: Task<Void, Never>?
    private var batteryTask: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.notifier = BatteryNotifier(defaults: defaults)
        defaults.register(defaults: [Self.showSpeedKey: true, Self.showBatteryKey: true])
    }

    // MARK: - Switches

    var showsSpeed: Bool {
        get { defaults.bool(forKey: Self.showSpeedKey) }
        set {
            guard newValue != showsSpeed else { return }
            defaults.set(newValue, forKey: Self.showSpeedKey)
            applySpeed()
        }
    }

    /// Switching this off also stops the polling, and with it the low battery notification - which
    /// is why saving a rule while it is off warns the user.
    var showsBattery: Bool {
        get { defaults.bool(forKey: Self.showBatteryKey) }
        set {
            guard newValue != showsBattery else { return }
            defaults.set(newValue, forKey: Self.showBatteryKey)
            applyBattery()
        }
    }

    /// Bring both blocks in line with their switches. Call once after `onRender` is set.
    func start() {
        applySpeed()
        applyBattery()
    }

    // MARK: - Loops

    private func applySpeed() {
        speedTask?.cancel()
        speedTask = nil
        speed = nil
        guard showsSpeed else { return render() }

        // The rate is derived from the measured elapsed time, so timer drift, coalescing and
        // sleep/wake cannot distort it - only the baseline needs re-arming when the loop restarts.
        speedMonitor.reset()
        render()
        speedTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Nil means the interval was not measurable (first tick, sleep/wake): keep the last
                // reading rather than inventing a rate.
                if let sample = self.speedMonitor.sample() {
                    self.speed = sample
                    self.render()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func applyBattery() {
        batteryTask?.cancel()
        batteryTask = nil
        lastPercent = nil
        guard showsBattery else { return render() }

        render()
        batteryTask = Task { [weak self] in
            while !Task.isCancelled {
                // ~60 ms of subprocess would hitch the menu bar if it ran on the main thread.
                let percent = await Task.detached { AirPodsBatteryMonitor.read() }.value
                // A switch flipped off while the read was in flight must not resurrect the block.
                guard !Task.isCancelled, let self else { return }
                self.lastPercent = percent
                self.notifier.handle(percent: percent)
                self.render()
                // The level only moves a percent every few minutes, and connect/disconnect shows up
                // as the reading appearing or vanishing rather than as a separate event.
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    // MARK: - Drawing

    private func render() {
        let image = ReadoutImage.make(speed: speed, showsSpeed: showsSpeed, percent: lastPercent)
        onRender?(image, tooltip())
    }

    /// Only describes what is actually on screen, so a switched-off block never explains itself.
    private func tooltip() -> String {
        var lines: [String] = []
        if showsSpeed {
            lines.append("Network - top line: upload, bottom line: download (physical links only)")
        }
        if lastPercent != nil {
            lines.append("AirPods battery - one earbud; the pair drains together")
        }
        lines.append("Click for the jj-ice menu")
        return lines.joined(separator: "\n")
    }
}
