# PR Context: Global dashboard shortcut and application icon

## Summary

Add a fixed Command-Option-L global shortcut to toggle the existing dashboard and supply
the missing macOS app-icon asset. Move dashboard presentation to public AppKit APIs while
retaining its SwiftUI content, themes, Settings, first-run setup, and section-aware refresh.
This PR updates source only; published Preview 5 binaries and release assets are unchanged.

## Key Decisions

| Decision | Rationale | Alternatives considered | Impact and tradeoffs |
| --- | --- | --- | --- |
| Register Command-Option-L through Carbon's application event target | The user requested this exact global combination, including when another app is active | SwiftUI `.keyboardShortcut` is not a global hotkey; adding a shortcut package was unnecessary | Fixed shortcut, no Accessibility/Input Monitoring permission, exclusive registration with visible failure |
| Handle the hotkey-release event | Toggle once per completed shortcut rather than toggling repeatedly while held | Key-press handling | The dashboard toggles when the registered combination is released |
| Own an NSStatusItem and transient NSPopover | SwiftUI MenuBarExtra has no public programmatic open/close API | Simulated clicks and private APIs were not used | Keep dashboard content; public toggle, Escape, and outside-click dismissal |
| Keep the Settings bridge in a tiny hosted status-item view | Reopening and manual setup must work before the dashboard is first opened | Registering only inside the lazily created dashboard | Preserve early-reopen coalescing, Settings fallback, and quiet login launches |
| Add a complete AppIcon catalog independently of the menu-bar image | Menu-bar images existed, but app-icon resources and bundle metadata were missing | Resetting system-wide caches does not fix a missing app asset | Supply all ten macOS size/scale slots with seven PNG resolutions; retain the template menu-bar icon |

## Key Flows

### Startup, hotkey, and dismissal

1. App initialization shares the existing account/setup/link stores with the native menu-bar
   controller. The app delegate starts that controller at launch.
2. The controller creates its status item, mounts the Settings bridge, subscribes to streak
   and visibility changes, and registers the fixed global shortcut.
3. Command-Option-L and status-item clicks share one toggle action. Opening prepares setup
   and calls the existing cached refresh path, then lazily hosts the existing dashboard.
4. The popover sizes to SwiftUI content and becomes key. Escape or outside interaction closes
   it; the close delegate clears the status-item highlight.
5. Normal termination unregisters the shortcut, removes its event handler and status item,
   closes the popover, and cancels subscriptions.

### Registration failures

1. Register an exclusive hotkey for the physical ANSI L key with Command and Option only.
2. If event-handler or hotkey registration fails, clean up partial registration.
3. Show the failure in Settings > Preferences and emit a sanitized warning with the numeric
   macOS status. Clicking the menu-bar icon remains available.
4. Restart after freeing a conflicting shortcut to retry. No general key logging is added.

### Finder and search icon

1. Xcode compiles the new AppIcon catalog and emits app-icon bundle metadata and ICNS resources.
2. The icon uses the existing LeetCode branding on a dark background; the README identifies
   the official source and retains the third-party logo/trademark notice.
3. macOS can still retain a stale search icon after an in-place replacement. Local checks
   verified the compiled resources and macOS's resolved installed-app icon; stale development
   registrations were removed locally without resetting system-wide caches.
4. Direct visual confirmation of Spotlight's refreshed result remains unavailable because
   its search UI could not be launched from this session.

## FAQs

### What remains unchanged?

The existing dashboard view, compact content width, themes, saved credentials/preferences,
network dependencies and cadences, login-item opt-in, diagnostics privacy, and macOS 14
minimum remain. Reopening from Finder/Spotlight still brings Settings or unfinished setup
forward; the new shortcut opens the dashboard instead.

### How was this validated?

All 136 Release tests passed on Apple silicon and under x86_64 Rosetta. Eight new tests cover
exact modifiers, registration idempotence, action delivery, error/retry behavior, cleanup,
lazy dashboard toggling, pre-dashboard bridge registration, streak-label preferences, and
clickable status-item fallback after registration failure. Native popover operations are
injected in unit tests because the unbundled runner cannot reliably own foreground focus.

Credential-free native app checks verified a real Carbon shortcut event from another app,
dashboard presentation, Escape/outside dismissal, and the hosted Settings gear opening the
SwiftUI Settings scene. The full scene wiring was also checked in an isolated app with
in-memory session storage.

The Universal app passed strict signature and architecture checks. All macOS icon slots,
including the compiled 1024-pixel rendition, and installed bundle metadata were verified.
Swift formatting and whitespace checks passed. Physical Intel hardware and every supported
macOS version were not tested.

### What are the rollout and signing limitations?

No new release is published here; Preview 5 downloads still lack this shortcut and icon fix.
Builds remain ad-hoc signed, not notarized. Replacing a build can require local Keychain
approval; production startup was waiting for that approval during verification. The prompt
was not approved automatically.

### How can this be diagnosed or rolled back?

Inspect Settings > Preferences and local diagnostic logs for shortcut-registration errors.
Free a conflicting global shortcut and restart. Reinstall Preview 5 to roll back the
executable; account data, personal links, and preferences are not removed automatically.
