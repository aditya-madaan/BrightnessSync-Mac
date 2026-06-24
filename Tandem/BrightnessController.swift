import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

/// Brightness calibration settings for each display type.
struct BrightnessCalibration {
    var minBrightness: Float
    var maxBrightness: Float

    func map(_ sliderValue: Float) -> Float {
        return minBrightness + (sliderValue * (maxBrightness - minBrightness))
    }

    func reverseMap(_ brightness: Float) -> Float {
        guard maxBrightness > minBrightness else { return brightness }
        let value = (brightness - minBrightness) / (maxBrightness - minBrightness)
        return max(0.0, min(1.0, value))
    }
}

protocol BrightnessChangeDelegate: AnyObject {
    func brightnessDidChange(sliderValue: Float)
}

/// How brightness is applied to an external display.
enum DisplayControlMode {
    /// Real backlight control via DDC, with the resolved m1ddc index.
    case ddc(m1ddcIndex: Int)
    /// Software dim overlay window.
    case overlay
}

/// Manages brightness control for all connected displays.
class BrightnessController {

    private let displayManager = DisplayManager()
    private let ddcControl = DDCControl()
    private let softDim = SoftwareDimController()

    weak var delegate: BrightnessChangeDelegate?

    // Calibration persistence
    private let macMinKey = "macMinBrightness"
    private let macMaxKey = "macMaxBrightness"
    private let monitorCalKeyPrefix = "monitorCal."

    var macBookCalibration: BrightnessCalibration {
        didSet { saveCalibrationSettings() }
    }

    /// Default calibration for any external display the user hasn't tuned yet.
    /// Min raised from 0 to 0.20 so software-dim displays don't go pitch black at slider 0%.
    let defaultMonitorCalibration = BrightnessCalibration(minBrightness: 0.20, maxBrightness: 1.00)

    /// Per-display calibration, keyed by display UUID. Lazily loaded from UserDefaults.
    private var monitorCalibrations: [String: BrightnessCalibration] = [:]

    /// Per-display resolved mode (cached for the session; cleared on reconfiguration).
    private var resolvedModes: [CGDirectDisplayID: DisplayControlMode] = [:]

    private var currentSliderValue: Float = 0.5
    private var lastKnownMacBrightness: Float = -1
    private var brightnessMonitorTimer: Timer?
    private var isSettingBrightness = false

    init() {
        let defaults = UserDefaults.standard
        let savedMin = defaults.object(forKey: macMinKey) as? Float ?? 0.20
        let savedMax = defaults.object(forKey: macMaxKey) as? Float ?? 0.80
        self.macBookCalibration = BrightnessCalibration(minBrightness: savedMin, maxBrightness: savedMax)
    }

    // MARK: - Public API

