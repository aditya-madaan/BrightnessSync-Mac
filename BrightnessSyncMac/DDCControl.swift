import Foundation
import CoreGraphics

/// Controls external monitors via m1ddc command-line tool with throttling
class DDCControl {
    
    // Cache for brightness values
    private var brightnessCache: [CGDirectDisplayID: Float] = [:]
    
    // Path to m1ddc
    private let m1ddcPath = "/opt/homebrew/bin/m1ddc"
    
    // Throttling
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.brightness.sync.ddc", qos: .userInitiated)
    
    /// Sets brightness for an external display with throttling
    func setBrightness(for display: Display, level: Float) {
        let value = Int(max(0, min(100, level * 100)))
        
        // Update cache immediately so UI feels responsive
        brightnessCache[display.id] = level
        
        // Cancel previous pending request
        pendingWorkItem?.cancel()
        
        // Create new work item
        let workItem = DispatchWorkItem { [weak self] in
            self?.executeBrightnessCommand(value: value)
        }
        
        pendingWorkItem = workItem
        
        // Execute with a slight delay (debouncing)
        // 0.1s delay allows for smooth slider dragging without overwhelming the monitor
        queue.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
    
    private func executeBrightnessCommand(value: Int) {
        // Double check if path exists
        guard FileManager.default.fileExists(atPath: m1ddcPath) else {
            print("BrightnessSync: m1ddc not found at \(m1ddcPath)")
            return
        }
        
        print("BrightnessSync: Setting external display brightness to \(value)% via m1ddc")
        
        // Use m1ddc to set brightness
        // m1ddc set luminance <value>
        // Note: m1ddc usually addresses the default external display. 
        // If there are multiple, advanced indexing logic would be needed. 
        // For now, we assume simple single external monitor setup or m1ddc handling defaults.
        let success = runM1DDC(args: ["set", "luminance", String(value)])
        
        if success {
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
        
        // Try to read current brightness from m1ddc (blocking, so use carefully)
        // We only do this on startup/refresh, not during slider interaction
        if let output = runM1DDCWithOutput(args: ["get", "luminance"]) {
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
