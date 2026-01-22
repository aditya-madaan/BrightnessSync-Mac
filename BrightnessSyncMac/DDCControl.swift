import Foundation
import CoreGraphics

/// Controls external monitors via m1ddc command-line tool
class DDCControl {
    
    // Cache for brightness values
    private var brightnessCache: [CGDirectDisplayID: Float] = [:]
    
    // Path to m1ddc
    private let m1ddcPath = "/opt/homebrew/bin/m1ddc"
    
    // Throttling for rapid changes (slider dragging)
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.brightness.sync.ddc", qos: .userInitiated)
    private var lastExecutionTime: Date = .distantPast
    private let minInterval: TimeInterval = 0.05 // 50ms minimum between commands
    
    /// Sets brightness for an external display
    func setBrightness(for display: Display, level: Float) {
        let value = Int(max(0, min(100, level * 100)))
        
        // Update cache immediately
        brightnessCache[display.id] = level
        
        // Cancel any pending work
        pendingWorkItem?.cancel()
        
        // Check if we need to throttle
        let timeSinceLastExecution = Date().timeIntervalSince(lastExecutionTime)
        
        if timeSinceLastExecution >= minInterval {
            // Execute immediately
            executeBrightnessCommand(value: value)
        } else {
            // Schedule for later (debounce rapid slider movements)
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeBrightnessCommand(value: value)
            }
            pendingWorkItem = workItem
            let delay = minInterval - timeSinceLastExecution
            queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    private func executeBrightnessCommand(value: Int) {
        lastExecutionTime = Date()
        
        guard FileManager.default.fileExists(atPath: m1ddcPath) else {
            print("BrightnessSync: m1ddc not found at \(m1ddcPath)")
            print("BrightnessSync: Install with: brew install m1ddc")
            return
        }
        
        print("BrightnessSync: Setting external display to \(value)% via m1ddc")
        
        let success = runM1DDC(args: ["set", "luminance", String(value)])
        
        if success {
            print("BrightnessSync: External monitor brightness set ✓")
        } else {
            print("BrightnessSync: m1ddc command failed")
        }
    }
    
    /// Gets brightness for an external display
    func getBrightness(for display: Display) -> Float? {
        if let cached = brightnessCache[display.id] {
            return cached
        }
        
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
            return nil
        }
    }
}
