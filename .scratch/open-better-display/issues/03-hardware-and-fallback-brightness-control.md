# 03: Hardware & Fallback Brightness Control with Persistence

**What to build:** A `Brightness` slider (`0%`–`100%`) with a sun icon and live percentage label inside every active display card (hidden when the display is toggled OFF). Adjusting brightness uses hardware backlight control first—native panel backlight for the Built-in Display and DDC/CI hardware luminance control over the display cable for external monitors—and automatically falls back to software gamma dimming if an external monitor does not support DDC/CI. Brightness levels are persisted per display across app restarts and hotplug events.

**Blocked by:** 01: Tracer Bullet — Menu Bar App & Live Display Listing

**Status:** resolved

- [x] Every enabled display card shows a `Brightness` row with the current percentage (`0%`–`100%`) and a horizontal slider with a sun icon; turning the display OFF hides the Brightness control.
- [x] Moving the Brightness slider on the Built-in Display adjusts the native Apple display backlight and reads back the current system brightness on launch.
- [x] Moving the Brightness slider on a DDC-capable external monitor adjusts the monitor's hardware backlight via DDC/CI VCP `0x10` (Luminance) with smooth debouncing/throttling.
- [x] If an external monitor does not support or respond to DDC/CI, moving the Brightness slider automatically falls back to software gamma dimming (`CGSetDisplayTransferByTable`) with a safe minimum floor so the screen remains readable at `0%`, and resets gamma cleanly on app quit.
- [x] Each display's last-set brightness level is persisted by display identifier and restored across app launches and hotplug events.
- [x] Behavioral tests across the `DisplayDriver` seam verify native backlight routing for built-in displays, hardware DDC routing for DDC-capable external displays, automatic fallback to software gamma dimming when DDC is unavailable, gamma reset on termination, and per-display brightness persistence.

## Comments

- Implemented on `ticket-03-brightness-control` (`bbe5f48`, `c362ff0`), merged onto `feat/open-better-display` in `29deb47`, and refined after code review in `af76b79` (built-in live brightness sync, DDC transient-failure cooldown & write-after-read-failure recovery).
