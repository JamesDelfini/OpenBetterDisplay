# 05: Global Brightness Hotkeys, Target Display Routing & Footer Checker

**What to build:** Add global **Brightness Hotkey** support (`☀️-`/`☀️+` media keys active by default via `CGEventTap`, plus an opt-in **"Bind literal F1 / F2"** toggle via Carbon hotkeys per ADR-0001) routed through a single new `BrightnessHotkeyGateway` seam, stepping brightness by `1/16` (`6.25%`) per press or `1/64` (`1.56%`) with `⌥⇧` (including key-repeat) across the configured **Target Display** mode (**Follow Mouse Cursor** default, **All Enabled Displays**, or **Main Display**, always excluding **Disconnected Displays**). Add a collapsible **Hotkeys** section in the popover footer (participating in the single-open accordion) with target/trigger controls and a live checker displaying macOS's `HIDFKeyMode` setting (top-row media vs standard `F1`–`F12` requiring `Fn+F1`/`Fn+F2`) and Accessibility permission status without auto-prompting on launch.

**Blocked by:** 01: Card Layout Transition & Core Display Mode Browser

**Status:** resolved

- [x] By default, `☀️-` decreases and `☀️+` increases brightness by `1/16` (`6.25%`) per press (`1/64` with `⌥⇧`) with key-repeat support; enabling **"Bind literal F1 / F2"** binds `F1` (decrease) and `F2` (increase) globally without requiring Accessibility permission.
- [x] **Target Display** defaults to **Follow Mouse Cursor** (adjusting whichever **Enabled Display** contains the pointer, falling back to **Main Display**), with options in the footer **Hotkeys** drawer for **All Enabled Displays** (independent relative stepping per display clamped to `0%–100%`) and **Main Display**; **Disconnected Displays** are never targeted.
- [x] Pressing `☀️-`/`☀️+` when the resolved **Target Display** is solely the **Built-in Display** passes the event through to macOS for native backlight/OSD handling, whereas targeting an external display or **All Enabled Displays** consumes the event and applies adjustments via `DisplayCoordinator` (respecting DDC throttling and software-gamma fallback).
- [x] The popover footer includes a collapsible **Hotkeys** row above `Launch at Login` (sharing the single-open accordion) with **Target Display** selector, trigger toggles, and persisted preferences across restarts.
- [x] The **Hotkeys** drawer displays a live **Keyboard & Permission Checker** reporting (a) macOS `HIDFKeyMode` (top-row media keys vs standard `F1`–`F12` requiring `Fn+F1`/`Fn+F2`) with a button to open Keyboard Settings, and (b) Accessibility trust status with an explicit **"Enable Accessibility…"** button (never auto-prompted on app startup).
- [x] Behavioral tests across `DisplayDriver` and a fake `BrightnessHotkeyGateway` verify cursor-under-display targeting, fallback to **Main Display**, **All Enabled Displays** relative stepping, **Disconnected Display** exclusion, `1/16` vs `⌥⇧` `1/64` deltas, `☀️-`/`☀️+` **Built-in Display** passthrough vs external consumption, literal `F1`/`F2` toggle behavior, and live checker state propagation; `make check` passes cleanly.

## Comments

- Implemented on `ticket-05-brightness-hotkeys` (`f9dc37a` / `dbb581f`), merged into `feat/display-mode-refresh-rate-and-hotkeys` in `86ea767`, and refined after two-axis code review in `f708002` / `0d028e2` (extracted pure `BrightnessKeyEventParser`, inclusive bottom/right screen-edge pointer fallback, background Accessibility change observer/conditional polling, truthful `isMediaKeyCaptureActive` status, and shared `UserDefaultsJSONStore` / `PopoverSectionChrome`).
