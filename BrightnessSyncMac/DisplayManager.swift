import Foundation
import CoreGraphics

/// Represents a display
struct Display {
    let id: CGDirectDisplayID
    let isBuiltIn: Bool
    let name: String
    
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
            
            return Display(id: displayID, isBuiltIn: isBuiltIn, name: name)
        }
        
        lastRefresh = Date()
    }
    
    private func refreshDisplaysIfNeeded() {
        if Date().timeIntervalSince(lastRefresh) > cacheTimeout {
            refreshDisplays()
        }
    }
    
    private func getDisplayName(for displayID: CGDirectDisplayID) -> String? {
        // Try to get the display name from IOKit via IORegistryEntryCreateCFProperties
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
