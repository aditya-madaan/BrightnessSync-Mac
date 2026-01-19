import Foundation
import CoreGraphics

/// Controls external monitors via m1ddc command-line tool
class DDCControl {
    
    // Cache for brightness values
    private var brightnessCache: [CGDirectDisplayID: Float] = [:]
    
    // Path to m1ddc
    private let m1ddcPath = "/opt/homebrew/bin/m1ddc"
    
    /// Sets brightness for an external display using m1ddc
    func setBrightness(for display: Display, level: Float) {
        let value = Int(max(0, min(100, level * 100)))
        print("BrightnessSync: Setting external display brightness to \(value)% via m1ddc")
        
        // Use m1ddc to set brightness
        // m1ddc set luminance <value>
        let success = runM1DDC(args: ["set", "luminance", String(value)])
        
        if success {
            brightnessCache[display.id] = level
            print("BrightnessSync: m1ddc brightness set successfully")
        } else {
            print("BrightnessSync: m1ddc failed to set brightness")
        }
    }
    
    /// Gets brightness for an external display
    func getBrightness(for display: Display) -> Float? {
        if let cached = brightnessCache[display.id] {
            return cached
        }
        
        // Try to read current brightness from m1ddc
        if let output = runM1DDCWithOutput(args: ["get", "luminance"]) {
            // Parse the output - m1ddc returns the value
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(trimmed) {
                let level = Float(value) / 100.0
                brightnessCache[display.id] = level
                return level
            }
        }
        
        return 0.5
    }
    
    // MARK: - m1ddc Execution
    
    private func runM1DDC(args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: m1ddcPath)
        process.arguments = args
        
        // Suppress output
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("BrightnessSync: Failed to run m1ddc: \(error)")
            return false
        }
    }
    
    private func runM1DDCWithOutput(args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: m1ddcPath)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            print("BrightnessSync: Failed to run m1ddc: \(error)")
            return nil
        }
    }
}
