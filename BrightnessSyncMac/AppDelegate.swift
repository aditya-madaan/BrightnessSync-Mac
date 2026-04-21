import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Design Tokens (macOS Tahoe / Liquid Glass — from BrightnessSync.html)
private enum DS {
    // Amber brand
    static let primary       = NSColor(srgbRed: 0.957, green: 0.753, blue: 0.145, alpha: 1.00) // #f4c025
    static let primaryGrad   = NSColor(srgbRed: 0.961, green: 0.620, blue: 0.043, alpha: 1.00) // #f59e0b
    static let primaryDim    = NSColor(srgbRed: 0.957, green: 0.753, blue: 0.145, alpha: 0.16) // AMBER_DIM

    // Liquid Glass surfaces (dark)
    static let glassBase     = NSColor(srgbRed: 0.110, green: 0.102, blue: 0.086, alpha: 0.55) // rgba(28,26,22,.55)
    static let glassBorder   = NSColor(white: 1.0, alpha: 0.18)   // rgba(255,255,255,.18)
    static let glassHighlight = NSColor(white: 1.0, alpha: 0.07)  // rgba(255,255,255,.07)
    static let cardGlass     = NSColor(white: 1.0, alpha: 0.07)   // rgba(255,255,255,.07)
    static let cardBorder    = NSColor(white: 1.0, alpha: 0.12)   // rgba(255,255,255,.12)

    // Text (dark mode)
    static let textPrimary   = NSColor(white: 1.0, alpha: 0.92)   // label
    static let textMuted     = NSColor(white: 1.0, alpha: 0.55)   // labelSec
    static let textTer       = NSColor(white: 1.0, alpha: 0.28)   // labelTer

