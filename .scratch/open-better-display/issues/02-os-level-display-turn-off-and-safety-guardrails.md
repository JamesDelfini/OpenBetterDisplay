# 02: True OS-Level Display Turn-Off, Safety Guardrails & Main Display ("M") Transfer

**What to build:** An on/off toggle switch in each display card's header pill that disconnects and reconnects the display at the macOS WindowServer level without unplugging the video cable or power cord. Turning a display OFF moves all windows to the remaining active screens, cuts video signal so external monitors enter hardware standby, and keeps the turned-off display card visible in the menu bar list (with its sub-controls collapsed) so it can be toggled back ON anytime. Includes full safety guardrails so the user can never lock themselves out of visual output: the Main Display (`M`) and the last remaining active display cannot be turned off, non-main active displays show a clickable `M` button to transfer Main Display status, a `Reconnect All Displays` button appears whenever any display is turned off, and all turned-off displays automatically reconnect on Mac wake-from-sleep and on app quit.

**Blocked by:** 01: Tracer Bullet — Menu Bar App & Live Display Listing

**Status:** resolved

- [x] Toggling an active non-main display OFF disconnects it at the OS level so macOS consolidates windows onto remaining displays and the monitor enters standby, while the display remains listed in the popover in the OFF state with its sliders hidden.
- [x] Toggling a turned-off display back ON re-enables it in macOS and restores its controls in the popover.
- [x] The turn-off toggle is disabled on whichever display is currently the Main Display (`M`).
- [x] Active non-main displays show a clickable `M` ("Set as Main Display") control that transfers Main Display status (`(0, 0)` origin) to that display, locking its off-toggle and unlocking the previous Main Display's off-toggle.
- [x] The turn-off toggle is disabled whenever only one active display remains enabled, preventing all displays from being turned off simultaneously.
- [x] Whenever one or more displays are turned off, a `Reconnect All Displays` action appears in the popover footer and re-enables all disconnected displays when clicked.
- [x] Waking the Mac from sleep automatically re-enables any turned-off displays.
- [x] Quitting `OpenBetterDisplay` automatically re-enables any turned-off displays before termination.
- [x] Behavioral tests across the `DisplayDriver` seam verify OS-level disconnect state retention after the OS stops reporting the display as active, single-display reconnect, `Reconnect All Displays`, Main Display (`M`) lock and transfer, last-active-display lock, sleep/wake auto-restore, and app-quit auto-restore.

## Comments

- Implemented on `ticket-02-display-turn-off` (`d129756`), merged onto `feat/open-better-display` in `4b766ce`, and verified through code review (`af76b79`).
