import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

/// Brightness calibration settings for each display type
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

/// Manages brightness control for all connected displays
class BrightnessController {
    
    private let displayManager = DisplayManager()
    private let ddcControl = DDCControl()
    
    weak var delegate: BrightnessChangeDelegate?
    
    // UserDefaults keys
    private let macMinKey = "macMinBrightness"
    private let macMaxKey = "macMaxBrightness"
    
    // Calibration settings
    var macBookCalibration: BrightnessCalibration {
        didSet { saveCalibrationSettings() }
    }
    
    let monitorCalibration = BrightnessCalibration(minBrightness: 0.0, maxBrightness: 1.0)
    
    private var currentSliderValue: Float = 0.5
    private var lastKnownMacBrightness: Float = -1
    private var brightnessMonitorTimer: Timer?
    private var isSettingBrightness = false // Prevent feedback loop
    
    init() {
        let defaults = UserDefaults.standard
        let savedMin = defaults.object(forKey: macMinKey) as? Float ?? 0.20
        let savedMax = defaults.object(forKey: macMaxKey) as? Float ?? 0.80
        self.macBookCalibration = BrightnessCalibration(minBrightness: savedMin, maxBrightness: savedMax)
    }
    
    // MARK: - Brightness Monitoring (Reactive Sync)
    
    func startMonitoring() {
        // Poll Mac brightness every 100ms to detect changes from native keyboard
        brightnessMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkForBrightnessChange()
        }
        print("BrightnessSync: Started monitoring Mac brightness")
    }
    
    func stopMonitoring() {
        brightnessMonitorTimer?.invalidate()
        brightnessMonitorTimer = nil
    }
    
    private func checkForBrightnessChange() {
        guard !isSettingBrightness else { return }
        
        guard let currentMacBrightness = getBuiltInDisplayBrightness() else { return }
        
        // Detect if brightness changed (with small tolerance for floating point)
        let delta = abs(currentMacBrightness - lastKnownMacBrightness)
        if delta > 0.005 && lastKnownMacBrightness >= 0 {
            // Mac brightness changed externally (keyboard or Control Center)
            print("BrightnessSync: Detected Mac brightness change: \(Int(currentMacBrightness * 100))%")
            
            // Sync external monitor to match
            let sliderValue = macBookCalibration.reverseMap(currentMacBrightness)
            let monitorBrightness = monitorCalibration.map(sliderValue)
            
            print("BrightnessSync: Syncing monitor to \(Int(monitorBrightness * 100))%")
            
            let externalDisplays = displayManager.getExternalDisplays()
            for display in externalDisplays {
                ddcControl.setBrightnessImmediate(for: display, level: monitorBrightness)
            }
            
            currentSliderValue = sliderValue
            
            // Notify delegate (update UI)
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
    
    /// Sets brightness for all displays using calibrated values
    func setBrightness(_ level: Float) {
        isSettingBrightness = true
        defer { 
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isSettingBrightness = false
            }
        }
        
        let clampedLevel = max(0.0, min(1.0, level))
        currentSliderValue = clampedLevel
        
        // Set MacBook brightness
        let macBrightness = macBookCalibration.map(clampedLevel)
        print("BrightnessSync: Slider \(Int(clampedLevel * 100))% → Mac \(Int(macBrightness * 100))%")
        setBuiltInDisplayBrightness(macBrightness)
        lastKnownMacBrightness = macBrightness
        
        // Set external monitor brightness
        let monitorBrightness = monitorCalibration.map(clampedLevel)
        print("BrightnessSync: Slider \(Int(clampedLevel * 100))% → Monitor \(Int(monitorBrightness * 100))%")
        
        let externalDisplays = displayManager.getExternalDisplays()
        for display in externalDisplays {
            ddcControl.setBrightness(for: display, level: monitorBrightness)
        }
    }
    
    func getBrightness() -> Float {
        if let actualBrightness = getBuiltInDisplayBrightness() {
            currentSliderValue = macBookCalibration.reverseMap(actualBrightness)
        }
        return currentSliderValue
    }
    
    func getDisplayCount() -> Int {
        var builtInCount = 0
        if getBuiltInDisplayBrightness() != nil {
            builtInCount = 1
        }
        return builtInCount + displayManager.getExternalDisplays().count
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
