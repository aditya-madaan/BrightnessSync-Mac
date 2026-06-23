import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Layout constants (no custom colors — all styling uses native NSColor / NSFont)

private enum L {
    static let popW: CGFloat       = 260
    static let padX: CGFloat       = 14
    static let padY: CGFloat       = 10
    static let rowH: CGFloat       = 22
    static let sectionGap: CGFloat = 12
    static let sepGap: CGFloat     = 10
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, BrightnessChangeDelegate {

    private var statusItem: NSStatusItem!
    private var brightnessController: BrightnessController!
    private var popoverView: TandemPopover!
    private var settingsWindow: NSWindow?
    private var shortcutManager: KeyboardShortcutManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        brightnessController = BrightnessController()
        brightnessController.delegate = self

        shortcutManager = KeyboardShortcutManager()
        shortcutManager.brightnessController = brightnessController
        shortcutManager.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Brightness") {
                btn.image = img
                btn.image?.isTemplate = true
            } else {
                btn.title = "☀️"
            }
        }

        rebuildMenu()
        monitorDisplayChanges()
        brightnessController.startMonitoring()
        checkAccessibilityPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        brightnessController.stopMonitoring()
        shortcutManager.stop()
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermissions() {
        if AXIsProcessTrusted() { shortcutManager.start() }
        else { promptForAccessibility() }
    }

    private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) { shortcutManager.start() }
        else { showAccessibilityAlert(); startAccessibilityPolling() }
    }

    private func showAccessibilityAlert() {
        let a = NSAlert()
        a.messageText     = "Accessibility Access Required"
        a.informativeText = "Tandem needs Accessibility access for keyboard shortcuts (Option+[ / ]).\n\nEnable in System Settings → Privacy & Security → Accessibility."
        a.alertStyle      = .informational
        a.addButton(withTitle: "Open Settings")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] t in
            if AXIsProcessTrusted() {
                t.invalidate()
                self?.shortcutManager.start()
                DispatchQueue.main.async { self?.popoverView?.refreshStatus() }
            }
        }
    }

    // MARK: - BrightnessChangeDelegate
    func brightnessDidChange(sliderValue: Float) { popoverView?.refreshBrightness() }

    // MARK: - Display monitoring

    private func monitorDisplayChanges() {
        CGDisplayRegisterReconfigurationCallback({ _, flags, ui in
            guard let ui else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(ui).takeUnretainedValue()
            if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) {
                DispatchQueue.main.async { me.handleDisplayChange() }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func handleDisplayChange() {
        brightnessController.displaysReconfigured()
        brightnessController.setBrightness(brightnessController.getBrightness())
        rebuildMenu()

        // Some displays aren't ready for gamma/DDC ops at the moment the reconfig
        // callback fires (especially HDMI-through-dock). Re-applying ~1s later catches
        // that — and is a visual no-op if the first attempt already succeeded.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.brightnessController.setBrightness(self.brightnessController.getBrightness())
            self.rebuildMenu()
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Top: custom view (slider + sync + per-display rows + shortcut hint).
        let topItem = NSMenuItem()
        popoverView = TandemPopover(brightnessController: brightnessController)
        topItem.view = popoverView
        menu.addItem(topItem)

        menu.addItem(.separator())

        // m1ddc warning, only when missing.
        if !brightnessController.isM1DDCInstalled {
            let installItem = NSMenuItem(
                title: "Install m1ddc for DDC support…",
                action: #selector(showM1DDCInstallAlert),
                keyEquivalent: ""
            )
            installItem.target = self
            installItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                        accessibilityDescription: nil)
            menu.addItem(installItem)
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(
            title: "Calibration Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit Tandem",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
    }

    @objc private func openSettings() {
        settingsWindow?.close()
        settingsWindow = nil
        createSettingsWindow()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showM1DDCInstallAlert() {
        let alert = NSAlert()
        alert.messageText = "Install m1ddc"
        alert.informativeText = """
        m1ddc enables real backlight control (DDC) for compatible external displays. Without it, Tandem falls back to software dimming (which alters the gamma curve rather than the backlight).

        Run this in Terminal:

            brew install m1ddc

        Then restart Tandem.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Open Terminal")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew install m1ddc", forType: .string)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        default:
            break
        }
    }

    // MARK: - Settings Window

    private func createSettingsWindow() {
        let W: CGFloat = 380

        let content = CalibrationSettingsView(width: W, controller: brightnessController)
        let contentH = content.frame.height

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: W, height: contentH),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = "Calibration Settings"
        win.center()
        win.isReleasedWhenClosed = false
        // No forced appearance — follow system light/dark.

        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: W, height: contentH))
        vfx.material     = .windowBackground
        vfx.blendingMode = .behindWindow
        vfx.state        = .followsWindowActiveState

        vfx.addSubview(content)

        win.contentView = vfx
        settingsWindow = win
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        popoverView?.refreshBrightness()
        popoverView?.refreshStatus()
    }
}

// MARK: - CallbackSlider
// Native NSSlider that fires a closure on change — keeps target/action plumbing local
// to the section that owns the slider, rather than routing through a shared selector.

final class CallbackSlider: NSSlider {
    var onChange: ((Double) -> Void)?

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        onChange?(doubleValue)
        return true
    }
}

// MARK: - TandemPopover (native-styled custom view inside an NSMenuItem)

final class TandemPopover: NSView {

    private let bc: BrightnessController

    private let pctLbl      = NSTextField(labelWithString: "50%")
    private let slider      = CallbackSlider()
    private let syncDot     = NSView()
    private let syncLbl     = NSTextField(labelWithString: "Syncing with F1 / F2")
    private let shortcutLbl = NSTextField(labelWithString: "⌥ [  /  ⌥ ]  shortcuts active")

    init(brightnessController: BrightnessController) {
        self.bc = brightnessController
        super.init(frame: NSRect(x: 0, y: 0, width: L.popW, height: 100))
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        let W = L.popW
        var y: CGFloat = L.padY  // building bottom-up

        // Shortcut info (bottom-most)
        shortcutLbl.font      = .systemFont(ofSize: 11, weight: .regular)
        shortcutLbl.textColor = .tertiaryLabelColor
        shortcutLbl.frame     = NSRect(x: L.padX, y: y, width: W - L.padX*2, height: 14)
        addSubview(shortcutLbl)
        y += 14 + L.sepGap

        // Per-display rows
        let displays = displayRowData()
        for display in displays.reversed() {
            let row = makeDisplayRow(display: display, width: W)
            row.frame = NSRect(x: 0, y: y, width: W, height: L.rowH)
            addSubview(row)
            y += L.rowH
        }
        y += 6

        // Sync status row (green dot + label)
        let syncRow = NSView(frame: NSRect(x: 0, y: y, width: W, height: 16))
        syncDot.wantsLayer = true
        syncDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        syncDot.layer?.cornerRadius    = 4
        syncDot.frame = NSRect(x: L.padX, y: 4, width: 8, height: 8)
        syncRow.addSubview(syncDot)

        syncLbl.font      = .systemFont(ofSize: 12, weight: .regular)
        syncLbl.textColor = .secondaryLabelColor
        syncLbl.frame     = NSRect(x: L.padX + 14, y: 0, width: W - L.padX*2 - 14, height: 16)
        syncRow.addSubview(syncLbl)
        addSubview(syncRow)
        y += 16 + L.sectionGap

        // Native separator
        let sep = NSBox(frame: NSRect(x: L.padX, y: y, width: W - L.padX*2, height: 1))
        sep.boxType = .separator
        addSubview(sep)
        y += 1 + L.sectionGap

        // Brightness slider (native NSSlider)
        slider.minValue     = 0
        slider.maxValue     = 100
        slider.doubleValue  = 50
        slider.isContinuous = true
        slider.controlSize  = .regular
        slider.onChange     = { [weak self] v in
            guard let self else { return }
            self.bc.setBrightness(Float(v / 100.0))
            self.pctLbl.stringValue = "\(Int(v))%"
        }
        slider.frame = NSRect(x: L.padX, y: y, width: W - L.padX*2, height: 20)
        addSubview(slider)
        y += 20 + 4

        // Title row: "Brightness" + percentage
        let titleLbl = NSTextField(labelWithString: "Brightness")
        titleLbl.font      = .systemFont(ofSize: 13, weight: .semibold)
        titleLbl.textColor = .labelColor
        titleLbl.frame     = NSRect(x: L.padX, y: y, width: 120, height: 16)
        addSubview(titleLbl)

        pctLbl.font      = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        pctLbl.textColor = .secondaryLabelColor
        pctLbl.alignment = .right
        pctLbl.frame     = NSRect(x: W - L.padX - 50, y: y, width: 50, height: 16)
        addSubview(pctLbl)

        y += 16 + L.padY

        frame = NSRect(x: 0, y: 0, width: W, height: y)
    }

    private struct DisplayRowData {
        let name: String
        let badge: String
        let badgeColor: NSColor
    }

    private func displayRowData() -> [DisplayRowData] {
        var rows: [DisplayRowData] = []
        rows.append(DisplayRowData(name: "MacBook Display",
                                   badge: "Built-in",
                                   badgeColor: .tertiaryLabelColor))
        for display in bc.externalDisplays() {
            let (badge, color): (String, NSColor)
            switch bc.mode(for: display) {
            case .ddc:     (badge, color) = ("DDC", .systemGreen)
            case .overlay: (badge, color) = ("Software", .systemYellow)
            }
            rows.append(DisplayRowData(name: display.name, badge: badge, badgeColor: color))
        }
        return rows
    }

    private func makeDisplayRow(display: DisplayRowData, width W: CGFloat) -> NSView {
        let row = NSView()

        let nameLbl = NSTextField(labelWithString: display.name)
        nameLbl.font           = .systemFont(ofSize: 12, weight: .regular)
        nameLbl.textColor      = .labelColor
        nameLbl.lineBreakMode  = .byTruncatingTail
        nameLbl.frame          = NSRect(x: L.padX, y: 4, width: W - L.padX*2 - 80, height: 16)
        row.addSubview(nameLbl)

        let badgeLbl = NSTextField(labelWithString: display.badge)
        badgeLbl.font      = .systemFont(ofSize: 11, weight: .medium)
        badgeLbl.textColor = display.badgeColor
        badgeLbl.alignment = .right
        badgeLbl.frame     = NSRect(x: W - L.padX - 70, y: 5, width: 70, height: 14)
        row.addSubview(badgeLbl)

        return row
    }

    func refreshBrightness() {
        let b = bc.getBrightness()
        slider.doubleValue      = Double(b * 100)
        pctLbl.stringValue      = "\(Int(b * 100))%"
    }

    func refreshStatus() {
        let active = AXIsProcessTrusted()
        if active {
            shortcutLbl.stringValue = "⌥ [  /  ⌥ ]  shortcuts active"
            shortcutLbl.textColor   = .tertiaryLabelColor
        } else {
            shortcutLbl.stringValue = "⌥ [  /  ⌥ ]  needs Accessibility access"
            shortcutLbl.textColor   = .systemOrange
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBrightness()
        refreshStatus()
    }
}

// MARK: - CalibrationSettingsView (native widgets)

final class CalibrationSettingsView: NSView {

    private let bc: BrightnessController

    private struct SectionUI {
        let display: Display?  // nil = MacBook
        let minSlider: CallbackSlider
        let maxSlider: CallbackSlider
        let minLbl: NSTextField
        let maxLbl: NSTextField
    }
    private var sectionUIs: [SectionUI] = []

    // Layout
    private let p: CGFloat    = 16
    private let lblW: CGFloat = 110
    private let valW: CGFloat = 36
    private let g2: CGFloat   = 8
    private let g3: CGFloat   = 12
    private let g4: CGFloat   = 16
    private let rowH: CGFloat = 22

    init(width: CGFloat, controller: BrightnessController) {
        self.bc = controller
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        let W = frame.width
        let trackW = W - p*2 - lblW - g2 - valW - g2
        let externals = bc.externalDisplays()
        let actionH: CGFloat = 24

        var y: CGFloat = p

        // Bottom: Reset button
        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetAll))
        resetBtn.bezelStyle  = .rounded
        resetBtn.controlSize = .small
        resetBtn.frame       = NSRect(x: p, y: y, width: 140, height: actionH)
        addSubview(resetBtn)
        y += actionH + g4

        let sepAbove = NSBox(frame: NSRect(x: p, y: y - g4/2, width: W - p*2, height: 1))
        sepAbove.boxType = .separator
        addSubview(sepAbove)

        // External display sections (bottom-up)
        for display in externals.reversed() {
            y = addSection(
                title: display.name,
                badge: badgeFor(mode: bc.mode(for: display)),
                calibration: bc.calibration(for: display),
                display: display,
                at: y,
                W: W,
                trackW: trackW
            )
            y += g3
            let sep = NSBox(frame: NSRect(x: p, y: y - 1, width: W - p*2, height: 1))
            sep.boxType = .separator
            addSubview(sep)
            y += g3
        }

        // MacBook section (top)
        y = addSection(
            title: "MacBook Display",
            badge: ("Built-in", .tertiaryLabelColor),
            calibration: bc.macBookCalibration,
            display: nil,
            at: y,
            W: W,
            trackW: trackW
        )

        y += p

        frame = NSRect(x: 0, y: 0, width: W, height: y)
    }

    private func addSection(title: String,
                            badge: (text: String, color: NSColor),
                            calibration: BrightnessCalibration,
                            display: Display?,
                            at baseY: CGFloat,
                            W: CGFloat,
                            trackW: CGFloat) -> CGFloat {
        var y = baseY + g3

        // Max slider row (visually lower of the two)
        let maxSlider = CallbackSlider()
        let maxLbl = NSTextField(labelWithString: "\(Int(calibration.maxBrightness * 100))%")
        maxLbl.font      = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        maxLbl.textColor = .secondaryLabelColor
        maxLbl.alignment = .right
        maxLbl.frame     = NSRect(x: p + lblW + g2 + trackW + g2, y: y + 4, width: valW, height: 14)
        addSubview(maxLbl)

        maxSlider.minValue     = 0
        maxSlider.maxValue     = 100
        maxSlider.doubleValue  = Double(calibration.maxBrightness * 100)
        maxSlider.isContinuous = true
        maxSlider.controlSize  = .small
        maxSlider.onChange = { [weak self, weak maxLbl] v in
            guard let self else { return }
            maxLbl?.stringValue = "\(Int(v))%"
            self.applyChange(display: display, newMax: Float(v / 100.0))
        }
        maxSlider.frame = NSRect(x: p + lblW + g2, y: y, width: trackW, height: rowH)
        addSubview(maxSlider)

        let maxRowLbl = NSTextField(labelWithString: "Maximum (100%)")
        maxRowLbl.font      = .systemFont(ofSize: 11, weight: .regular)
        maxRowLbl.textColor = .labelColor
        maxRowLbl.frame     = NSRect(x: p, y: y + 4, width: lblW, height: 14)
        addSubview(maxRowLbl)

        y += rowH + g3

        // Min slider row
        let minSlider = CallbackSlider()
        let minLbl = NSTextField(labelWithString: "\(Int(calibration.minBrightness * 100))%")
        minLbl.font      = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        minLbl.textColor = .secondaryLabelColor
        minLbl.alignment = .right
        minLbl.frame     = NSRect(x: p + lblW + g2 + trackW + g2, y: y + 4, width: valW, height: 14)
        addSubview(minLbl)

        minSlider.minValue     = 0
        minSlider.maxValue     = 100
        minSlider.doubleValue  = Double(calibration.minBrightness * 100)
        minSlider.isContinuous = true
        minSlider.controlSize  = .small
        minSlider.onChange = { [weak self, weak minLbl] v in
            guard let self else { return }
            minLbl?.stringValue = "\(Int(v))%"
            self.applyChange(display: display, newMin: Float(v / 100.0))
        }
        minSlider.frame = NSRect(x: p + lblW + g2, y: y, width: trackW, height: rowH)
        addSubview(minSlider)

        let minRowLbl = NSTextField(labelWithString: "Minimum (0%)")
        minRowLbl.font      = .systemFont(ofSize: 11, weight: .regular)
        minRowLbl.textColor = .labelColor
        minRowLbl.frame     = NSRect(x: p, y: y + 4, width: lblW, height: 14)
        addSubview(minRowLbl)

        y += rowH + g3

        // Title + badge row
        let titleLbl = NSTextField(labelWithString: title)
        titleLbl.font          = .systemFont(ofSize: 13, weight: .semibold)
        titleLbl.textColor     = .labelColor
        titleLbl.lineBreakMode = .byTruncatingTail
        titleLbl.frame         = NSRect(x: p, y: y, width: W - p*2 - 90, height: 16)
        addSubview(titleLbl)

        let badgeLbl = NSTextField(labelWithString: badge.text)
        badgeLbl.font      = .systemFont(ofSize: 11, weight: .medium)
        badgeLbl.textColor = badge.color
        badgeLbl.alignment = .right
        badgeLbl.frame     = NSRect(x: W - p - 80, y: y + 1, width: 80, height: 14)
        addSubview(badgeLbl)

        y += 16

        sectionUIs.append(SectionUI(display: display,
                                    minSlider: minSlider, maxSlider: maxSlider,
                                    minLbl: minLbl, maxLbl: maxLbl))
        return y
    }

    private func applyChange(display: Display?, newMin: Float? = nil, newMax: Float? = nil) {
        if let display {
            var cal = bc.calibration(for: display)
            if let newMin { cal.minBrightness = newMin }
            if let newMax { cal.maxBrightness = newMax }
            bc.setCalibration(cal, for: display)
        } else {
            if let newMin { bc.macBookCalibration.minBrightness = newMin }
            if let newMax { bc.macBookCalibration.maxBrightness = newMax }
        }
    }

    private func badgeFor(mode: DisplayControlMode) -> (text: String, color: NSColor) {
        switch mode {
        case .ddc:     return ("DDC", .systemGreen)
        case .overlay: return ("Software", .systemYellow)
        }
    }

    @objc private func resetAll() {
        bc.macBookCalibration = BrightnessCalibration(minBrightness: 0.20, maxBrightness: 0.80)
        bc.resetAllMonitorCalibrations()

        for sec in sectionUIs {
            let cal: BrightnessCalibration
            if let display = sec.display {
                cal = bc.calibration(for: display)
            } else {
                cal = bc.macBookCalibration
            }
            sec.minSlider.doubleValue = Double(cal.minBrightness * 100)
            sec.maxSlider.doubleValue = Double(cal.maxBrightness * 100)
            sec.minLbl.stringValue    = "\(Int(cal.minBrightness * 100))%"
            sec.maxLbl.stringValue    = "\(Int(cal.maxBrightness * 100))%"
        }
        bc.setBrightness(bc.getBrightness())
    }
}
