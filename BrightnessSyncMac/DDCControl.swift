import Foundation
import CoreGraphics

/// Controls external monitors via m1ddc command-line tool
class DDCControl {
    
    private var brightnessCache: [CGDirectDisplayID: Float] = [:]
    private let m1ddcPath = "/opt/homebrew/bin/m1ddc"
    
    // Throttling for slider dragging
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.brightness.sync.ddc", qos: .userInitiated)
    private var lastExecutionTime: Date = .distantPast
    private let minInterval: TimeInterval = 0.05
    
    /// Sets brightness with throttling (for slider dragging)
    func setBrightness(for display: Display, level: Float) {
        let value = Int(max(0, min(100, level * 100)))
        brightnessCache[display.id] = level
        
        pendingWorkItem?.cancel()
        
        let timeSinceLastExecution = Date().timeIntervalSince(lastExecutionTime)
        
        if timeSinceLastExecution >= minInterval {
            executeBrightnessCommand(value: value)
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeBrightnessCommand(value: value)
            }
            pendingWorkItem = workItem
            let delay = minInterval - timeSinceLastExecution
            queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
    
    /// Sets brightness immediately without throttling (for keyboard sync)
    func setBrightnessImmediate(for display: Display, level: Float) {
        let value = Int(max(0, min(100, level * 100)))
        brightnessCache[display.id] = level
        
        // Cancel any pending work and execute immediately
        pendingWorkItem?.cancel()
        executeBrightnessCommand(value: value)
    }
    
    private func executeBrightnessCommand(value: Int) {
        lastExecutionTime = Date()
        
        guard FileManager.default.fileExists(atPath: m1ddcPath) else {
            print("BrightnessSync: m1ddc not found - install with: brew install m1ddc")
            return
        }
        
        print("BrightnessSync: m1ddc set luminance \(value)")
        _ = runM1DDC(args: ["set", "luminance", String(value)])
    }
    
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
