# 01: Card Layout Transition & Core Display Mode Browser

**What to build:** Replace the legacy `Resolution` slider on every **Enabled Display** card with a collapsible **Display Mode** pill directly below the **Brightness** slider, while keeping the **Brightness** slider visible and keeping the bottom `⌄` disclosure chevron for **Set as Main Display**. When collapsed, the **Display Mode** pill summarizes the active logical resolution; when expanded, it shows a height-capped scrollable list of safe `>= 720p` macOS-exposed **Display Modes** (excluding synthetic custom modes per ADR-0002), pinned **Default Mode** (`★`) and **Native Mode** (`≡`) rows at the top, active selection state, and per-mode badges (`✦` **HiDPI**, aspect ratio, refresh rate, and color bit depth such as `10bit` or `8bit`) with immediate click-to-switch. Expanding any section enforces a single-open accordion across the entire popover and automatically collapses on display disconnect, unplug, or popover close.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Every **Enabled Display** card shows the **Brightness** slider, a collapsible **Display Mode** pill displaying the active resolution summary when collapsed, and the bottom `⌄` chevron for **Set as Main Display**, with the old `Resolution` slider removed.
- [ ] **Disconnected Displays** remain collapsed with no **Display Mode** or **Brightness** controls.
- [ ] Expanding **Display Mode** or **Set as Main Display** collapses any other expanded section across the popover, and expansion resets cleanly when a display disconnects, unplugs, or the popover closes.
- [ ] Expanding **Display Mode** displays a height-capped scrollable list with a **Default and native modes** group (`★` for **Default Mode** and `≡` for **Native Mode**) followed by safe `>= 720p` modes, hiding unsafe, stretched, and sub-720p modes.
- [ ] Each **Display Mode** row renders an active checkmark when currently selected, logical `WidthxHeight`, and metadata badges for **HiDPI** (`✦`), aspect ratio, refresh rate, and color depth (`10bit` / `8bit`).
- [ ] Clicking any **Display Mode** row switches the display to that mode immediately and updates the active checkmark and collapsed summary.
- [ ] Mode parsing tests verify extraction of **Default Mode**, **Native Mode**, color depth (`10bit`/`8bit`), safe/stretched flags, and `>= 720p` filtering; coordinator behavioral tests across `DisplayDriver` verify immediate **Display Mode** switching, error preservation when macOS rejects a mode, and single-open accordion state; UI preview rendering and `make check` pass cleanly.
