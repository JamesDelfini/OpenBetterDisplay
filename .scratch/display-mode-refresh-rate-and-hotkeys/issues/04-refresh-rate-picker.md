# 04: Refresh Rate Picker (Variable, Integer & Exposed NTSC Rates)

**What to build:** Add a collapsible **Refresh Rate** pill directly on each **Enabled Display** card below **Display Mode** showing the currently active rate (such as `120Hz` or `24–120Hz`) when collapsed, and expanding to list every refresh rate macOS exposes for the display's active logical resolution and **HiDPI**/**LoDPI** tier. **Variable Refresh Rate** options (e.g. `48–120Hz (Variable)`) appear alongside standard integer rates (`120Hz`, `60Hz`, `50Hz`, etc.), and hardware-exposed **NTSC Refresh Rates** (`119.88Hz`, `59.94Hz`, `47.95Hz`, `29.97Hz`, `23.98Hz`) appear in a separated sub-section only when exposed by macOS for that display—omitting unexposed synthetic timings and `Configuration Protection` per ADR-0002.

**Blocked by:** 01: Card Layout Transition & Core Display Mode Browser

**Status:** resolved

- [x] Every **Enabled Display** card displays a collapsible **Refresh Rate** pill below **Display Mode** showing the active refresh rate (or **Variable Refresh Rate** range) when collapsed, participating in the single-open popover accordion.
- [x] Expanding **Refresh Rate** lists only modes matching the display's currently active logical resolution and **HiDPI**/**LoDPI** scaling tier, highlighting the currently active refresh rate.
- [x] **Variable Refresh Rate** modes exposed by macOS/SkyLight are surfaced cleanly with range labels (e.g. `48–120Hz (Variable)`) and selectable in one click.
- [x] Standard integer refresh rates appear in the primary section, while fractional **NTSC Refresh Rates** (`119.88Hz`, `59.94Hz`, `47.95Hz`, `29.97Hz`, `23.98Hz`) appear below a divider only when macOS actually exposes fractional rates for that display and resolution (no fabricated timings or `Configuration Protection` warnings).
- [x] Clicking any refresh rate row switches the display to that mode immediately while preserving the active logical resolution and **HiDPI**/**LoDPI** tier.
- [x] Behavioral tests across `DisplayDriver` verify current-resolution rate grouping, **Variable Refresh Rate** presentation, exposed-only **NTSC Refresh Rate** section visibility, and immediate refresh-rate switching; UI preview rendering and `make check` pass cleanly.

## Comments

- Implemented on `ticket-04-refresh-rate-picker` (`c54e233` / `a63b7e1`), merged into `feat/display-mode-refresh-rate-and-hotkeys` in `4fe8143`, and refined after two-axis code review in `f708002` / `0d028e2` (unified canonical `isVariableRefreshRate` domain naming and shared collapsible section chrome).
