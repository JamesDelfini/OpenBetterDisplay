# 01: Tracer Bullet — Menu Bar App & Live Display Listing

**What to build:** A runnable, open-source macOS menu bar application (`OpenBetterDisplay`) that opens a dark, translucent, vibrant popover listing every connected display in its own rounded header pill with its human-readable model name (such as `Built-in Display`, `DELL P2217H`, `DELL U2725QE`), display-type icon (laptop for built-in, external monitor for external displays), and active Main Display (`M`) badge. The display list updates automatically when monitors are plugged in, unplugged, or reconfigured, and the popover footer provides `Launch at Login` and `Quit OpenBetterDisplay` actions.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Running the app places a monitor icon in the macOS system menu bar (without a Dock icon) and opens a dark translucent popover when clicked.
- [ ] Every connected display appears as a rounded header pill showing a laptop icon for the built-in display, a monitor icon for external displays, and the display's human-readable product name.
- [ ] The current Main Display displays an active `M` badge next to its name.
- [ ] Plugging in, unplugging, or reconfiguring displays updates the menu bar display list in real time.
- [ ] The popover footer includes a working `Launch at Login` toggle and a `Quit OpenBetterDisplay` button.
- [ ] The repository includes an MIT license, documentation for building and packaging the `.app` bundle from the command line or Xcode, and git ignore rules that exclude proprietary disk images and build artifacts.
- [ ] Behavioral tests exercise `DisplayCoordinator` across the `DisplayDriver` seam using an in-memory `FakeDisplayDriver` to verify multi-display discovery, human-readable naming, built-in vs. external classification, and Main Display identification.
