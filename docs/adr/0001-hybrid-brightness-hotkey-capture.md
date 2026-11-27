# Hybrid Brightness Hotkey Capture and Fn-Mode Checker

Status: accepted

To route **Brightness Hotkeys** (`☀️-`/`☀️+` media keys and `F1`/`F2`) per **Target Display**, OpenBetterDisplay uses a hybrid capture architecture: a `CGEventTap` for system brightness media keys (suppressing macOS's built-in display routing when targeting external monitors) paired with Carbon `RegisterEventHotKey` for opt-in literal `F1`/`F2` keys, plus an `IOHIDEventSystemClient` (`HIDFKeyMode`) checker surfacing the user's macOS function-key mode and Accessibility status in the popover without unsolicited permission prompts on launch.

## Considered Options

- **`CGEventTap` only (all keys)**: Cannot receive unmodified `F1`/`F2` or media keys reliably without Accessibility/Input Monitoring permission; fails completely on first launch or after ad-hoc local rebuilds.
- **Carbon `RegisterEventHotKey` only**: Requires no Accessibility permission for literal `F1`/`F2`, but cannot intercept or consume Apple hardware brightness media keys (`NX_KEYTYPE_BRIGHTNESS_DOWN` / `NX_KEYTYPE_BRIGHTNESS_UP`), causing macOS to adjust the **Built-in Display** or display a disabled OSD when aiming at an external monitor.
- **Hybrid (`CGEventTap` + Carbon `RegisterEventHotKey` + `HIDFKeyMode` checker) (chosen)**: Gives zero-permission support for opt-in literal `F1`/`F2` (ideal for external keyboards or flipped `HIDFKeyMode`), clean per-**Target Display** interception of `☀️-`/`☀️+` once Accessibility is granted, and transparent diagnostics for why `F1`/`F2` vs `Fn+F1`/`Fn+F2` behaves as it does.

## Consequences

- Pressing `☀️-`/`☀️+` when **Target Display** is solely the **Built-in Display** passes the event through to macOS for native backlight control and native OSD, whereas targeting an external display (or **All Enabled Displays**) consumes the event and applies adjustments via `DisplayCoordinator`.
- Accessibility permission is never requested automatically on startup; the user explicitly grants it via the **Hotkeys** checker when enabling `☀️-`/`☀️+` interception for external displays.
- Local ad-hoc rebuilds (`make app`) invalidate macOS TCC Accessibility trust until re-granted or signed with a stable developer certificate.
