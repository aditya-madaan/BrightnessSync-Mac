import Cocoa
import CoreGraphics

protocol MediaKeyDelegate: AnyObject {
    func handleBrightnessEvent(up: Bool, isRepeat: Bool)
}

class MediaKeyManager {
    
    weak var delegate: MediaKeyDelegate?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // NX Keycodes (from IOKit/hidsystem/ev_keymap.h)
    private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
    private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
    
    // CGEventType.nxSystemDefined is not exposed in Swift directly as a named case easily, 
    // but likely maps to .tapDisabledByTimeout (val 0xFFFFFFFE) ? No.
    // We use the raw value 14 which is defined in CGEventTypes.h as kCGEventNXSystemDefined
    private let kCGEventNXSystemDefined = CGEventType(rawValue: 14)!
    
    func start() {
        // Create an event tap to intercept system keys
        // We capture at the HID level to block the system default beeps/actions
        
        let eventMask = (1 << kCGEventNXSystemDefined.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let ref = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<MediaKeyManager>.fromOpaque(ref).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("MediaKeyManager: Failed to create event tap (Requires Accessibility)")
            return
        }
        
        self.eventTap = tap
        
        // Add to run loop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        print("MediaKeyManager: Started listening for native brightness keys")
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            self.runLoopSource = nil
        }
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == kCGEventNXSystemDefined {
            // Get event data
            // The 16-32 bits contain the keycode for system events
            // We use integer value field 0 (data1)
            let data1 = event.getIntegerValueField(.eventSourceUserData) // This usually holds the data for system events
            
            // Actually, for NSEvent/CGEvent system defined:
            // Field 1 (data1) contains the keycode info
            // In CoreGraphics Swift API, we might need to rely on the NSEvent wrapper to parse it easily, 
            // but we can't create NSEvent from CGEvent in this context safely/performantly always?
            // Actually we can:
            if let nsEvent = NSEvent(cgEvent: event) {
                if nsEvent.type == .systemDefined && nsEvent.subtype.rawValue == 8 {
                    let data = nsEvent.data1
                    let keyCode = (data & 0xFFFF0000) >> 16
                    let keyFlags = (data & 0x0000FFFF)
                    let keyState = (keyFlags & 0xFF00) >> 8 // 0xA press, 0xB release
                    let isRepeat = (keyFlags & 0x1) > 0
                    
                    if Int32(keyCode) == NX_KEYTYPE_BRIGHTNESS_UP || Int32(keyCode) == NX_KEYTYPE_BRIGHTNESS_DOWN {
                        if keyState == 0xA { // Key Down
                            let isUp = Int32(keyCode) == NX_KEYTYPE_BRIGHTNESS_UP
                            
                            DispatchQueue.main.async { [weak self] in
                                self?.delegate?.handleBrightnessEvent(up: isUp, isRepeat: isRepeat)
                            }
                            
                            // Return nil to suppress the event
                            return nil
                        }
                        
                        // Also consume key up
                        if keyState == 0xB {
                            return nil
                        }
                    }
                }
            }
        }
        
        // Re-enable if disabled
        if type == .tapDisabledByTimeout {
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}
