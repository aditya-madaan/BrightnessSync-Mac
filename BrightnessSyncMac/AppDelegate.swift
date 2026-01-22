import Cocoa
import Carbon.HIToolbox
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate, BrightnessChangeDelegate {
    
    private var statusItem: NSStatusItem!
    private var brightnessController: BrightnessController!
    private var sliderView: BrightnessSliderView!
    private var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("BrightnessSync: App launching...")
        
        brightnessController = BrightnessController()
        brightnessController.delegate = self
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                button.image = image
                button.image?.isTemplate = true
            } else {
                button.title = "☀️"
            }
        }
        
        setupMenu()
        monitorDisplayChanges()
        
        // Start monitoring Mac brightness for reactive sync
        brightnessController.startMonitoring()
        
        print("BrightnessSync: Ready! Using native F1/F2 keys will sync to monitor.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        brightnessController.stopMonitoring()
    }
    
    // MARK: - BrightnessChangeDelegate
    
    func brightnessDidChange(sliderValue: Float) {
        sliderView?.updateSlider()
    }
    
    private func monitorDisplayChanges() {
        CGDisplayRegisterReconfigurationCallback({ (displayId, flags, userInfo) in
            guard let userInfo = userInfo else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
            
            if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) {
                DispatchQueue.main.async {
                    delegate.handleDisplayChange()
                }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    func handleDisplayChange() {
        print("BrightnessSync: Display changed, syncing...")
        if let menu = statusItem.menu,
           let infoItem = menu.items.first(where: { $0.title.contains("display") }) {
            let displayCount = brightnessController.getDisplayCount()
            infoItem.title = "\(displayCount) display(s) connected"
        }
        // Sync current brightness to new display
        let current = brightnessController.getBrightness()
        brightnessController.setBrightness(current)
    }
    
    // MARK: - Menu Setup
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let headerItem = NSMenuItem(title: "BrightnessSync Mac", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        // Slider
        let sliderItem = NSMenuItem()
        sliderView = BrightnessSliderView(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        sliderView.brightnessController = brightnessController
        sliderView.updateSlider()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)
        menu.addItem(NSMenuItem.separator())
        
        // Status
        let statusInfo = NSMenuItem(title: "Auto-syncs with F1/F2 keys ✓", action: nil, keyEquivalent: "")
        statusInfo.isEnabled = false
        menu.addItem(statusInfo)
        
        let displayCount = brightnessController.getDisplayCount()
        let infoItem = NSMenuItem(title: "\(displayCount) display(s) connected", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Calibration Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        menu.delegate = self
    }
    
    @objc private func openSettings() {
        if settingsWindow == nil {
            createSettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func createSettingsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Calibration Settings"
        window.center()
        window.isReleasedWhenClosed = false
        
        let contentView = NSView(frame: window.contentView!.bounds)
        
        // Title
        let titleLabel = NSTextField(labelWithString: "MacBook Brightness Limits")
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: 150, width: 300, height: 20)
        contentView.addSubview(titleLabel)
        
        let descLabel = NSTextField(wrappingLabelWithString: "Maps slider 0-100% to these MacBook brightness values.\nThe external monitor always uses 0-100%.")
        descLabel.frame = NSRect(x: 20, y: 110, width: 310, height: 40)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        contentView.addSubview(descLabel)
        
        // Min slider
        let minLabel = NSTextField(labelWithString: "Minimum (0%):")
        minLabel.frame = NSRect(x: 20, y: 75, width: 100, height: 20)
        contentView.addSubview(minLabel)
        
        let minSlider = NSSlider(value: Double(brightnessController.macBookCalibration.minBrightness * 100),
                                  minValue: 0, maxValue: 50,
                                  target: self, action: #selector(minSliderChanged(_:)))
        minSlider.frame = NSRect(x: 120, y: 75, width: 150, height: 20)
        minSlider.tag = 1
        contentView.addSubview(minSlider)
        
        let minValueLabel = NSTextField(labelWithString: "\(Int(brightnessController.macBookCalibration.minBrightness * 100))%")
        minValueLabel.frame = NSRect(x: 280, y: 75, width: 50, height: 20)
        minValueLabel.tag = 101
        contentView.addSubview(minValueLabel)
        
        // Max slider
        let maxLabel = NSTextField(labelWithString: "Maximum (100%):")
        maxLabel.frame = NSRect(x: 20, y: 45, width: 100, height: 20)
        contentView.addSubview(maxLabel)
        
        let maxSlider = NSSlider(value: Double(brightnessController.macBookCalibration.maxBrightness * 100),
                                  minValue: 50, maxValue: 100,
                                  target: self, action: #selector(maxSliderChanged(_:)))
        maxSlider.frame = NSRect(x: 120, y: 45, width: 150, height: 20)
        maxSlider.tag = 2
        contentView.addSubview(maxSlider)
        
        let maxValueLabel = NSTextField(labelWithString: "\(Int(brightnessController.macBookCalibration.maxBrightness * 100))%")
        maxValueLabel.frame = NSRect(x: 280, y: 45, width: 50, height: 20)
        maxValueLabel.tag = 102
        contentView.addSubview(maxValueLabel)
        
        // Reset button
        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetCalibration))
        resetButton.frame = NSRect(x: 20, y: 10, width: 120, height: 25)
        contentView.addSubview(resetButton)
        
        window.contentView = contentView
        settingsWindow = window
    }
    
    @objc private func minSliderChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue) / 100.0
        brightnessController.macBookCalibration.minBrightness = value
        
        if let label = settingsWindow?.contentView?.viewWithTag(101) as? NSTextField {
            label.stringValue = "\(Int(sender.doubleValue))%"
        }
    }
    
    @objc private func maxSliderChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue) / 100.0
        brightnessController.macBookCalibration.maxBrightness = value
        
        if let label = settingsWindow?.contentView?.viewWithTag(102) as? NSTextField {
            label.stringValue = "\(Int(sender.doubleValue))%"
        }
    }
    
    @objc private func resetCalibration() {
        brightnessController.macBookCalibration = BrightnessCalibration(minBrightness: 0.20, maxBrightness: 0.80)
        
        if let minSlider = settingsWindow?.contentView?.viewWithTag(1) as? NSSlider {
            minSlider.doubleValue = 20
        }
        if let maxSlider = settingsWindow?.contentView?.viewWithTag(2) as? NSSlider {
            maxSlider.doubleValue = 80
        }
        if let minLabel = settingsWindow?.contentView?.viewWithTag(101) as? NSTextField {
            minLabel.stringValue = "20%"
        }
        if let maxLabel = settingsWindow?.contentView?.viewWithTag(102) as? NSTextField {
            maxLabel.stringValue = "80%"
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        sliderView?.updateSlider()
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
    
    required init?(coder: NSCoder) { super.init(coder: coder); setupViews() }
    
    private func setupViews() {
        let iconSize: CGFloat = 16
        let padding: CGFloat = 12
        let spacing: CGFloat = 8
        let labelWidth: CGFloat = 36
        
        let lowIcon = NSTextField(labelWithString: "🔅")
        lowIcon.font = .systemFont(ofSize: 12)
        lowIcon.frame = NSRect(x: padding, y: (bounds.height - iconSize)/2, width: iconSize, height: iconSize)
        addSubview(lowIcon)
        
        let sliderX = padding + iconSize + spacing
        let sliderWidth = bounds.width - sliderX - spacing - iconSize - spacing - labelWidth - padding
        slider.frame = NSRect(x: sliderX, y: (bounds.height - 21)/2, width: sliderWidth, height: 21)
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        addSubview(slider)
        
        let highIcon = NSTextField(labelWithString: "🔆")
        highIcon.font = .systemFont(ofSize: 12)
        highIcon.frame = NSRect(x: sliderX + sliderWidth + spacing, y: (bounds.height - iconSize)/2, width: iconSize, height: iconSize)
        addSubview(highIcon)
        
        percentageLabel.frame = NSRect(x: highIcon.frame.maxX + spacing, y: (bounds.height - 16)/2, width: labelWidth, height: 16)
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
