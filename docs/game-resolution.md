# Per-game fullscreen resolution

Properties > Compatibility > Fullscreen resolution reads the main display’s available
macOS modes, including HiDPI logical and pixel dimensions, and offers common game
resolutions plus custom width/height. Refresh-rate duplicates are collapsed. Apply saves the selection for the next launch. Use game settings
removes the override. Each game has a `notproton-display` file beside `pfx` in its
Steam library's `steamapps/compatdata/<appid>` directory. The main display is used;
settings are never placed in Steam launch options.

The generated game app declares `public.app-category.games`. An enabled override
injects the universal `game-display.dylib` into that game's Wine launcher and its
children. It creates a native AppKit fullscreen Space for the main Wine window,
excluding background Wine helpers and utility windows. Normal fullscreen exit
remains available.

The helper exposes one virtual mode through the Wine Mac driver's CoreGraphics
mode, pixel-size and bounds queries and its NSScreen queries. Real CGDisplayMode
objects retain their normal ownership semantics. Their dimensions are virtualized
only for `winemac.so`; AppKit still sees the physical monitor. Wine's display mode
and capture requests are virtual. The Mac's display settings remain unchanged.
The virtual canvas preserves the requested aspect ratio inside the native Space.

The helper is inactive with no valid override. A missing helper is reported rather
than silently ignoring the setting. Changing or clearing the setting requires a
restart. Games with independent internal render scaling can still render below
the selected desktop resolution.

`make display-check` exercises Mach-O interposition, physical/AppKit isolation,
native fullscreen and invalid/default settings using a separate driver fixture.
`make compatsvc-check panel-behavior` covers the actual service and injected UI.
`make runcheck scriptcheck launchercheck bundlecheck` covers the launcher paths.

For an optional live CrossOver check, install mingw-w64 and run:

```sh
python3 dylib/tests/display-wine-check.py --crossover-root "/path/to/notproton/runners/crossover-<build>/CrossOver"
```

This uses a temporary prefix and generated game bundle, confirms the Windows
desktop and client area are 1920×1080 in a native fullscreen Space, checks the
physical mode is unchanged, and confirms disabling restores the default desktop.
The runner must have NotProton’s normal DYLD entitlement patch.

The helper keeps native titlebar separators hidden in fullscreen and maintains a
black uncovered canvas even when Wine changes the window background after entry.
Exiting fullscreen restores the window’s original style, background and bounds.
The native fixture opens a driver-warning dialog first, attaches a renderer after
window creation, simulates Wine’s late white-background repaint, and checks exit.
The live Wine fixture exercises a real warning dialog followed by an OpenGL window.
