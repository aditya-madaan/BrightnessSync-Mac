import Cocoa
import CoreGraphics

protocol MediaKeyDelegate: AnyObject {
    func handleBrightnessEvent(up: Bool, isRepeat: Bool)
}

class MediaKeyManager {
    
    weak var delegate: MediaKeyDelegate?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // NX Keycodes
    private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
    private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
    
    // CGEventType.nxSystemDefined value
    private let kCGEventNXSystemDefined: CGEventType = CGEventType(rawValue: 14)!
    
    func start() {
        // Create an event tap to intercept system keys
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
            print("MediaKeyManager: Failed to create event tap")
            return
        }
        
        self.eventTap = tap
        
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("MediaKeyManager: Tap disabled, re-enabling...")
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        if type == kCGEventNXSystemDefined {
            // Use NSEvent to parse the system defined event data easily
            if let nsEvent = NSEvent(cgEvent: event) {
                // Check if it is a system defined special key event (subtype 8)
                if nsEvent.subtype.rawValue == 8 {
                    let data = nsEvent.data1
                    let keyCode = (data & 0xFFFF0000) >> 16
                    let keyFlags = (data & 0x0000FFFF)
                    let keyState = (keyFlags & 0xFF00) >> 8
                    let isRepeat = (keyFlags & 0x1) > 0
                    
                    if Int32(keyCode) == NX_KEYTYPE_BRIGHTNESS_UP || Int32(keyCode) == NX_KEYTYPE_BRIGHTNESS_DOWN {
                        
                        // Key Down (0xA) or Key Repeat
                        if keyState == 0xA {
                            let isUp = Int32(keyCode) == NX_KEYTYPE_BRIGHTNESS_UP
                            
                            // Perform action on main thread
                            DispatchQueue.main.async { [weak self] in
                                self?.delegate?.handleBrightnessEvent(up: isUp, isRepeat: isRepeat)
                            }
                            
                            // Return nil to SUPPRESS the event so macOS doesn't show its overlay
                            // or change the native brightness on top of our change
                            print("MediaKeyManager: Intercepted brightness key")
                            return nil
                        }
                        
                        // Key Up (0xB) - also suppress to finish the stroke cleanly
                        if keyState == 0xB {
                            return nil
                        }
                    }
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}
