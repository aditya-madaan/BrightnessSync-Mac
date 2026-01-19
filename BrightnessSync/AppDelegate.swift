import Cocoa
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem!
    private var brightnessController: BrightnessController!
    private var sliderView: BrightnessSliderView!
    private var eventMonitor: Any?
    
    // Brightness step for keyboard shortcuts (10%)
    private let brightnessStep: Float = 0.1
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("BrightnessSync: App launching...")
        
        // Initialize brightness controller
        brightnessController = BrightnessController()
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                button.image = image
                button.image?.isTemplate = true
            } else {
                button.title = "☀️"
            }
        }
        
        // Create menu
        setupMenu()
        
        // Setup keyboard shortcuts
        setupKeyboardShortcuts()
        
        print("BrightnessSync: Ready! Use Option+F1/F2 to adjust brightness")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Remove event monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Header
        let headerItem = NSMenuItem(title: "BrightnessSync", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Add slider view as menu item
        let sliderItem = NSMenuItem()
        sliderView = BrightnessSliderView(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        sliderView.brightnessController = brightnessController
        sliderView.updateSlider()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Shortcuts info
        let shortcutInfo = NSMenuItem(title: "⌥F1 / ⌥F2 to adjust", action: nil, keyEquivalent: "")
        shortcutInfo.isEnabled = false
        menu.addItem(shortcutInfo)
        
        // Display info
        let displayCount = brightnessController.getDisplayCount()
        let infoItem = NSMenuItem(title: "\(displayCount) display(s) connected", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // Quit option
        let quitItem = NSMenuItem(title: "Quit BrightnessSync", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        menu.delegate = self
    }
    
    private func setupKeyboardShortcuts() {
        // Use global event monitor for Option+F1 and Option+F2
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Also monitor local events (when app is focused)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // Check for Option modifier
        guard event.modifierFlags.contains(.option) else { return }
        
        switch event.keyCode {
        case 122: // F1 key
            decreaseBrightness()
        case 120: // F2 key
            increaseBrightness()
        default:
            break
        }
    }
    
    private func increaseBrightness() {
        let current = brightnessController.getBrightness()
        let newLevel = min(1.0, current + brightnessStep)
        brightnessController.setBrightness(newLevel)
        sliderView.updateSlider()
        showBrightnessOSD(level: newLevel)
        print("BrightnessSync: Brightness increased to \(Int(newLevel * 100))%")
    }
    
    private func decreaseBrightness() {
        let current = brightnessController.getBrightness()
        let newLevel = max(0.0, current - brightnessStep)
        brightnessController.setBrightness(newLevel)
        sliderView.updateSlider()
        showBrightnessOSD(level: newLevel)
        print("BrightnessSync: Brightness decreased to \(Int(newLevel * 100))%")
    }
    
    private func showBrightnessOSD(level: Float) {
        // Show a brief notification-style feedback
        // We could use a custom OSD window here, but for simplicity we'll just update the menu bar
        if let button = statusItem.button {
            let percentage = Int(level * 100)
            button.title = "\(percentage)%"
            
            // Reset to icon after 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                    button.title = ""
                    button.image = image
                    button.image?.isTemplate = true
                } else {
                    button.title = "☀️"
                }
            }
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        sliderView.updateSlider()
        
        if let infoItem = menu.items.first(where: { $0.title.contains("display") }) {
            let displayCount = brightnessController.getDisplayCount()
            infoItem.title = "\(displayCount) display(s) connected"
        }
    }
}

// MARK: - BrightnessSliderView

class BrightnessSliderView: NSView {
    
    var brightnessController: BrightnessController?
    
    private let slider: NSSlider = {
        let slider = NSSlider()
        slider.minValue = 0
        slider.maxValue = 100
        slider.sliderType = .linear
        slider.isContinuous = true
        return slider
    }()
    
    private let lowBrightnessIcon: NSTextField = {
        let label = NSTextField(labelWithString: "🔅")
        label.font = NSFont.systemFont(ofSize: 12)
        return label
    }()
    
    private let highBrightnessIcon: NSTextField = {
        let label = NSTextField(labelWithString: "🔆")
        label.font = NSFont.systemFont(ofSize: 12)
        return label
    }()
    
    private let percentageLabel: NSTextField = {
        let label = NSTextField(labelWithString: "100%")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        let iconSize: CGFloat = 16
        let padding: CGFloat = 12
        let spacing: CGFloat = 8
        let labelWidth: CGFloat = 36
        
        lowBrightnessIcon.frame = NSRect(x: padding, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        addSubview(lowBrightnessIcon)
        
        let sliderX = padding + iconSize + spacing
        let sliderWidth = bounds.width - sliderX - spacing - iconSize - spacing - labelWidth - padding
        slider.frame = NSRect(x: sliderX, y: (bounds.height - 21) / 2, width: sliderWidth, height: 21)
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        addSubview(slider)
        
        let highIconX = sliderX + sliderWidth + spacing
        highBrightnessIcon.frame = NSRect(x: highIconX, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        addSubview(highBrightnessIcon)
        
        let labelX = highIconX + iconSize + spacing
        percentageLabel.frame = NSRect(x: labelX, y: (bounds.height - 16) / 2, width: labelWidth, height: 16)
        addSubview(percentageLabel)
    }
    
    func updateSlider() {
        let brightness = brightnessController?.getBrightness() ?? 0.5
        slider.doubleValue = Double(brightness * 100)
        percentageLabel.stringValue = "\(Int(brightness * 100))%"
    }
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue / 100.0)
        brightnessController?.setBrightness(value)
        percentageLabel.stringValue = "\(Int(sender.doubleValue))%"
    }
}
