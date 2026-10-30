# Automatic game cursor handling

The generated game launcher stages and injects `game-cursor.dylib` without settings
or launch-option changes. The helper is a universal macOS 15 library. It excludes
native processes, Steam/Wine services, installers and crash reporters before
installing any hooks, capturing executable identity before Wine rewrites argv.

The system cursor becomes transparent only when the app is active, a visible game
WineWindow is key, that window is topmost at the physical pointer location, and
the pointer is over a visible Metal, hosted Metal or OpenGL rendering view. Native
controls, titlebars, unrendered regions, child windows, utility windows, sheets,
modal sessions and nonresizable titled dialog windows retain their cursor.

A local event monitor and window/application notifications update this decision.
A 100 ms timer runs only while the game process is active to handle stationary
pointers when a window or surface changes. Coordinates are physical AppKit
coordinates, independent of the optional resolution helper's Wine-only transforms.

Cursor replacement uses a valid transparent bitmap and intercepts subsequent
`NSCursor.set` calls while the pointer remains over the game renderer. It never
calls global display hide APIs. Wine's retained hide request is temporarily
suspended outside the game renderer so Wine balances its own hide/unhide state;
the original request is preserved for returning to the game. Restoration
reinstates the last requested cursor only if this helper still owns the transparent
cursor. Resigning active, closing or leaving a game window restores that ownership.
The OS retains control of cursor presentation across applications and process exit.

`make cursor-check` checks renderer/focus/dialog boundaries and cursor ownership
without hiding or moving the user's cursor, plus process exclusions and the actual
generated launcher’s preservation of existing injected libraries and arguments.
