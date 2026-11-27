# 02: Interactive Display Mode Filter Chips & Per-Display Persistence

**What to build:** Add an interactive **`Filter...`** button and expandable chip panel inside **Display Mode** so users can narrow long mode lists by aspect ratio, refresh rate, color depth, and **HiDPI** / **LoDPI**, or reveal all safe modes with **`Show All`** and restore defaults with **`Reset Default`**. Plain-clicking a chip solo-selects within its group while `⇧ Shift`+clicking multi-selects; uncustomized filtering dynamically tracks the display's native aspect ratio, active refresh rate, active color depth, and preferred DPI tier across refresh-rate switches, whereas explicit chip selections persist per physical display until **`Reset Default`**.

**Blocked by:** 01: Card Layout Transition & Core Display Mode Browser

**Status:** resolved

- [x] **Display Mode** shows a **`Filter...`** toggle button next to the filtered modes section header that expands and collapses the filter chip bar.
- [x] The filter chip bar derives available chips dynamically from each display's safe `>= 720p` **Display Modes**, covering aspect ratios (e.g. `5:4`, `4:3`, `24:10`, `16:9`, `16:10`), refresh rates (integer, **Variable Refresh Rate**, and **NTSC Refresh Rates**), color depths (`10bit` / `8bit`), and scaling (**HiDPI** / **LoDPI**).
- [x] Plain-clicking a chip selects only that chip within its attribute group, while holding `⇧ Shift` and clicking toggles multi-selection across chips.
- [x] Clicking **`Show All`** clears restrictive filters to display all safe `>= 720p` **Display Modes**; clicking **`Reset Default`** returns the filter to its uncustomized dynamic state.
- [x] Uncustomized default filtering automatically follows changes to the display's active refresh rate and color depth while keeping the preferred **HiDPI**/**LoDPI** tier and native aspect ratio; customized filter selections persist per physical display across refresh-rate changes and app restarts until **`Reset Default`**.
- [x] Behavioral tests across `DisplayDriver` and an in-memory persistence store verify dynamic default tracking, solo vs `⇧ Shift` multi-select chip filtering, `Show All`, `Reset Default`, and per-display persistence; UI preview rendering and `make check` pass cleanly.

## Comments

- Implemented on `ticket-02-display-mode-filter-chips` (`662cbdc` / `3e811f8`), merged into `feat/display-mode-refresh-rate-and-hotkeys` in `08effac`, and refined after two-axis code review in `f708002` / `0d028e2` (typed `AspectRatioFilterKey` and `RefreshRateFilterKey`, `DisplayModeContext`, shared `UserDefaultsJSONStore`, and serial-less physical persistence keys).
