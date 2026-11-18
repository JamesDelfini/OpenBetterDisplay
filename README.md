# OpenBetterDisplay

**OpenBetterDisplay** is a lightweight, open-source (MIT) native macOS menu bar application for managing multi-monitor setups without bloatware.

## Features

- **Native Menu Bar Popover**: Dark, translucent HUD popover listing every connected display in a rounded header pill with its human-readable model name (`Built-in Display`, `DELL P2217H`, `DELL U2725QE`), laptop vs. external monitor icon, and Main Display (`M`) badge.
- **Live Hotplug Detection**: Automatically updates the display list when monitors are plugged in, unplugged, or reconfigured.
- **No-Unplug OS-Level Display Turn-Off**: Disconnect and reconnect individual monitors at the macOS WindowServer level without unplugging cables, with safety guardrails for the Main Display (`M`) and last active display.
- **Hardware & Fallback Brightness Control**: Native backlight control for Apple built-in displays, DDC/CI (`IOAVService` I2C VCP `0x10`) hardware luminance control for external monitors, and automatic software gamma fallback.
- **HiDPI Resolution Slider & Mode Picker**: Stepped resolution slider with live scale-percentage preview (`2560x1440 · 133%`) and clickable mode dropdown.

## Requirements

- macOS 14.0+ (Apple Silicon & Intel)
- Swift 5.9+ / Xcode 15+

## Building & Running

### From the Command Line

Build and package `build/OpenBetterDisplay.app`:

```bash
./scripts/build-app.sh
# or via Make:
make app
```

Run the packaged app:

```bash
open ./build/OpenBetterDisplay.app
# or:
make run
```

Run the test suite:

```bash
swift test
# or:
make test
```

### In Xcode

Open `Package.swift` directly in Xcode:

```bash
xed .
```

Select the `OpenBetterDisplay` scheme and press **Run** (`Cmd+R`), or press **Test** (`Cmd+U`) to run `OpenBetterDisplayTests`.

## License

Released under the [MIT License](LICENSE).
