# 06: Floating Brightness HUD Overlay on External Target Displays

**What to build:** Display a brief, non-activating, click-through dark translucent **Brightness HUD** pill near the bottom-center of each external **Target Display** whenever its brightness is adjusted via a **Brightness Hotkey**, showing the display icon, display name, brightness progress bar, and percentage readout, and resetting its ~1.2 s auto-fade timer smoothly across repeated or held key presses.

**Blocked by:** 05: Global Brightness Hotkeys, Target Display Routing & Footer Checker

**Status:** resolved

- [x] Adjusting an external **Target Display** (under **Follow Mouse Cursor**, **Main Display**, or **All Enabled Displays**) via **Brightness Hotkeys** displays a compact dark translucent **Brightness HUD** centered near the bottom edge of that specific display.
- [x] Each **Brightness HUD** panel is non-activating and click-through so active full-screen or focused applications never lose keyboard focus or mouse interaction.
- [x] Each HUD displays the monitor icon, display name, filled brightness bar, and percentage readout (`0%–100%`), updating immediately and extending its ~1.2 s auto-fade timer during repeated presses or key-repeat holds.
- [x] Passing `☀️-`/`☀️+` through to macOS when targeting only the **Built-in Display** does not emit a duplicate custom HUD over macOS's native brightness OSD.
- [x] Behavioral tests across `BrightnessHotkeyGateway` verify exact HUD emission payloads (display ID, display name, updated brightness level) for external single-target, multi-display **All Enabled Displays**, and **Built-in Display** passthrough scenarios; `make check` passes cleanly.

## Comments

- Implemented on `ticket-06-floating-brightness-hud` (`9180e3d` / `bf3d7d9`), merged into `feat/display-mode-refresh-rate-and-hotkeys` in `672bdf1`, and refined after two-axis code review in `f708002` / `0d028e2` (consolidated HUD output strictly through `BrightnessHotkeyGateway.showBrightnessHUD`).
