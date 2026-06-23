import Cocoa
import CoreGraphics

/// Software-dim fallback for displays where DDC isn't available (HDMI, docks, etc.).
/// Uses GPU gamma table scaling — applied at the framebuffer output stage, so it
/// survives Spaces, fullscreen transitions, screen recording, and Mission Control.
/// The display's original transfer curve is captured on first dim and multiplicatively
/// scaled by the brightness level. Original tables are restored on quit / hotplug.
final class SoftwareDimController {

    private struct GammaTable {
        let red: [CGGammaValue]
        let green: [CGGammaValue]
        let blue: [CGGammaValue]
    }

    /// Hard floor — never go fully black. The user's per-display calibration
    /// (BrightnessController.calibration) sets the practical minimum above this.
    private let minLevel: CGGammaValue = 0.05

    private var originalTables: [CGDirectDisplayID: GammaTable] = [:]
    private var anyDimApplied = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        removeAll()
    }

    // MARK: - Public API

    /// Set effective brightness for a display.
    /// - Parameter level: 0.0 (dimmest, clamped to minLevel) to 1.0 (original brightness).
    func setBrightness(_ level: Float, for displayID: CGDirectDisplayID) {
        let scale = CGGammaValue(max(minLevel, min(1.0, CGGammaValue(level))))

        if let original = capturedOrCapture(displayID) {
            apply(table: original, scaledBy: scale, to: displayID)
        } else {
            // Fallback: linear formula transfer (loses calibration but at least dims).
            _ = CGSetDisplayTransferByFormula(
                displayID,
                0, scale, 1.0,
                0, scale, 1.0,
                0, scale, 1.0
            )
        }
        anyDimApplied = true
    }

    /// Restore original gamma for all known displays. Call on quit and hotplug.
    func removeAll() {
        for (displayID, table) in originalTables {
            apply(table: table, scaledBy: 1.0, to: displayID)
        }
        originalTables.removeAll()
        if anyDimApplied {
            // Safety net for any display whose original wasn't captured
            // (or where the table application silently failed).
            CGDisplayRestoreColorSyncSettings()
            anyDimApplied = false
        }
    }

    // MARK: - Internals

    @objc private func applicationWillTerminate() {
        removeAll()
    }

    private func capturedOrCapture(_ displayID: CGDirectDisplayID) -> GammaTable? {
        if let cached = originalTables[displayID] { return cached }
        guard let captured = captureOriginalTable(for: displayID) else { return nil }
        originalTables[displayID] = captured
        return captured
    }

    private func captureOriginalTable(for displayID: CGDirectDisplayID) -> GammaTable? {
        let capacity: UInt32 = 4096
        var r = [CGGammaValue](repeating: 0, count: Int(capacity))
        var g = [CGGammaValue](repeating: 0, count: Int(capacity))
        var b = [CGGammaValue](repeating: 0, count: Int(capacity))
        var actual: UInt32 = 0

        let result = CGGetDisplayTransferByTable(displayID, capacity, &r, &g, &b, &actual)
        guard result == .success, actual > 0 else { return nil }
        let count = Int(actual)
        return GammaTable(
            red: Array(r.prefix(count)),
            green: Array(g.prefix(count)),
            blue: Array(b.prefix(count))
        )
    }

    private func apply(table: GammaTable, scaledBy scale: CGGammaValue, to displayID: CGDirectDisplayID) {
        let r = scale == 1.0 ? table.red   : table.red.map   { $0 * scale }
        let g = scale == 1.0 ? table.green : table.green.map { $0 * scale }
        let b = scale == 1.0 ? table.blue  : table.blue.map  { $0 * scale }

        r.withUnsafeBufferPointer { rPtr in
            g.withUnsafeBufferPointer { gPtr in
                b.withUnsafeBufferPointer { bPtr in
                    _ = CGSetDisplayTransferByTable(
                        displayID,
                        UInt32(r.count),
                        rPtr.baseAddress,
                        gPtr.baseAddress,
                        bPtr.baseAddress
                    )
                }
            }
        }
    }
}
