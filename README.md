# BrightnessSync ☀️

A lightweight macOS menu bar app to control your MacBook and external monitor brightness together with calibrated sync.

![macOS](https://img.shields.io/badge/macOS-12.0+-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3-green)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

## Features

- 🌞 **Unified brightness control** - Single slider syncs brightness across all displays
- ⌨️ **Keyboard shortcuts** - Option+F1/F2 to quickly adjust brightness
- 🎚️ **Calibrated sync** - Maps brightness levels so displays match visually
- 💡 **Built-in display support** - Native brightness control via DisplayServices
- 🖥️ **External monitor support** - DDC/CI via m1ddc for hardware brightness
- ⚡ **Lightweight** - Pure Swift, minimal memory footprint

## Installation

### Download DMG
Download the latest release from the [Releases](../../releases) page.

### Build from Source
```bash
git clone https://github.com/YOUR_USERNAME/BrightnessSync.git
cd BrightnessSync
./build.sh
```

## Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon Mac (M1/M2/M3)
- `m1ddc` for external monitor control:
  ```bash
  brew install m1ddc
  ```

## Usage

1. **Run the app** - A ☀️ icon appears in your menu bar
2. **Click the icon** - Shows a brightness slider
3. **Drag the slider** - Adjusts brightness on all displays
4. **Use keyboard shortcuts** - ⌥F1 (decrease) / ⌥F2 (increase)

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌥ Option + F1 | Decrease brightness by 10% |
| ⌥ Option + F2 | Increase brightness by 10% |

> **Note**: Keyboard shortcuts require Accessibility permissions.  
> Go to **System Settings → Privacy & Security → Accessibility** and add BrightnessSync.

## Brightness Calibration

The app includes built-in calibration to match displays with different brightness ranges:

| Slider | MacBook | External Monitor |
|--------|---------|------------------|
| 0% | 20% | 0% |
| 50% | 50% | 50% |
| 100% | 80% | 100% |

This ensures:
- MacBook doesn't go pitch black at minimum
- MacBook doesn't overpower the monitor at maximum

You can customize these values in `BrightnessController.swift`.

## How It Works

- **MacBook display**: Uses Apple's DisplayServices private framework
- **External monitors**: Uses [m1ddc](https://github.com/waydabber/m1ddc) for DDC/CI control

## Project Structure

```
BrightnessSync/
├── BrightnessSync/
│   ├── main.swift              # App entry point
│   ├── AppDelegate.swift       # Menu bar UI + keyboard shortcuts
│   ├── BrightnessController.swift  # Brightness management + calibration
│   ├── DDCControl.swift        # External monitor via m1ddc
│   └── DisplayManager.swift    # Display enumeration
├── build.sh                    # Build script
└── README.md
```

## License

MIT License - see [LICENSE](LICENSE)

## Acknowledgments

- [m1ddc](https://github.com/waydabber/m1ddc) - DDC control for Apple Silicon
- [MonitorControl](https://github.com/MonitorControl/MonitorControl) - Inspiration for the project
