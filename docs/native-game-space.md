# Native game Space: Dock and menu bar during play

Per-game resolution (`native-game-space.dylib`, `NOTPROTON_NATIVE_SIZE` or the
launcher's `.native-game-space` manifest) puts the game window in its own native
macOS fullscreen Space.

## Behaviour

While the managed game window is in its fullscreen Space, the game process is
active and the game window is the key window:

- Top edge: the menu bar does not appear.
- Bottom edge: the Dock does not appear over the game. The Dock still slides in
  underneath the game window, but nothing of it is visible or clickable.

As soon as any of these stop being true, normal behaviour returns: switching to
another app (Cmd-Tab, click elsewhere), leaving the Space (swipe, Mission
Control), another window of the game becoming key (a Wine dialog), the start of
a fullscreen exit, closing the window or quitting the game.

## Mechanism

Measured on macOS 27 with an AppKit harness that drives the cursor to the
edges with HID events and compares the edge pixels:

| In a native fullscreen Space                    | Menu bar | Dock  |
|-------------------------------------------------|----------|-------|
| default options (`AutoHide*`)                   | shown    | shown |
| `HideDock \| HideMenuBar`, regular or accessory | hidden   | shown |
| same, window level `NSStatusWindowLevel + 1`    | hidden   | hidden |
| borderless desktop window, `HideDock \| HideMenuBar` | hidden | hidden |

Inside a fullscreen Space the system honours `HideMenuBar` but ignores
`HideDock`. `currentSystemPresentationOptions` reports `0x400` there even when
the menu bar is hidden, so it is not evidence either way.

The fix, in `native-game-space/game_space.m`:

1. `HideDock | HideMenuBar` stays requested through
   `window:willUseFullScreenPresentationOptions:` and `syncPresentation()`
   (hides the menu bar; harmless for the Dock).
2. `gameLevel()` puts the managed window at `NSStatusWindowLevel + 1` (the
   level Wine itself uses for active fullscreen windows) only under the
   conditions above, and at `NSNormalWindowLevel` otherwise. It is applied from
   Wine's `minimumLevelForActive:` hook, `configure()`, `syncPresentation()`
   (all activation, key, Space and occlusion changes plus the 1 s timer), the
   will-enter/will-exit fullscreen notifications, and one runloop turn after
   key/activation changes. The log prints `[native-space] window level N` on
   each change.

Nothing global is changed: no `defaults write`, no display capture, no
system UI mode outside the game process.

## Verifying

`native-game-space/tests/edge-harness.swift` reproduces the table above (modes
are listed in its header). `native-game-space/tests/edge-probe.swift` drives a
running game: build it with `swiftc -O edge-probe.swift -o edge-probe` and run
`./edge-probe LABEL` while the game is in front. The probe
moves the cursor to the top and bottom edge and prints the front-most window
under each edge plus a screenshot. On a real launch the probe must report the
game window (layer 26) at both edges while playing, and `Window Server/Menubar`
and `Dock` again after switching away or quitting.
