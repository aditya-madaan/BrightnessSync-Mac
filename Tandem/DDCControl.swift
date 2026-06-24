import Foundation
import CoreGraphics

/// Controls external monitors via the m1ddc command-line tool.
/// Operates on m1ddc display indices (1-based). Callers resolve CGDirectDisplayIDs
/// to m1ddc indices via name matching against `getDetectedDisplays()`.
class DDCControl {

    private let m1ddcPath = "/opt/homebrew/bin/m1ddc"

    // Throttling for slider dragging (shared across all displays — m1ddc serializes anyway).
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.tandem.brightness.ddc", qos: .userInitiated)
    private var lastExecutionTime: Date = .distantPast
    private let minInterval: TimeInterval = 0.05

    /// True if m1ddc is installed at the expected path.
    var isM1DDCInstalled: Bool {
        FileManager.default.fileExists(atPath: m1ddcPath)
    }

    /// Detected m1ddc display (parsed from `m1ddc display list`).
    struct DetectedDisplay {
        let index: Int
        let name: String
    }

    /// Returns list of external displays detected by m1ddc.
    func getDetectedDisplays() -> [DetectedDisplay] {
        guard let output = runM1DDCWithOutput(args: ["display", "list"]) else { return [] }

        var displays: [DetectedDisplay] = []
        for line in output.components(separatedBy: "\n") {
            // Format: [N] DisplayName (UUID)
            guard let bracket = line.range(of: #"^\[(\d+)\]\s+"#, options: .regularExpression),
                  let indexMatch = line.range(of: #"\d+"#, options: .regularExpression, range: bracket),
                  let index = Int(line[indexMatch]) else { continue }

            // Skip built-in (shows as "(null)").
            if line.contains("(null)") { continue }

            let name = line
                .replacingOccurrences(of: #"^\[\d+\]\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+\([^)]+\)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            displays.append(DetectedDisplay(index: index, name: name))
        }
        return displays
    }

    /// Probes whether DDC actually works for a specific m1ddc display.
    /// Reads luminance (read-only — no value change). Returns false if the call
    /// errors, times out, or returns no valid number.
    func probeDisplay(index: Int) -> Bool {
        guard isM1DDCInstalled else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: m1ddcPath)
        process.arguments = ["get", "luminance", "-d", String(index)]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        if process.terminationStatus != 0 { return false }

        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if stderr.localizedCaseInsensitiveContains("failure") { return false }

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed) != nil
    }

    /// Sets brightness for a specific m1ddc display (throttled for slider drags).
    func setBrightness(m1ddcIndex: Int, level: Float) {
        let value = Int(max(0, min(100, level * 100)))

        pendingWorkItem?.cancel()

        let elapsed = Date().timeIntervalSince(lastExecutionTime)
        if elapsed >= minInterval {
            executeSet(value: value, index: m1ddcIndex)
        } else {
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeSet(value: value, index: m1ddcIndex)
            }
            pendingWorkItem = workItem
            queue.asyncAfter(deadline: .now() + (minInterval - elapsed), execute: workItem)
        }
    }

    /// Sets brightness immediately for a specific m1ddc display (no throttle — used for keyboard sync).
    func setBrightnessImmediate(m1ddcIndex: Int, level: Float) {
        let value = Int(max(0, min(100, level * 100)))
        pendingWorkItem?.cancel()
        executeSet(value: value, index: m1ddcIndex)
    }

    private func executeSet(value: Int, index: Int) {
        lastExecutionTime = Date()
        guard isM1DDCInstalled else {
            print("Tandem: m1ddc not found at \(m1ddcPath)")
            return
        }
        _ = runM1DDC(args: ["set", "luminance", String(value), "-d", String(index)])
    }

    @discardableResult
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
        guard isM1DDCInstalled else { return nil }

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