    // Status
    static let emerald       = NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1) // #30d158
    static let orange        = NSColor(srgbRed: 1.000, green: 0.584, blue: 0.000, alpha: 1) // #ff9500
    static let textRed       = NSColor(srgbRed: 1.000, green: 0.231, blue: 0.188, alpha: 1) // #ff3b30

    // Separator / track
    static let divider       = NSColor(white: 1.0, alpha: 0.10)
    static let trackBg       = NSColor(white: 1.0, alpha: 0.13)

    // Hover fills
    static let bgCardHoverAmber = NSColor(srgbRed: 0.957, green: 0.753, blue: 0.145, alpha: 0.16)
    static let bgCardHoverRed   = NSColor(srgbRed: 1.000, green: 0.231, blue: 0.188, alpha: 0.18)

    // Layout constants
    static let popW: CGFloat     = 280
    static let px: CGFloat       = 16
    static let badgePx: CGFloat  = 10
    static let badgeGap: CGFloat = 7   // gap between badges (design: 7px)
    static let sectionGap: CGFloat = 16

    static func body(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
    static var mono: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .semibold) }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, BrightnessChangeDelegate {

    private var statusItem: NSStatusItem!
    private var brightnessController: BrightnessController!
    private var popoverView: BrightnessSyncPopover!
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
                btn.image = img; btn.image?.isTemplate = true
            } else { btn.title = "☀️" }
        }

        setupMenu()
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
        a.informativeText = "BrightnessSync needs Accessibility access for keyboard shortcuts (Option+[ / ]).\n\nEnable in System Settings → Privacy & Security → Accessibility."
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
        brightnessController.setBrightness(brightnessController.getBrightness())
        popoverView?.refreshStatus()
    }

    // MARK: - Menu
    private func setupMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        popoverView = BrightnessSyncPopover(
            brightnessController: brightnessController,
            onSettings: { [weak self] in self?.openSettings() },
            onQuit:     { NSApp.terminate(nil) }
        )
        item.view = popoverView
        menu.addItem(item)
        statusItem.menu = menu
        menu.delegate   = self
    }

    @objc private func openSettings() {
        if settingsWindow == nil { createSettingsWindow() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings Window
    private func createSettingsWindow() {
        // w-[350px], glassmorphic bg-black/40 backdrop-blur-xl, border border-white/10
        // NSWindow title bar is ~28px; content height ~220px → total ~248px
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "Calibration Settings"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.center()
        win.isReleasedWhenClosed = false
        win.appearance = NSAppearance(named: .darkAqua)

        // Liquid Glass: vibrancy + warm glass overlay
        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 390, height: 220))
        vfx.material     = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state        = .active

        let warmOverlay = NSView(frame: vfx.bounds)
        warmOverlay.wantsLayer             = true
        warmOverlay.layer?.backgroundColor = DS.glassBase.cgColor
        vfx.addSubview(warmOverlay)

        // Glass title bar (38pt) with traffic lights + centred title
        let titleBar = NSView(frame: NSRect(x: 0, y: 182, width: 390, height: 38))
        titleBar.wantsLayer             = true
        titleBar.layer?.backgroundColor = DS.glassHighlight.cgColor

        let trafficColors: [NSColor] = [
            NSColor(srgbRed: 1.0, green: 0.451, blue: 0.416, alpha: 1),
            NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1),
            NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 1),
        ]
        for (i, c) in trafficColors.enumerated() {
            let dot = NSView(frame: NSRect(x: 14 + i * 20, y: 13, width: 12, height: 12))
            dot.wantsLayer             = true
            dot.layer?.backgroundColor = c.cgColor
            dot.layer?.cornerRadius    = 6
            dot.layer?.borderWidth     = 0.5
            dot.layer?.borderColor     = NSColor(white: 0, alpha: 0.18).cgColor
            titleBar.addSubview(dot)
        }

        let titleLbl = NSTextField(labelWithString: "Calibration Settings")
        titleLbl.font      = DS.body(13, weight: .semibold)
        titleLbl.textColor = DS.textPrimary
        titleLbl.alignment = .center
        titleLbl.frame     = NSRect(x: 80, y: 10, width: 230, height: 18)
        titleBar.addSubview(titleLbl)

        let sep = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 1))
        sep.wantsLayer             = true
        sep.layer?.backgroundColor = DS.divider.cgColor
        titleBar.addSubview(sep)
        vfx.addSubview(titleBar)

        // Glass content card
        let contentCard = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 182))
        contentCard.wantsLayer             = true
        contentCard.layer?.backgroundColor = DS.cardGlass.cgColor

        let content = CalibrationSettingsView(
            frame: NSRect(x: 0, y: 0, width: 390, height: 182),
            controller: brightnessController
        )
        contentCard.addSubview(content)
        vfx.addSubview(contentCard)

        win.setContentSize(NSSize(width: 390, height: 220))
        win.contentView = vfx
        settingsWindow = win
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        popoverView?.refreshBrightness()
        popoverView?.refreshStatus()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - BrightnessSyncPopover
// Matches Stitch HTML layout exactly
// ═══════════════════════════════════════════════════════════

final class BrightnessSyncPopover: NSView {

    // Public refresh
    private let bc: BrightnessController
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    private let pctLabel   = NSTextField(labelWithString: "50%")
    private let slider     = StitchSlider()
    private let kbBadge    = BadgeCard()
    private let dispBadge  = BadgeCard()

    // Total height: header(46) + divider(1) + content(badge3*34+2*8+brightness50+gap16+padding24) + divider(1) + menu(72)
    private static let totalH: CGFloat = 330

