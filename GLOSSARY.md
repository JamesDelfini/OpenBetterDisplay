# OpenBetterDisplay

A lightweight macOS menu bar utility for managing connected displays, brightness, resolution scaling, and OS-level display disconnect without unplugging cables.

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