    func startMonitoring() {
        // Schedule in .common mode so the poll keeps firing during NSMenu tracking
        // — without this, F1/F2 presses while the menu is open don't update the slider
        // until the menu closes (Timer.scheduledTimer defaults to .default mode only).
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForBrightnessChange()
        }
        RunLoop.main.add(timer, forMode: .common)
        brightnessMonitorTimer = timer
    }

    func stopMonitoring() {
        brightnessMonitorTimer?.invalidate()
        brightnessMonitorTimer = nil
    }

    /// Called when displays are hot-plugged or rearranged — invalidates routing cache,
    /// tears down orphan dim state, and forces the display list cache to refresh so the
    /// next setBrightness call sees newly-connected displays immediately (no 5s lag).
    func displaysReconfigured() {
        resolvedModes.removeAll()
        softDim.removeAll()
        displayManager.refreshDisplays()
    }

    /// Sets brightness for all displays using calibrated values.
    func setBrightness(_ level: Float) {
        isSettingBrightness = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isSettingBrightness = false
            }
        }

        let clamped = max(0.0, min(1.0, level))
        currentSliderValue = clamped

        // Built-in
        let macBrightness = macBookCalibration.map(clamped)
        setBuiltInDisplayBrightness(macBrightness)
        lastKnownMacBrightness = macBrightness

        // External — per-display calibration
        for display in displayManager.getExternalDisplays() {
            let monitorBrightness = calibration(for: display).map(clamped)
            applyExternalBrightness(monitorBrightness, to: display, immediate: false)
        }
    }

    func getBrightness() -> Float {
        if let actualBrightness = getBuiltInDisplayBrightness() {
            currentSliderValue = macBookCalibration.reverseMap(actualBrightness)
        }
        return currentSliderValue
    }

    func getDisplayCount() -> Int {
        let builtIn = getBuiltInDisplayBrightness() != nil ? 1 : 0
        return builtIn + displayManager.getExternalDisplays().count
    }

    // MARK: - Per-display accessors (exposed for UI)

    /// Whether m1ddc is available — drives the install-prompt UI when missing.
    var isM1DDCInstalled: Bool { ddcControl.isM1DDCInstalled }

    /// Returns the list of currently connected external displays.
    func externalDisplays() -> [Display] {
        return displayManager.getExternalDisplays()
    }

    /// Returns the calibration for a display, loading it from UserDefaults on first access.
    /// Falls back to `defaultMonitorCalibration` for new/unknown displays.
    func calibration(for display: Display) -> BrightnessCalibration {
        guard let uuid = display.uuid else { return defaultMonitorCalibration }
        if let cached = monitorCalibrations[uuid] { return cached }

        let defaults = UserDefaults.standard
        if let min = defaults.object(forKey: "\(monitorCalKeyPrefix)\(uuid).min") as? Float,
           let max = defaults.object(forKey: "\(monitorCalKeyPrefix)\(uuid).max") as? Float {
            let cal = BrightnessCalibration(minBrightness: min, maxBrightness: max)
            monitorCalibrations[uuid] = cal
            return cal
        }
        return defaultMonitorCalibration
    }

    /// Persists a calibration and immediately re-applies brightness to that display
    /// so the user sees the effect of their slider change without lag.
    func setCalibration(_ cal: BrightnessCalibration, for display: Display) {
        guard let uuid = display.uuid else { return }
        monitorCalibrations[uuid] = cal

        let defaults = UserDefaults.standard
        defaults.set(cal.minBrightness, forKey: "\(monitorCalKeyPrefix)\(uuid).min")
        defaults.set(cal.maxBrightness, forKey: "\(monitorCalKeyPrefix)\(uuid).max")

        let monitorBrightness = cal.map(currentSliderValue)
        applyExternalBrightness(monitorBrightness, to: display, immediate: true)
    }

    /// Clears per-display calibrations (called by the Reset button).
    func resetAllMonitorCalibrations() {
        let defaults = UserDefaults.standard
        for uuid in monitorCalibrations.keys {
            defaults.removeObject(forKey: "\(monitorCalKeyPrefix)\(uuid).min")
            defaults.removeObject(forKey: "\(monitorCalKeyPrefix)\(uuid).max")
        }
        monitorCalibrations.removeAll()
    }

    // MARK: - Routing

    /// Returns the resolved control mode for a display, computing it on first access.
    /// `auto` (default): probe DDC, fall back to overlay if probe fails.
    func mode(for display: Display) -> DisplayControlMode {
        if let cached = resolvedModes[display.id] { return cached }

        let resolved = resolve(display: display)
        resolvedModes[display.id] = resolved
        print("Tandem: \(display.name) resolved to \(resolved.label)")
        return resolved
    }

    private func resolve(display: Display) -> DisplayControlMode {
        // Name-match the CG display against m1ddc's view of the world.
        guard ddcControl.isM1DDCInstalled else { return .overlay }
        let m1ddcDisplays = ddcControl.getDetectedDisplays()
        guard let match = m1ddcDisplays.first(where: { matches(displayName: display.name, m1ddcName: $0.name) }) else {
            return .overlay
        }
        return ddcControl.probeDisplay(index: match.index)
            ? .ddc(m1ddcIndex: match.index)
            : .overlay
    }

    /// Best-effort name match. CG and m1ddc sometimes report slightly different strings.
    private func matches(displayName cg: String, m1ddcName m1: String) -> Bool {
        let a = cg.lowercased().trimmingCharacters(in: .whitespaces)
        let b = m1.lowercased().trimmingCharacters(in: .whitespaces)
        if a == b { return true }
        // Either contains the other (handles "Dell U2720Q" vs "DELL U2720Q (USB-C)" etc.).
        return a.contains(b) || b.contains(a)
    }

    private func applyExternalBrightness(_ level: Float, to display: Display, immediate: Bool) {
        switch mode(for: display) {
        case .ddc(let index):
            if immediate {
                ddcControl.setBrightnessImmediate(m1ddcIndex: index, level: level)
            } else {
                ddcControl.setBrightness(m1ddcIndex: index, level: level)
            }
        case .overlay:
            softDim.setBrightness(level, for: display.id)
        }
    }

    // MARK: - Reactive sync (poll built-in)

    private func checkForBrightnessChange() {
        guard !isSettingBrightness else { return }
        guard let currentMacBrightness = getBuiltInDisplayBrightness() else { return }

        let delta = abs(currentMacBrightness - lastKnownMacBrightness)
        if delta > 0.005 && lastKnownMacBrightness >= 0 {
            let sliderValue = macBookCalibration.reverseMap(currentMacBrightness)

            for display in displayManager.getExternalDisplays() {
                let monitorBrightness = calibration(for: display).map(sliderValue)
                applyExternalBrightness(monitorBrightness, to: display, immediate: true)
            }

            currentSliderValue = sliderValue
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.brightnessDidChange(sliderValue: sliderValue)
            }
        }
        lastKnownMacBrightness = currentMacBrightness
    }

    private func saveCalibrationSettings() {
        let defaults = UserDefaults.standard
        defaults.set(macBookCalibration.minBrightness, forKey: macMinKey)
        defaults.set(macBookCalibration.maxBrightness, forKey: macMaxKey)
    }

    // MARK: - Built-in Display Control

    @discardableResult
    private func setBuiltInDisplayBrightness(_ level: Float) -> Bool {
        if setDisplayServicesBrightness(level) { return true }
        if setIOKitBrightness(level) { return true }
        return false
    }

    private func setDisplayServicesBrightness(_ level: Float) -> Bool {
        guard let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return false }
        defer { dlclose(displayServices) }

        let mainDisplay = CGMainDisplayID()
        typealias SetBrightnessFunc = @convention(c) (UInt32, Float) -> Int32

        if let symbolPtr = dlsym(displayServices, "DisplayServicesSetBrightness") {
            let setBrightness = unsafeBitCast(symbolPtr, to: SetBrightnessFunc.self)
            return setBrightness(mainDisplay, level) == 0
        }
        return false
    }

    private func setIOKitBrightness(_ level: Float) -> Bool {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
        guard result == kIOReturnSuccess else { return false }
        defer { IOObjectRelease(iterator) }

        var success = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, level) == kIOReturnSuccess {
                success = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return success
    }

    private func getBuiltInDisplayBrightness() -> Float? {
        if let brightness = getDisplayServicesBrightness() { return brightness }
        return getIOKitBrightness()
    }

    private func getDisplayServicesBrightness() -> Float? {
        guard let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return nil }
        defer { dlclose(displayServices) }

        let mainDisplay = CGMainDisplayID()
        typealias GetBrightnessFunc = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

        if let symbolPtr = dlsym(displayServices, "DisplayServicesGetBrightness") {
            let getBrightness = unsafeBitCast(symbolPtr, to: GetBrightnessFunc.self)
            var brightness: Float = 0
            if getBrightness(mainDisplay, &brightness) == 0 {
                return brightness
            }
        }
        return nil
    }

    private func getIOKitBrightness() -> Float? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
        guard result == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var brightness: Float = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness) == kIOReturnSuccess {
                IOObjectRelease(service)
                return brightness
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }
}

private extension DisplayControlMode {
    var label: String {
        switch self {
        case .ddc(let i): return "DDC (m1ddc index \(i))"
        case .overlay:    return "Overlay"
        }
    }
}
