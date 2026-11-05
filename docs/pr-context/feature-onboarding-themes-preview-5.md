# PR Context: Resumable onboarding, themed Settings, and Preview 5

## Summary

Add resumable first-run setup, five focused Settings pages, four persisted themes, and
consistent native header and keyboard-focus behavior. Publish Preview 5 (app version
0.1.0, build 5) as a separate release with Universal, Apple silicon, and Intel ZIPs;
Preview 4 and its assets remain unchanged.

## Key Decisions

| Decision | Rationale | Alternatives considered | Impact and tradeoffs |
| --- | --- | --- | --- |
| Reopen the running app into Settings or unfinished setup | SwiftUI's menu-bar window has no public programmatic presentation API | Automatically opening the dashboard | Finder/Spotlight opens reuse Settings; login launches stay quiet |
| Persist setup progress, but keep unfinished credentials only in memory | Resume setup without storing draft secrets in preferences | Persisting credential drafts was not selected | Restarting requires re-pasting unfinished credentials; verified sessions use Keychain |
| Use one shared 500 x 500-point content area and Preferences controls | Keep setup and Settings consistent without enlarging the compact dashboard | Not documented | Longer pages scroll; section visibility semantics remain unchanged |
| Add Appearance and four live themes | Separate visual choices from dashboard visibility settings | Keeping themes inside Preferences | Theme changes update accents and surfaces without fetching account data |
| Use native navigation buttons in a centered preference toolbar | Native SwiftUI tab selection followed the macOS accent rather than the app theme | Hidden title and alternate toolbar layouts caused incorrect title/control positioning | Visible LeetBar title, theme-colored selection, neutral unselected tabs; hide shared glass background on macOS 26 |
| Give the theme picker a non-key-loop initial responder | Avoid an automatic square around Teal without removing keyboard focus feedback | SwiftUI default-focus and focus clearing did not produce consistent native behavior | Tab can still reach controls and Space can select a theme |
| Keep versioned release assets outside Git | Continue the existing release-download convention and preserve old builds | Replacing Preview 4 | Build 5 includes separate arm64/x86_64 packages plus the existing convenient Universal format |

## Key Flows

### Setup and account connection

1. Prepare once, restore the saved session, and migrate previously connected installations
   without a saved onboarding step directly to completed setup.
2. New users advance through welcome, browser sign-in, credentials, Preferences, and ready.
   Opening the browser does not automatically advance the step.
3. Validate cookie values locally before authentication. Report verification, Keychain save,
   and dashboard loading as separate phases; errors remain visible.
4. Persist the step, clear credentials after successful verification, and resume Preferences.
   Closing pauses setup; quitting clears unverified drafts. Completing ready prevents replay.

### Settings, themes, and reopening

1. A reopen bridge registers the Settings action and coalesces early reopen requests.
2. Settings restores its selected tab. Account reveals credential fields only when needed
   and clears drafts on tab changes, window closure, or successful connection.
3. Appearance saves one of four themes. Shared surfaces and navigation update immediately;
   the sample dashboard preview requires no networking.
4. The theme picker starts outside its buttons, avoiding automatic Teal focus. Subsequent
   keyboard navigation retains the native visible focus indicator.
5. Diagnostics polling runs only on its selected page. Folder/export/clear results remain
   explicit; no logs or credentials are uploaded automatically.

### Release packaging

1. Build Release with arm64 and x86_64 slices, app version 0.1.0 and build number 5.
2. Preserve the Universal app and derive architecture-specific apps from its tested slices.
   Re-sign each thinned app with ad-hoc hardened-runtime signing.
3. Verify architecture, minimum macOS 14 metadata, strict signatures, and absence of the
   debugger entitlement; ZIP each app and generate SHA256SUMS.
4. Extract all three ZIPs, compare them to their packaged apps, and verify signatures and
   checksums before publishing a distinct v0.1.0-preview.5 prerelease after merge.

## FAQs

### What remains unchanged?

The menu-bar dashboard stays compact. Existing section-aware network dependencies, refresh
cadences, completed-day caching, launch-at-login opt-in, and privacy-safe local diagnostics
remain covered by the full suite. Authentication still uses manually entered browser cookies
and unofficial LeetCode website endpoints; no OAuth or automatic token refresh is added.

### How was this validated?

All 128 Release tests passed on Apple silicon and under x86_64 Rosetta, including onboarding
state/failure handling, credential validation, reopen coalescing, five-page sizing, native
header geometry, theme persistence and no-refetch behavior, and initial/reopened focus with
subsequent keyboard navigation. The isolated credential-free preview verified first-open
focus and keyboard theme selection in the actual native UI. All three extracted packages
passed signature, architecture, metadata, equivalence, and checksum checks.

Physical Intel hardware and every supported macOS version were not tested.

### What are the signing limitations?

These are ad-hoc signed previews, not Developer ID signed or Apple-notarized. macOS may
require explicit user approval to open the app or access an existing Keychain item after
replacement. The app does not approve security prompts automatically.

### How can this be diagnosed or rolled back?

Use Settings > Diagnostics for local logs and exports, reviewing exports before sharing.
Install the retained Preview 4 release to roll back the executable. New theme, tab, and setup
preferences are additive; rollback does not automatically erase them, personal links, or
Keychain credentials.
