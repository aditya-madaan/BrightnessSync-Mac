# BrightnessSync Mac ☀️

A lightweight macOS menu bar app that syncs brightness between your MacBook and external monitors. When you press F1/F2 or adjust brightness via Control Center, your external monitor automatically follows!

![macOS](https://img.shields.io/badge/macOS-12.0+-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-green)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

## ✨ Features

- ☀️ **Unified Brightness Control** - Single slider syncs all displays
- 🎹 **Native F1/F2 Keys** - Works automatically with your keyboard
- 🔌 **Auto-Detect** - Monitors plug/unplug detection
- ⚙️ **Calibration Settings** - Customize min/max brightness limits
- 🖥️ **Multi-Display** - Controls all connected external monitors
- ⚡ **Lightweight** - Pure Swift, ~100KB, no background CPU usage

## 📥 Installation

### 1. Install m1ddc (Required)
```bash
brew install m1ddc
```

### 2. Download the App
Download `BrightnessSyncMac.dmg` from the [Releases](../../releases) page.

### 3. Install & Fix Gatekeeper
```bash
# Drag app to Applications, then run:
xattr -cr "/Applications/BrightnessSync Mac.app"
```

### 4. Launch
Open BrightnessSync Mac from Applications. A ☀️ icon appears in your menu bar.

## 🎮 Usage

- **F1/F2 Keys**: Just use them normally - external monitor follows automatically
- **Menu Bar Slider**: Click the ☀️ icon and drag the slider
- **Control Center**: Brightness changes sync to external monitors

## ⚙️ Calibration Settings

Click ☀️ → "Calibration Settings..." to customize:

| Setting | Default | Description |
|---------|---------|-------------|
| Minimum | 20% | MacBook brightness when slider is at 0% |
| Maximum | 80% | MacBook brightness when slider is at 100% |

This prevents your MacBook from going too dim or too bright relative to your external monitor.

## ⚠️ Important: Connection Type Matters

### ✅ Supported Connections
| Connection | DDC Support | Notes |
|------------|-------------|-------|
| **USB-C / Thunderbolt** | ✅ Works | Best option |
| **DisplayPort** | ✅ Works | Use USB-C to DP adapter |

### ❌ Not Supported
| Connection | DDC Support | Notes |
|------------|-------------|-------|
| **HDMI** | ❌ Doesn't work | Apple Silicon limitation |
| **HDMI Adapters** | ❌ Rarely works | Most adapters block DDC |

### Why HDMI Doesn't Work

On Apple Silicon Macs, **HDMI connections do not reliably support DDC/CI** (the protocol used to control monitor brightness). This is a hardware/driver limitation in macOS, not something any software can fix.

**If you're using HDMI:**
- Switch to **USB-C** or **DisplayPort** connection
- Use a **USB-C to DisplayPort adapter** instead of HDMI
- Some monitors have USB-C input that supports DDC

**To verify your monitor supports DDC, run:**
```bash
m1ddc set luminance 50
```
If you see `DDC communication failure`, your connection doesn't support brightness control.

## 🔧 Troubleshooting

### "App is damaged" error
```bash
xattr -cr "/Applications/BrightnessSync Mac.app"
```

### External monitor not responding
1. Check connection type (USB-C works, HDMI doesn't)
2. Verify m1ddc is installed: `which m1ddc`
3. Test m1ddc directly: `m1ddc set luminance 50`

### Monitor not detected
```bash
m1ddc display list
```
Your monitor should appear in the list.

## 🏗️ Building from Source

```bash
git clone https://github.com/aditya-madaan/BrightnessSync-Mac.git
cd BrightnessSync-Mac
./build.sh
```

The built app will be in `build/BrightnessSync Mac.app`

## 📁 Project Structure

```
BrightnessSync-Mac/
├── BrightnessSyncMac/
│   ├── main.swift              # App entry point
│   ├── AppDelegate.swift       # Menu bar UI + settings
│   ├── BrightnessController.swift  # Brightness logic + sync
│   ├── DDCControl.swift        # m1ddc wrapper
│   ├── DisplayManager.swift    # Display detection
│   └── Info.plist              # App configuration
├── build.sh                    # Build script
└── README.md
```

## 📋 Requirements

- **macOS 12.0+** (Monterey, Ventura, Sonoma, Sequoia)
- **Apple Silicon** (M1, M2, M3, M4)
- **m1ddc** (`brew install m1ddc`)
- **USB-C or DisplayPort** connection (not HDMI)

## 📄 License

MIT License - see [LICENSE](LICENSE)

## 🙏 Credits

- [m1ddc](https://github.com/waydabber/m1ddc) - DDC control for Apple Silicon
