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
    
    /// Gets list of external displays detected by m1ddc
    func getDetectedDisplays() -> [(index: Int, name: String, uuid: String)] {
        guard let output = runM1DDCWithOutput(args: ["display", "list"]) else {
            return []
        }
        
        var displays: [(index: Int, name: String, uuid: String)] = []
        let lines = output.components(separatedBy: "\n")
        
        for line in lines {
            // Parse format: [1] DisplayName (UUID)
            if let match = line.range(of: #"\[(\d+)\]\s+(.+?)\s+\(([^)]+)\)"#, options: .regularExpression) {
                let fullMatch = String(line[match])
                
                // Extract components
                if let indexMatch = fullMatch.range(of: #"\[(\d+)\]"#, options: .regularExpression),
                   let index = Int(fullMatch[indexMatch].dropFirst().dropLast()) {
                    
                    // Skip index 1 which is usually the built-in display shown as "(null)"
                    let name = line.contains("(null)") ? "Built-in Display" : 
                               line.replacingOccurrences(of: #"\[\d+\]\s+"#, with: "", options: .regularExpression)
                                   .replacingOccurrences(of: #"\s+\([^)]+\)$"#, with: "", options: .regularExpression)
                    
                    if !line.contains("(null)") {
                        displays.append((index: index, name: name.trimmingCharacters(in: .whitespaces), uuid: ""))
                    }
                }
            }
        }
        
        return displays
    }
    
    /// Sets brightness with throttling (for slider dragging)
    func setBrightness(for display: Display, level: Float) {
        let value = Int(max(0, min(100, level * 100)))
        brightnessCache[display.id] = level
        
        pendingWorkItem?.cancel()
        
        let timeSinceLastExecution = Date().timeIntervalSince(lastExecutionTime)
        
        if timeSinceLastExecution >= minInterval {
            executeBrightnessCommandForAll(value: value)
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeBrightnessCommandForAll(value: value)
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
        
        pendingWorkItem?.cancel()
        executeBrightnessCommandForAll(value: value)
    }
    
    /// Execute brightness command for ALL detected external displays
    private func executeBrightnessCommandForAll(value: Int) {
        lastExecutionTime = Date()
        
        guard FileManager.default.fileExists(atPath: m1ddcPath) else {
            print("BrightnessSync: m1ddc not found - install with: brew install m1ddc")
            return
        }
        
        // Get all detected displays
        let displays = getDetectedDisplays()
        
        if displays.isEmpty {
            // Fallback: try without display index (controls default display)
            print("BrightnessSync: No external displays detected, trying default...")
            _ = runM1DDC(args: ["set", "luminance", String(value)])
            return
        }
        
        // Set brightness for each detected external display
        for display in displays {
            print("BrightnessSync: Setting display \(display.index) (\(display.name)) to \(value)%")
            _ = runM1DDC(args: ["set", "luminance", String(value), "-d", String(display.index)])
        }
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
        guard FileManager.default.fileExists(atPath: m1ddcPath) else {
            return nil
        }
        
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
