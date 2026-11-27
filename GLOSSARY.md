# OpenBetterDisplay

A lightweight macOS menu bar utility for managing connected displays, brightness, Display Modes, and OS-level display disconnect without unplugging cables.

## Language

**Main Display**:
The single connected display designated by macOS to host the primary menu bar and Dock.
_Avoid_: Active main, primary display

**Main Display Badge**:
The solid `M` indicator shown exclusively in the Main Display's header pill.
_Avoid_: M icon, main indicator

**Enabled Display**:
A physically connected display currently powered on and receiving video output from macOS.
_Avoid_: Active display, online display

**Disconnected Display**:
A physically connected display turned off at the OS level by OpenBetterDisplay and retained in the display list so it can be re-enabled without unplugging cables.
_Avoid_: Disabled display, inactive display, off display

**Display Mode**:
A selectable display configuration combining logical resolution, pixel scaling (`HiDPI` or `LoDPI`), refresh rate, and color depth.
_Avoid_: Resolution, screen resolution, display setting

**HiDPI**:
A pixel-scaled Display Mode that renders desktop UI at a higher backing pixel density (such as 2x Retina) for crisp text and graphics.
_Avoid_: Retina mode, 2x mode

**LoDPI**:
An unscaled 1x Display Mode where logical points match output pixel dimensions one-to-one.
_Avoid_: Standard DPI, non-Retina, 1x mode

**Default Mode**:
The Display Mode designated by macOS as the recommended factory default for a connected display.
_Avoid_: Recommended mode, star mode

**Native Mode**:
The Display Mode whose logical resolution matches the physical pixel grid of the panel one-to-one.
_Avoid_: Physical resolution, panel native

**Favorite Mode**:
A Display Mode saved to one of a display's five quick-recall slots for one-click switching.
_Avoid_: Preset, bookmark, saved resolution

**ProMotion**:
An Apple **Variable Refresh Rate** Display Mode reported natively by macOS (`SLSIsDisplayModeProMotion`), surfaced as `ProMotion` (`ProMotion (Variable)` in the Refresh Rate picker) rather than only a numeric Hz range.

**Variable Refresh Rate**:
A Display Mode whose refresh rate adapts dynamically across a supported frequency range (such as `48–120Hz` on external adaptive displays).
_Avoid_: VRR, adaptive sync

**NTSC Refresh Rate**:
A fractional broadcast-cadence refresh rate (such as `59.94Hz` or `119.88Hz`) when exposed by the display.
_Avoid_: Fractional Hz, drop-frame rate

**Brightness Hotkey**:
A global keyboard shortcut that steps Target Display brightness up or down.
_Avoid_: Keyboard shortcut, keybind, brightness key

**Target Display**:
The Enabled Display or set of Enabled Displays that receives a Brightness Hotkey adjustment.
_Avoid_: Active display, focused screen
