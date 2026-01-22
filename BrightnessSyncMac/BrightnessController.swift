import Foundation
import IOKit
import IOKit.graphics
import CoreGraphics

/// Brightness calibration settings for each display type
struct BrightnessCalibration {
    var minBrightness: Float  // What brightness level to use when slider is at 0%
    var maxBrightness: Float  // What brightness level to use when slider is at 100%
    
    /// Maps slider value (0-1) to calibrated brightness (min-max)
    func map(_ sliderValue: Float) -> Float {
        return minBrightness + (sliderValue * (maxBrightness - minBrightness))
    }
    
    /// Reverse maps calibrated brightness back to slider value
    func reverseMap(_ brightness: Float) -> Float {
        guard maxBrightness > minBrightness else { return brightness }
        let value = (brightness - minBrightness) / (maxBrightness - minBrightness)
        return max(0.0, min(1.0, value))
    }
}

/// Manages brightness control for all connected displays
class BrightnessController {
    
    private let displayManager = DisplayManager()
    private let ddcControl = DDCControl()
    
    // UserDefaults keys
    private let macMinKey = "macMinBrightness"
    private let macMaxKey = "macMaxBrightness"
    
    // Calibration settings (loaded from UserDefaults)
    var macBookCalibration: BrightnessCalibration {
        didSet {
            saveCalirationSettings()
        }
    }
    
    // External monitor: slider 0% = 0% brightness, slider 100% = 100% brightness
    let monitorCalibration = BrightnessCalibration(minBrightness: 0.0, maxBrightness: 1.0)
    
    // Store the current slider value (0-1)
    private var currentSliderValue: Float = 0.5
    
    init() {
        // Load saved calibration or use defaults
        let defaults = UserDefaults.standard
        let savedMin = defaults.object(forKey: macMinKey) as? Float ?? 0.20
        let savedMax = defaults.object(forKey: macMaxKey) as? Float ?? 0.80
        self.macBookCalibration = BrightnessCalibration(minBrightness: savedMin, maxBrightness: savedMax)
    }
    
    private func saveCalirationSettings() {
        let defaults = UserDefaults.standard
        defaults.set(macBookCalibration.minBrightness, forKey: macMinKey)
        defaults.set(macBookCalibration.maxBrightness, forKey: macMaxKey)
    }
    
    /// Sets brightness for all displays using calibrated values
    /// - Parameter level: Slider level from 0.0 to 1.0
    func setBrightness(_ level: Float) {
        let clampedLevel = max(0.0, min(1.0, level))
        currentSliderValue = clampedLevel
        
        // Calculate calibrated brightness for MacBook
        let macBrightness = macBookCalibration.map(clampedLevel)
        print("BrightnessSync: Slider \(Int(clampedLevel * 100))% → MacBook \(Int(macBrightness * 100))%")
        
        // Set built-in display brightness
        let builtInSuccess = setBuiltInDisplayBrightness(macBrightness)
        if !builtInSuccess {
            print("BrightnessSync: Failed to set MacBook brightness")
        }
        
        // Calculate calibrated brightness for external monitor
        let monitorBrightness = monitorCalibration.map(clampedLevel)
        print("BrightnessSync: Slider \(Int(clampedLevel * 100))% → Monitor \(Int(monitorBrightness * 100))%")
        
        // Set external display brightness via DDC (synchronously for key presses)
        let externalDisplays = displayManager.getExternalDisplays()
        for display in externalDisplays {
            ddcControl.setBrightness(for: display, level: monitorBrightness)
        }
    }
    
    /// Gets the current slider value (not the actual brightness)
    /// - Returns: Slider level from 0.0 to 1.0
    func getBrightness() -> Float {
        // Try to get built-in display brightness and reverse-map it
        if let actualBrightness = getBuiltInDisplayBrightness() {
            // Reverse map from actual brightness to slider value
            let sliderValue = macBookCalibration.reverseMap(actualBrightness)
            currentSliderValue = sliderValue
            return currentSliderValue
        }
        
        return currentSliderValue
    }
    
    /// Returns the number of connected displays
    func getDisplayCount() -> Int {
        var builtInCount = 0
        if getBuiltInDisplayBrightness() != nil {
            builtInCount = 1
        }
        return builtInCount + displayManager.getExternalDisplays().count
    }
    
    // MARK: - Built-in Display Control
    
    private func setBuiltInDisplayBrightness(_ level: Float) -> Bool {
        // Method 1: Try DisplayServices private framework (most reliable on modern macOS)
        if setDisplayServicesBrightness(level) {
            return true
        }
        
        // Method 2: Try IOKit IODisplaySetFloatParameter
        if setIOKitBrightness(level) {
            return true
        }
        
        return false
    }
    
    private func setDisplayServicesBrightness(_ level: Float) -> Bool {
        guard let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return false
        }
        
        defer { dlclose(displayServices) }
        
        let mainDisplay = CGMainDisplayID()
        
        typealias SetBrightnessFunc = @convention(c) (UInt32, Float) -> Int32
        
        if let symbolPtr = dlsym(displayServices, "DisplayServicesSetBrightness") {
            let setBrightness = unsafeBitCast(symbolPtr, to: SetBrightnessFunc.self)
            let result = setBrightness(mainDisplay, level)
            return result == 0
        }
        
        return false
    }
    
    private func setIOKitBrightness(_ level: Float) -> Bool {
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        
        guard result == kIOReturnSuccess else {
            return false
        }
        
        defer { IOObjectRelease(iterator) }
        
        var success = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let setResult = IODisplaySetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                level
            )
            if setResult == kIOReturnSuccess {
                success = true
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        return success
    }
    
    private func getBuiltInDisplayBrightness() -> Float? {
        if let brightness = getDisplayServicesBrightness() {
            return brightness
        }
        return getIOKitBrightness()
    }
    
    private func getDisplayServicesBrightness() -> Float? {
        guard let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return nil
        }
        
        defer { dlclose(displayServices) }
        
        let mainDisplay = CGMainDisplayID()
        
        typealias GetBrightnessFunc = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
        
        if let symbolPtr = dlsym(displayServices, "DisplayServicesGetBrightness") {
            let getBrightness = unsafeBitCast(symbolPtr, to: GetBrightnessFunc.self)
            var brightness: Float = 0
            let result = getBrightness(mainDisplay, &brightness)
            if result == 0 {
                return brightness
            }
        }
        
        return nil
    }
    
    private func getIOKitBrightness() -> Float? {
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        
        guard result == kIOReturnSuccess else {
            return nil
        }
        
        defer { IOObjectRelease(iterator) }
        
        var brightness: Float = 0
        var service = IOIteratorNext(iterator)
        
        while service != 0 {
            let getResult = IODisplayGetFloatParameter(
                service,
                0,
                kIODisplayBrightnessKey as CFString,
                &brightness
            )
            
            if getResult == kIOReturnSuccess {
                IOObjectRelease(service)
                return brightness
            }
            
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        return nil
    }
}
