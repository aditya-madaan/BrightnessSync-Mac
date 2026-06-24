import Foundation
import AppKit
import CoreGraphics

/// Represents a display
struct Display {
    let id: CGDirectDisplayID
    let isBuiltIn: Bool
    let name: String
    /// CFUUID string — stable identifier across sessions, suitable as a UserDefaults key.
    let uuid: String?

    var isExternal: Bool { !isBuiltIn }
}

/// Manages display enumeration and identification
class DisplayManager {
    
    private var cachedDisplays: [Display] = []
    private var lastRefresh: Date = .distantPast
    private let cacheTimeout: TimeInterval = 5.0 // Refresh every 5 seconds max
    
    /// Returns all external (non-built-in) displays
    func getExternalDisplays() -> [Display] {
        refreshDisplaysIfNeeded()
        return cachedDisplays.filter { $0.isExternal }
    }
    
    /// Returns all displays
    func getAllDisplays() -> [Display] {
        refreshDisplaysIfNeeded()
        return cachedDisplays
    }
    
    /// Forces a refresh of the display list
    func refreshDisplays() {
        var displayCount: UInt32 = 0
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        
        let result = CGGetActiveDisplayList(16, &displayIDs, &displayCount)
        guard result == .success else {
            print("Failed to get display list")
            cachedDisplays = []
            return
        }
        
        cachedDisplays = (0..<Int(displayCount)).map { index in
            let displayID = displayIDs[index]
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let name = getDisplayName(for: displayID) ?? "Display \(index + 1)"
            let uuid = getUUID(for: displayID)

            return Display(id: displayID, isBuiltIn: isBuiltIn, name: name, uuid: uuid)
        }
        
        lastRefresh = Date()
    }
    
    private func refreshDisplaysIfNeeded() {
        if Date().timeIntervalSince(lastRefresh) > cacheTimeout {
            refreshDisplays()
        }
    }
    
    /// Stable per-display identifier built from EDID vendor + model + serial.
    /// Survives reboots, hotplug, and reconnection — suitable as a UserDefaults key.
    /// For displays missing one of these fields, the corresponding slot is 0;
    /// two identical-model displays without serials would collide (rare edge case).
    private func getUUID(for displayID: CGDirectDisplayID) -> String? {
        let vendor = CGDisplayVendorNumber(displayID)
        let model  = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        if vendor == 0 && model == 0 && serial == 0 { return nil }
        return "v\(vendor)_m\(model)_s\(serial)"
    }

    /// Returns the display's user-facing name (EDID product name).
    /// Prefers NSScreen.localizedName — the reliable path on Apple Silicon.
    /// Falls back to the legacy IOKit IODisplayConnect lookup for older edge cases.
    private func getDisplayName(for displayID: CGDirectDisplayID) -> String? {
        // Modern path: NSScreen exposes the localized name per display.
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }) {
            let name = screen.localizedName
            if !name.isEmpty { return name }
        }
        // Legacy path: IODisplayConnect (often empty on Apple Silicon, kept as fallback).
        return getDisplayNameFromIOKit()
    }

    private func getDisplayNameFromIOKit() -> String? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        guard result == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let props = properties?.takeRetainedValue() as? [String: Any],
               let names = props["DisplayProductName"] as? [String: String],
               let name = names["en_US"] ?? names.values.first {
                IOObjectRelease(service)
                return name
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }
}
