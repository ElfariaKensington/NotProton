# Automatic game cursor handling

The generated game launcher stages and injects `game-cursor.dylib` without settings
or launch-option changes. The helper is a universal macOS 15 library. It excludes
native processes, Steam/Wine services, installers and crash reporters before
installing any hooks, capturing executable identity before Wine rewrites argv.

The system cursor becomes transparent only when the app is active, a visible game
WineWindow is key, that window is topmost at the physical pointer location, and
the pointer is over a visible Metal, hosted Metal or OpenGL rendering view, and
the game has explicitly requested cursor hiding through Wine. Hardware cursors,
including custom game cursors, remain visible when the game requests them. Native
controls, titlebars, unrendered regions, child windows, utility windows, sheets,
modal sessions and nonresizable titled dialog windows retain their cursor.

A local event monitor and window/application notifications update this decision.
A 100 ms timer runs only while the game process is active to handle stationary
pointers when a window or surface changes. Coordinates are physical AppKit
coordinates, independent of the optional resolution helper's Wine-only transforms.

Cursor replacement uses a valid transparent bitmap and intercepts subsequent
`NSCursor.set` calls while the pointer remains over the game renderer and Wine’s hide request is active. It never
calls global display hide APIs. Wine's retained hide request is temporarily
suspended outside the game renderer so Wine balances its own hide/unhide state;
the original request is preserved for returning to the game. Restoration
reinstates the last requested cursor only if this helper still owns the transparent
cursor. Resigning active, closing or leaving a game window restores that ownership.
The OS retains control of cursor presentation across applications and process exit.

`make cursor-check` checks renderer/focus/dialog boundaries and cursor ownership
without hiding or moving the user's cursor, plus process exclusions and the actual
generated launcher’s preservation of existing injected libraries and arguments.

Fullscreen game presentation suppresses edge-triggered Dock and menu-bar reveal
using app-local HideDock/HideMenuBar flags. This applies both to native fullscreen
Spaces and borderless windows covering the physical display, including games with
no resolution override. AppKit/Wine presentation updates are normalized while the
game is active; dialogs, windowed mode, focus loss and termination restore the
requested presentation flags. Cmd-Tab and system preferences remain available.

Presentation ownership is retained across same-app key-window handoffs and native
renderer replacement. Notifications from unrelated closing windows cannot release
it. A real dialog, mode change, game close or app deactivation still releases it.
The policy checks effective system presentation flags as well as AppKit’s cached
request and reasserts protection if they diverge. State transitions are recorded
as `NotProton presentation v2` lines in the existing per-game Wine log.

Desktop/Space round trips can reset the effective HIToolbox process UI mode while
AppKit retains its cached HideDock/HideMenuBar request. Repeating the same setter
then does not recover the system policy. When this exact mismatch is detected for
the active fullscreen game, the helper reapplies process-local AllHidden directly.
It saves and restores the previous process UI mode/options on release, without
changing global preferences or disabling application switching. Native tests reset
the effective mode repeatedly while retaining the AppKit cache, cover accessory
clients, and check release on returning to windowed mode.
Space changes are observed explicitly, and windows outside the active Space cannot
retain the override even if AppKit’s active-app state has not yet caught up.