    init(brightnessController: BrightnessController,
         onSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.bc         = brightnessController
        self.onSettings = onSettings
        self.onQuit     = onQuit
        super.init(frame: NSRect(x: 0, y: 0, width: DS.popW, height: Self.totalH))
        wantsLayer = true
        layer?.cornerRadius    = 14
        layer?.masksToBounds   = true

        // Liquid Glass base: vibrancy backdrop + warm tint overlay
        let vfx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: DS.popW, height: Self.totalH))
        vfx.material     = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state        = .active
        vfx.autoresizingMask = [.width, .height]
        addSubview(vfx)

        let tint = NSView(frame: vfx.bounds)
        tint.wantsLayer             = true
        tint.layer?.backgroundColor = DS.glassBase.cgColor
        tint.autoresizingMask       = [.width, .height]
        addSubview(tint)

        // Edge specular highlight (top edge)
        let highlight = NSView(frame: NSRect(x: 0, y: frame.height - 1, width: DS.popW, height: 1))
        highlight.wantsLayer             = true
        highlight.layer?.backgroundColor = DS.glassHighlight.cgColor
        highlight.autoresizingMask       = [.width]
        addSubview(highlight)

        // Glass border ring
        layer?.borderWidth = 0.75
        layer?.borderColor = DS.glassBorder.cgColor

        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        let W  = DS.popW       // 280
        let px = DS.px         // 16
        var y: CGFloat = 0     // building from BOTTOM up

        // ─── Menu Section (bottom) ────────────────────────
        // py-1 (4pt) + two buttons(30pt each) + gap(2pt) + py-1(4pt) = 70pt
        let menuTopPad:    CGFloat = 4
        let menuBotPad:    CGFloat = 4
        let menuItemH:     CGFloat = 30
        let menuPx:        CGFloat = 4   // px-1

        // Quit button
        y += menuBotPad
        let quitBtn = MenuItemRow(title: "Quit BrightnessSync",
                                  rightText: "⌘Q",
                                  hoverColor: DS.bgCardHoverRed,
                                  hoverTextColor: DS.textRed)
        quitBtn.frame = NSRect(x: menuPx, y: y, width: W - menuPx*2, height: menuItemH)
        quitBtn.onTap = { [weak self] in self?.onQuit() }
        addSubview(quitBtn)
        y += menuItemH + 2 // mt-0.5

        // Settings button
        let settingsBtn = MenuItemRow(title: "Calibration Settings…",
                                      sfRightIcon: "gearshape",
                                      hoverColor: DS.primaryDim,
                                      hoverTextColor: DS.primary)
        settingsBtn.frame = NSRect(x: menuPx, y: y, width: W - menuPx*2, height: menuItemH)
        settingsBtn.onTap = { [weak self] in self?.onSettings() }
        addSubview(settingsBtn)
        y += menuItemH + menuTopPad

        // ─── Full-width divider ───────────────────────────
        addDivider(y: y, width: W)
        y += 1

        // ─── Content Section ──────────────────────────────
        // py-3 = 12pt top (added at end) + py-3 = 12pt bottom (add now)
        y += 12 // bottom py-3

        // Display badge
        dispBadge.setIcon(sfSymbol: "display", text: "1 display connected")
        dispBadge.frame = NSRect(x: px, y: y, width: W - px*2, height: 28)
        addSubview(dispBadge)
        y += 28 + DS.badgeGap

        // Keyboard badge
        kbBadge.setIcon(sfSymbol: "keyboard", text: "⌥[ / ] shortcuts active")
        kbBadge.frame = NSRect(x: px, y: y, width: W - px*2, height: 28)
        addSubview(kbBadge)
        y += 28 + DS.badgeGap

        // Sync badge (green dot only, no icon)
        let syncBadge = SyncBadgeCard(text: "Syncing with F1 / F2")
        syncBadge.frame = NSRect(x: px, y: y, width: W - px*2, height: 28)
        addSubview(syncBadge)
        y += 28

        // gap-4 between badges and brightness
        y += DS.sectionGap  // 16

        // Slider row
        slider.frame = NSRect(x: px, y: y, width: W - px*2, height: 24)
        slider.onChanged = { [weak self] val in
            guard let self else { return }
            self.bc.setBrightness(Float(val / 100.0))
            self.pctLabel.stringValue = "\(Int(val))%"
        }
        addSubview(slider)
        y += 24 + 8  // gap-2

        // Brightness label row: "Brightness" (left) + "72%" (right)
        let bLabel = makeText("Brightness", font: DS.body(11, weight: .medium), color: DS.textMuted)
        bLabel.frame = NSRect(x: px, y: y, width: 100, height: 15)
        addSubview(bLabel)

        pctLabel.font      = DS.mono
        pctLabel.textColor = DS.primary
        pctLabel.alignment = .right
        pctLabel.frame     = NSRect(x: W - px - 48, y: y, width: 48, height: 15)
        addSubview(pctLabel)
        y += 15

        // Top py-3 padding
        y += 12

        // ─── Full-width divider ───────────────────────────
        addDivider(y: y, width: W)
        y += 1

        // ─── Header Section ───────────────────────────────
        // header: 42pt tall, pb-2 (8pt) + icon(28pt) centre = y+7 for icon, then pt-3(gap to divider)
        y += 7  // bottom pad

        // Sun icon glass pill — 28×28, LiquidGlass bubble
        let pillW: CGFloat = 28
        let pill = NSView(frame: NSRect(x: px, y: y, width: pillW, height: pillW))
        pill.wantsLayer             = true
        pill.layer?.cornerRadius    = 10
        pill.layer?.backgroundColor = DS.cardGlass.cgColor
        pill.layer?.borderWidth     = 0.75
        pill.layer?.borderColor     = DS.cardBorder.cgColor

        let sunView = NSImageView()
        let sunCfg  = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        if let img = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(sunCfg) {
            sunView.image = img
        }
        sunView.contentTintColor = DS.primary
        sunView.imageScaling     = .scaleProportionallyUpOrDown
        sunView.frame            = NSRect(x: 6, y: 6, width: 16, height: 16)
        pill.addSubview(sunView)
        addSubview(pill)

        let titleField = makeText("BrightnessSync", font: DS.body(13, weight: .semibold), color: DS.textPrimary)
        titleField.frame = NSRect(x: px + pillW + 8, y: y + 5, width: 180, height: 18)
        addSubview(titleField)
        y += pillW + 7  // top pad to reach total header ~42pt

        // Resize self to actual content height
        let finalH = y
        frame = NSRect(x: 0, y: 0, width: W, height: finalH)
    }

    @discardableResult
    private func addDivider(y: CGFloat, width: CGFloat) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: y, width: width, height: 1))
        v.wantsLayer             = true
        v.layer?.backgroundColor = DS.divider.cgColor
        addSubview(v)
        return v
    }

    private func makeText(_ s: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: s); f.font = font; f.textColor = color; return f
    }

    // ─── Refresh ─────────────────────────────────────────
    func refreshBrightness() {
        let b = bc.getBrightness()
        slider.setValue(Double(b * 100))
        pctLabel.stringValue = "\(Int(b * 100))%"
    }

    func refreshStatus() {
        let active = AXIsProcessTrusted()
        kbBadge.setText(active ? "⌥[ / ] shortcuts active" : "⌥[ / ] needs permissions")

        let count = bc.getDisplayCount()
        dispBadge.setText("\(count) display\(count == 1 ? "" : "s") connected")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBrightness()
        refreshStatus()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - StitchSlider  (matches Stitch CSS slider)
// ═══════════════════════════════════════════════════════════

final class StitchSlider: NSView {

    var onChanged: ((Double) -> Void)?
    private(set) var value: Double = 50

    // Layers
    private let trackBg   = CALayer()
    private let trackFill = CAGradientLayer()
    private let thumb     = CALayer()

    override var isFlipped: Bool { false }

    override init(frame: NSRect) { super.init(frame: frame); setupLayers() }
    required init?(coder: NSCoder) { super.init(coder: coder); setupLayers() }

    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // h-1.5 track = 6px, rounded-full, dark bg
        trackBg.cornerRadius    = 3
        trackBg.backgroundColor = DS.trackBg.cgColor
        layer?.addSublayer(trackBg)

        // amber gradient fill + glow shadow
        trackFill.colors      = [DS.primaryGrad.cgColor, DS.primary.cgColor]
        trackFill.shadowColor  = DS.primary.cgColor
        trackFill.shadowRadius = 4
        trackFill.shadowOpacity = 0.40
        trackFill.shadowOffset  = .zero
        trackFill.startPoint  = CGPoint(x: 0, y: 0.5)
        trackFill.endPoint    = CGPoint(x: 1, y: 0.5)
        trackFill.cornerRadius = 3
        layer?.addSublayer(trackFill)

        // w-4 h-4 white thumb, shadow, rounded-full
        thumb.cornerRadius    = 8  // 16px thumb → r=8
        thumb.backgroundColor = NSColor.white.cgColor
        thumb.shadowColor     = NSColor.black.cgColor
        thumb.shadowRadius    = 3
        thumb.shadowOpacity   = 0.25
        thumb.shadowOffset    = CGSize(width: 0, height: -1)
        // border: border-slate-600
        thumb.borderWidth     = 0.5
        thumb.borderColor     = NSColor(white: 0.6, alpha: 0.5).cgColor
        layer?.addSublayer(thumb)
    }

    override func layout() {
        super.layout()
        positionLayers()
    }

    func setValue(_ v: Double) {
        value = max(0, min(100, v))
        positionLayers()
    }

    private func positionLayers() {
        guard bounds.width > 0 else { return }

        let tH: CGFloat  = 6   // h-1.5 = 6px
        let tD: CGFloat  = 16  // w-4 h-4 = 16px
        let tY: CGFloat  = (bounds.height - tH) / 2
        let tY2: CGFloat = (bounds.height - tD) / 2
        let usable       = bounds.width - tD
        let thumbX       = CGFloat(value / 100.0) * usable
        let fillW        = max(tH, thumbX + tD / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackBg.frame   = CGRect(x: 0,      y: tY,  width: bounds.width, height: tH)
        trackFill.frame = CGRect(x: 0,      y: tY,  width: fillW,        height: tH)
        thumb.frame     = CGRect(x: thumbX, y: tY2, width: tD,           height: tD)
        CATransaction.commit()
    }

    // Mouse drag
    override func mouseDown(with e: NSEvent)    { handleDrag(e) }
    override func mouseDragged(with e: NSEvent) { handleDrag(e) }
    override func mouseUp(with e: NSEvent)      { handleDrag(e) }

    private func handleDrag(_ e: NSEvent) {
        let tD: CGFloat = 16
        let x   = convert(e.locationInWindow, from: nil).x
        let raw = (x - tD / 2) / (bounds.width - tD) * 100
        value   = max(0, min(100, raw))
        positionLayers()
        onChanged?(value)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - BadgeCard  (icon + label, rounded dark bg)
// Matches: flex items-center gap-2 px-2.5 py-1.5 rounded-md bg-slate-800/50
// ═══════════════════════════════════════════════════════════

final class BadgeCard: NSView {

    private let iconView = NSImageView()
    private let label    = NSTextField(labelWithString: "")

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { super.init(coder: coder); build() }

    private func build() {
        wantsLayer             = true
        layer?.backgroundColor = DS.cardGlass.cgColor
        layer?.cornerRadius    = 10
        layer?.borderWidth     = 0.75
        layer?.borderColor     = DS.cardBorder.cgColor

        // gap-2 = 8px, px-2.5 = 10px, py-1.5 = 6px
        // icon 16×16 at x=10, centered vertically
        iconView.imageScaling  = .scaleProportionallyUpOrDown
        iconView.frame         = NSRect(x: 10, y: 8, width: 14, height: 14)
        addSubview(iconView)

        label.font      = DS.body(11, weight: .medium)
        label.textColor = DS.textPrimary
        label.frame     = NSRect(x: 32, y: 7, width: 200, height: 14)
        addSubview(label)
    }

    func setIcon(sfSymbol: String, text: String) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if let img = NSImage(systemSymbolName: sfSymbol, accessibilityDescription: nil)?
                        .withSymbolConfiguration(cfg) {
            iconView.image            = img
            iconView.contentTintColor = DS.textMuted
        }
        label.stringValue = text
    }

    func setText(_ t: String) { label.stringValue = t }
}

// ═══════════════════════════════════════════════════════════
// MARK: - SyncBadgeCard  (green dot + label)
// ═══════════════════════════════════════════════════════════

final class SyncBadgeCard: NSView {

    private let dot   = NSView()
    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        build(text: text)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(text: String) {
        wantsLayer             = true
        layer?.backgroundColor = DS.cardGlass.cgColor
        layer?.cornerRadius    = 10
        layer?.borderWidth     = 0.75
        layer?.borderColor     = DS.cardBorder.cgColor

        // 8×8 dot with glow — #30d158
        dot.wantsLayer             = true
        dot.layer?.backgroundColor = DS.emerald.cgColor
        dot.layer?.cornerRadius    = 4
        dot.layer?.shadowColor     = DS.emerald.cgColor
        dot.layer?.shadowRadius    = 3
        dot.layer?.shadowOpacity   = 0.60
        dot.layer?.shadowOffset    = .zero
        dot.frame                  = NSRect(x: 10, y: 10, width: 8, height: 8)
        addSubview(dot)

        label.font        = DS.body(11, weight: .medium)
        label.textColor   = DS.textPrimary
        label.stringValue = text
        label.frame       = NSRect(x: 26, y: 7, width: 210, height: 14)
        addSubview(label)
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - MenuItemRow
// Matches: flex items-center justify-between px-3 py-1.5 text-sm rounded hover:...
// ═══════════════════════════════════════════════════════════

final class MenuItemRow: NSView {

    var onTap: (() -> Void)?
    private let titleLabel    = NSTextField(labelWithString: "")
    private let rightLabel    = NSTextField(labelWithString: "")
    private let rightIconView = NSImageView()
    private let hoverColor: NSColor
    private let hoverTextColor: NSColor
    private var tracking: NSTrackingArea?

    init(title: String,
         rightText: String? = nil,
         sfRightIcon: String? = nil,
         hoverColor: NSColor,
         hoverTextColor: NSColor) {
        self.hoverColor     = hoverColor
        self.hoverTextColor = hoverTextColor
        super.init(frame: .zero)
        wantsLayer        = true
        layer?.cornerRadius = 8

        titleLabel.font        = DS.body(13)
        titleLabel.textColor   = DS.textPrimary
        titleLabel.stringValue = title
        titleLabel.frame       = NSRect(x: 12, y: 7, width: 200, height: 14)
        addSubview(titleLabel)

        if let txt = rightText {
            rightLabel.font        = DS.body(11)
            rightLabel.textColor   = DS.textMuted
            rightLabel.stringValue = txt
            rightLabel.alignment   = .right
            rightLabel.frame       = NSRect(x: DS.popW - 12 - 40, y: 8, width: 40, height: 14)
            addSubview(rightLabel)
        }

        if let sym = sfRightIcon,
           let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?
                       .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) {
            rightIconView.image            = img
            rightIconView.contentTintColor = DS.textMuted
            rightIconView.imageScaling     = .scaleProportionallyUpOrDown
            rightIconView.frame            = NSRect(x: DS.popW - 12 - 20, y: 8, width: 14, height: 14)
            addSubview(rightIconView)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    private func setHovered(_ on: Bool) {
        layer?.backgroundColor = on ? hoverColor.cgColor : NSColor.clear.cgColor
        titleLabel.textColor   = on ? hoverTextColor : DS.textPrimary
    }

    override func mouseEntered(with e: NSEvent) { setHovered(true)  }
    override func mouseExited(with e: NSEvent)  { setHovered(false) }
    override func mouseUp(with e: NSEvent) {
        setHovered(false)
        onTap?()
        enclosingMenuItem?.menu?.cancelTracking()
    }
}

// ═══════════════════════════════════════════════════════════
// MARK: - CalibrationSettingsView
// Matches Stitch HTML: w-[350px], p-4, gap-4 sections,
// flat slider rows (label w-24 | track+thumb | value w-6),
// border-t bottom row: Reset btn (left) | ⌥[ ⌥] pills (right)
// ═══════════════════════════════════════════════════════════

final class CalibrationSettingsView: NSView {

    private let bc: BrightnessController
    private let minSlider = StitchSlider()
    private let maxSlider = StitchSlider()
    private let minLbl    = NSTextField(labelWithString: "20%")
    private let maxLbl    = NSTextField(labelWithString: "80%")

    init(frame: NSRect, controller: BrightnessController) {
        self.bc = controller
        super.init(frame: frame)
        wantsLayer = true
        // Transparent — NSVisualEffectView behind us provides the blur
        layer?.backgroundColor = NSColor.clear.cgColor
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        let W:    CGFloat = 390
        let p:    CGFloat = 16
        let g4:   CGFloat = 16
        let g3:   CGFloat = 12
        let lblW: CGFloat = 104   // w-26 (design: 104px)
        let valW: CGFloat = 26
        let g2:   CGFloat = 8
        let rowH: CGFloat = 24
        let actH: CGFloat = 22
        let actTopSpace: CGFloat = 1 + 16 + 8   // sep + pt-4 + mt-2

        var y: CGFloat = p

        // ── Bottom row ────────────────────────────────────────
        let resetBtn = SmallOutlineButton(title: "Reset to Defaults",
                                          target: self, action: #selector(resetCalibration))
        resetBtn.frame = NSRect(x: p, y: y, width: 116, height: actH)
        addSubview(resetBtn)

        let pill2 = makePill("⌥]")
        pill2.frame = NSRect(x: W - p - 36, y: y + 2, width: 36, height: 18)
        addSubview(pill2)

        let pill1 = makePill("⌥[")
        pill1.frame = NSRect(x: W - p - 36 - 6 - 36, y: y + 2, width: 36, height: 18)
        addSubview(pill1)

        y += actH + actTopSpace

        // Full-width separator
        let sep = NSView(frame: NSRect(x: p, y: y - 1, width: W - p*2, height: 1))
        sep.wantsLayer             = true
        sep.layer?.backgroundColor = DS.divider.cgColor
        addSubview(sep)

        // ── Max slider row ────────────────────────────────────
        y += g3
        let trackW = W - p*2 - lblW - g2 - valW - g2

        maxLbl.font        = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        maxLbl.textColor   = DS.textMuted
        maxLbl.alignment   = .right
        maxLbl.stringValue = "\(Int(bc.macBookCalibration.maxBrightness * 100))%"
        maxLbl.frame       = NSRect(x: p + lblW + g2 + trackW + g2, y: y + 5, width: valW, height: 14)
        addSubview(maxLbl)

        maxSlider.frame = NSRect(x: p + lblW + g2, y: y, width: trackW, height: rowH)
        maxSlider.setValue(Double(bc.macBookCalibration.maxBrightness * 100))
        maxSlider.onChanged = { [weak self] v in
            guard let self else { return }
            self.bc.macBookCalibration.maxBrightness = Float(v / 100)
            self.maxLbl.stringValue = "\(Int(v))%"
        }
        addSubview(maxSlider)

        let maxLbl2 = lbl("Maximum (100%)", font: DS.body(11, weight: .medium), color: DS.textPrimary)
        maxLbl2.frame = NSRect(x: p, y: y + 5, width: lblW, height: 14)
        addSubview(maxLbl2)
        y += rowH

        // ── Min slider row ────────────────────────────────────
        y += g3

        minLbl.font        = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        minLbl.textColor   = DS.textMuted
        minLbl.alignment   = .right
        minLbl.stringValue = "\(Int(bc.macBookCalibration.minBrightness * 100))%"
        minLbl.frame       = NSRect(x: p + lblW + g2 + trackW + g2, y: y + 5, width: valW, height: 14)
        addSubview(minLbl)

        minSlider.frame = NSRect(x: p + lblW + g2, y: y, width: trackW, height: rowH)
        minSlider.setValue(Double(bc.macBookCalibration.minBrightness * 100))
        minSlider.onChanged = { [weak self] v in
            guard let self else { return }
            self.bc.macBookCalibration.minBrightness = Float(v / 100)
            self.minLbl.stringValue = "\(Int(v))%"
        }
        addSubview(minSlider)

        let minLbl2 = lbl("Minimum (0%)", font: DS.body(11, weight: .medium), color: DS.textPrimary)
        minLbl2.frame = NSRect(x: p, y: y + 5, width: lblW, height: 14)
        addSubview(minLbl2)
        y += rowH + g4

        // ── Description ───────────────────────────────────────
        let desc = NSTextField(wrappingLabelWithString: "Adjust the brightness range mapped to your external display.")
        desc.font      = DS.body(10)
        desc.textColor = DS.textMuted
        desc.frame     = NSRect(x: p, y: y, width: W - p*2, height: 14)
        addSubview(desc)
        y += 18

        // ── Section heading ───────────────────────────────────
        let heading = lbl("MacBook Brightness Limits", font: DS.body(13, weight: .semibold), color: DS.textPrimary)
        heading.frame = NSRect(x: p, y: y, width: W - p*2, height: 18)
        addSubview(heading)
    }

    // Helpers
    private func lbl(_ s: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: s); f.font = font; f.textColor = color; return f
    }

    private func makePill(_ text: String) -> NSView {
        let v = NSView()
        v.wantsLayer             = true
        v.layer?.backgroundColor = DS.cardGlass.cgColor
        v.layer?.cornerRadius    = 5
        v.layer?.borderWidth     = 0.75
        v.layer?.borderColor     = DS.cardBorder.cgColor
        let l = NSTextField(labelWithString: text)
        l.font      = .monospacedSystemFont(ofSize: 10, weight: .regular)
        l.textColor = DS.textMuted
        l.alignment = .center
        l.frame     = NSRect(x: 2, y: 2, width: 32, height: 14)
        v.addSubview(l)
        return v
    }

    @objc private func resetCalibration() {
        bc.macBookCalibration = BrightnessCalibration(minBrightness: 0.20, maxBrightness: 0.80)
        minSlider.setValue(20); maxSlider.setValue(80)
        minLbl.stringValue = "20%"; maxLbl.stringValue = "80%"
    }
}

// ─── SmallOutlineButton (matches Stitch 'Reset to Defaults' style) ────────────
// text-[10px] px-2 py-1 rounded border border-white/10 hover:text-slate-200
final class SmallOutlineButton: NSView {
    private let label = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private let action: Selector
    private weak var target: AnyObject?

    init(title: String, target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
        super.init(frame: .zero)
        wantsLayer             = true
        layer?.cornerRadius    = 6
        layer?.borderWidth     = 0.75
        layer?.borderColor     = DS.cardBorder.cgColor
        layer?.backgroundColor = DS.cardGlass.cgColor

        label.font        = DS.body(11)
        label.textColor   = DS.textMuted
        label.alignment   = .center
        label.stringValue = title
        label.frame       = NSRect(x: 4, y: 6, width: 104, height: 14)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        tracking = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with e: NSEvent) { label.textColor = DS.textPrimary }
    override func mouseExited(with e: NSEvent)  { label.textColor = DS.textMuted }
    override func mouseUp(with e: NSEvent) {
        NSApp.sendAction(action, to: target, from: self)
    }
}
