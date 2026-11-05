# LeetBar

LeetBar puts your LeetCode daily challenge, streak, contest rating, practice totals, study-plan progress, and upcoming contests in the macOS menu bar. Keep up to four personal practice links one click away in its expandable Quick Links section.

## I don't have Xcode, and I just want to use it!

**[Download LeetBar for Mac](https://github.com/hritvikpatel1999/LeetBar/releases/download/v0.1.0-preview.4/LeetBar-0.1.0-preview.4-macos-universal.zip)**

For **Apple silicon and Intel Macs** running **macOS 14 or later**. This is **Preview 4**, adding privacy-safe local logging and exportable diagnostics alongside Launch at login and performance improvements. One Universal download contains both architectures.

**No Xcode, Terminal, or GitHub account needed to install.**

1. Open the downloaded ZIP to extract **LeetBar**.
2. Drag **LeetBar** into **Applications**.
3. Open **LeetBar**, then click its icon in the **menu bar at the top of your screen**. There is no Dock icon or main window.

**If macOS blocks the first launch:** this preview is not Apple-notarized. After attempting to open it, go to **System Settings > Privacy & Security > Open Anyway**, then confirm. Proceed only if you trust this download. Managed Macs may prohibit this approval; do not disable macOS security protections.

Next, [connect your LeetCode account](#connect-your-account). See the [release's security notes and known limitations](https://github.com/hritvikpatel1999/LeetBar/releases/tag/v0.1.0-preview.4#security-and-known-limitations) before connecting.

## LeetBar Overview

Choose what you see in **Settings > Preferences**: show or hide **Quick Links**, **Upcoming Contests**, **Today**, and **Study Plans** independently. All four are shown by default, and your choices are saved automatically. Hiding a section does not delete your saved links or disconnect your account.

The **Study Plans** section appears after **Today**, starts collapsed, and shows up to three active plans from your connected LeetCode account. Expand it to see each plan's name, completed/total question counts, and a **Next Question** link when available. Progress is shown as counts, not percentages. Click a plan name to open it on LeetCode. Use **Show Study Plans** in Settings to hide or restore the section.

In **Settings > Preferences**, you can also show or hide the streak count beside the menu-bar icon.

### Reopening an already-running app (source builds)

Open LeetBar again from Finder, Spotlight, or `open /Applications/LeetBar.app` to bring its
Settings window forward, or resume setup if onboarding is unfinished. Repeated opens reuse Settings rather than launching another app
instance. Click the menu-bar icon to open the dashboard as usual.

The current SwiftUI menu-bar dashboard has no public programmatic presentation API, so
Settings is the supported fallback on macOS 14 and later. Existing connected users start
quietly; new users see setup on a manual launch. Launch at login remains quiet.
This behavior is not included in the Preview 4 download above.

### First-run setup (source builds)

New users get a centered setup window with the same 500 x 500-point content area as Settings:

1. **Welcome to LeetBar**: choose **Connect LeetCode**.
2. **Sign in to LeetCode**: choose **Open LeetCode**, sign in in your browser, then return and
   choose **I'm signed in**. Opening the browser does not automatically advance setup.
3. **Connect your account**: enter `LEETCODE_SESSION` and `csrftoken` values from that same
   signed-in session. Local validation catches empty fields, cookie-name/header pastes, and
   unsupported characters before any network request. Connection status distinguishes session
   verification, Keychain saving, and dashboard loading. Browser-specific instructions are
   not yet included; see [Connect your account](#connect-your-account).
4. **Preferences**: choose the same five visibility options available in Settings, then **Continue**.
5. **You're all set!**: find the LeetBar icon in your menu bar, then choose **Let's LeetCode!**
   to finish setup. Closing this page before finishing resumes it next time.

Close the window at any point to pause. **Continue setup** in the dashboard or reopening
LeetBar resumes the saved page. Unfinished credentials stay only in app memory, so closing
and reopening the window retains them while quitting/restarting clears them. Paste them
again to resume the credentials page. Verified credentials are stored in macOS Keychain,
never in preferences or diagnostic logs. A connection already underway can finish while the
window is closed, saving progress at Preferences.

LeetBar uses these credentials to authenticate requests to LeetCode; do not share them with
anyone. Failed connections remain on the credentials page with an actionable error.
Failures loading dashboard data after successful authentication do not falsely report a
failed login. Previously installed users with a saved session skip first-run setup, and
completed setup does not repeat after a normal restart or disconnect.

### Focused Settings pages (source builds)

Settings uses five icon-based native navigation buttons in the same 500 x 500-point content area as setup:
**Preferences**, **Appearance**, **Quick Links**, **Account**, and **Diagnostics**. The last selected tab
is remembered. Headers, grouped controls, credential fields, and teal accents are shared
with first-run setup, with scrolling available when a page needs more room.
The native title bar always shows **LeetBar** centered above the centered icon-based tabs,
with window controls kept in the top-left title row.
Navigation buttons leave room around their icons and labels, with only the active tab highlighted
and no shared toolbar capsule.
Navigation icons and labels have independently tuned spacing inside the selection highlight,
with clear gaps above and below it.

Choose **Teal**, **Ocean**, **Violet**, or **Sunset** in **Settings > Appearance > Color theme**.
Appearance includes a live, sample dashboard preview without loading account data.
Teal is the default. The choice is saved locally and updates accents and subtly tinted backgrounds
across Settings, first-run setup, Quick Link editing, and the menu-bar dashboard without restarting
or fetching account data. Light/dark appearance still follows macOS. Native window chrome and
semantic status colors retain their platform behavior.
The selected navigation icon and label use the app's chosen theme rather than the macOS system accent;
unselected tabs remain neutral.
The selected color is marked with a checkmark. Opening Appearance does not automatically focus
the first color button or show a square around Teal. Keyboard navigation remains available:
use Tab to focus a color and Space to select it, with a visible focus outline while navigating.

**Preferences** includes visibility controls and Launch at login. **Account** keeps saved
session status visible without permanently showing empty token fields. Choose **Reconnect**
to reveal the connection form, or **Cancel** to keep the current session. A rejected session
reveals the form automatically. Credential drafts are cleared when leaving Account or
closing Settings; an already-started connection can continue.

This layout is not included in the Preview 4 download.

### Launch at login

To start LeetBar automatically when you sign in to your Mac, open **Settings > General**
(**Settings > Preferences** in source builds)
and enable **Launch at login**. This is opt-in: LeetBar never registers itself automatically.
It starts quietly in the menu bar, without a Dock icon or a Settings window.

Enable this from your installed copy in **Applications**, not a temporary Xcode build.
The toggle reads macOS's actual login-item registration rather than a saved app preference.
If macOS requires approval, the toggle remains on to indicate registration is requested,
but LeetBar will not launch automatically until you approve it. Use **Open Login Items in
System Settings** to review its permission. Registration failures appear in Settings.

Turn the toggle off to unregister automatic startup; this does not quit LeetBar or disconnect
your account. You can also manage it in **System Settings > General > Login Items**
(called **Login Items & Extensions** on some macOS versions). Returning to LeetBar refreshes
the displayed status. This starts the app at user login, not before anyone signs in.

### Local diagnostic logs

Open **Settings > Diagnostics** to enable **Verbose logging**, **Export Logs** to a ZIP,
**Show in Finder**, or **Clear Logs** (with confirmation). Verbose logging is **off by default**.
Available in Preview 4 and later. Turn verbose logging on before reproducing a problem to
capture successful requests and authentication steps; warnings and errors do not require it.

LeetBar keeps two structured JSON-lines files in `~/Library/Logs/LeetBar/`:

- `warnings-errors.log`: warnings and errors are always recorded.
- `verbose.log`: optional startup/lifecycle, authentication, cache, and network events.
  A small startup record with app version/build, macOS version, and architecture is retained
  in **both files even when verbose logging is off**.

Authentication events cover saved-session restoration, verification, saving, reconnecting,
expiry, and disconnecting. LeetBar currently reuses saved cookies; it does **not** have an
automatic token-refresh API. Network events use fixed operation names, random request/cycle
IDs, HTTP status, response size, duration, and sanitized failure categories. Disabled sections
and cache decisions are visible with verbose logging enabled.

Logs never include cookies, CSRF tokens, raw headers/bodies, GraphQL variables, usernames,
account statistics, personal links, or arbitrary server/system error descriptions. Files are
owner-readable/writable only. Logs stay local: exporting does not upload anything. Timestamps
and system versions are still diagnostic information; review the ZIP before sharing it.

Each file is capped at **5 MiB** (10 MiB total), with **seven-day retention**, checked when
writing or exporting. Old entries are removed first; eviction warnings record size/retention
limits. Exported ZIPs are outside this cap and remain wherever you save them. Clear removes
historical entries but retains current startup metadata. Storage/export failures appear in Settings.

Every write is synchronized to disk. Pending writes are drained on normal quit, handled
SIGTERM/SIGINT termination, system sleep, and app deactivation. A force quit, crash, debugger
hard stop, or power loss cannot guarantee a final flush; the next launch warns if the previous
session did not record a clean shutdown.

### Network usage and refresh

Hidden **Today**, **Upcoming Contests**, and **Study Plans** sections do not fetch their data.
Quick Links are stored locally and never require a network request. Daily challenge, streak,
and contest rating remain visible in the dashboard, so hiding the menu-bar streak count does
not disable streak requests.

Opening the dashboard or clicking Refresh checks enabled data against an in-memory cache:

| Data | Refresh interval |
| --- | --- |
| Daily challenge (incomplete or unknown), today's activity, unconfirmed streak | 1 minute |
| Completed daily challenge, confirmed updated streak | Until the next daily reset (00:00 UTC) |
| Study plans | 5 minutes |
| Upcoming contests, contest rating | 1 hour |

Only a completed challenge whose server-provided date matches the current UTC day gets the
day-long cache. Local midnight does not expire it; UTC midnight does. Missing, malformed,
future, or outdated challenge dates retain the normal one-minute refresh behavior.

The streak is cached for that same day only after LeetBar observes a higher server-reported
count than an earlier sample from the same UTC challenge day, with daily completion confirmed.
It never calculates the increase itself or treats an unchanged count as proof of an update.
If the app first opens after completion, or the streak update is delayed or fails, streak
polling continues until an increase can be confirmed. An increase observed before challenge
completion can also be confirmed once completion is known.

These intervals do not introduce background polling. Refresh respects these intervals rather
than forcing every endpoint to reload. Each fetch cycle still verifies the account. Turning on
a section immediately loads missing or stale data, even during the ordinary one-minute refresh
cooldown; fresh cached data appears without another request. Changes during a fetch are queued
for when it finishes. A request cycle already underway may finish fetching a section you hide.
Failed sections report an error and can retry after one minute; rate limiting pauses requests
for five minutes. Caches clear on reconnect, disconnect, or app restart, and account changes
invalidate the previous account's data.

For a cold refresh, the previous implementation made `6 + P` requests, where `P` is the number
of submission-history pages (1–25). With one page, disabling Study Plans saves 1 of 7 requests;
disabling Today, Upcoming Contests, and Study Plans saves 3 of 7. A deterministic mock-transport
test simulating 60 refreshes one minute apart, including the initial cold connection and a
daily challenge that remains incomplete, verifies:

| Configuration | Previous requests | Cached requests | Reduction |
| --- | --- | --- | --- |
| All sections enabled | 420 | 254 | 39.5% |
| Study Plans disabled | 420 | 242 | 42.4% |
| Today, Upcoming Contests, Study Plans disabled | 420 | 181 | 56.9% |

Additional all-enabled tests verify the completed-day optimization:

| Daily completion and streak scenario | Previous requests | Cached requests | Reduction |
| --- | --- | --- | --- |
| Already completed at launch; streak increase cannot be confirmed | 420 | 195 | 53.6% |
| Completion observed at minute 1; streak increase observed at minute 2 | 420 | 139 | 66.9% |

These are request-count comparisons, not measured latency, bandwidth, or battery savings.
They assume successful responses, one submission page per fetch, and no restarts. Less frequent
use yields different savings; disabling Today saves all submission pages that would be requested.

LeetBar is an unofficial companion, not affiliated with LeetCode. The LeetCode name and logo belong to LeetCode.

LeetBar's original source code and documentation are licensed under the [MIT License](LICENSE). The bundled LeetCode logo images are excluded from that license. This project grants no rights to LeetCode's names, logos, or trademarks; those remain subject to their owners' rights.

## Download This If You

- Want a quick check of your daily challenge completion and streak.
- Track today's submissions and distinct problems solved.
- Want your contest rating and upcoming contest times at a glance.
- Want to check active study-plan progress and continue with the next question.
- Keep practice sheets, notes, or study plans online and want shortcuts to them.

## System Requirements

### To use the downloaded app

- **Apple silicon or Intel Mac** with **macOS 14 or later**. The same Universal download supports both.
- **Internet access and a LeetCode account** for live statistics. Quick Links work without a connected account.
- **Chrome** for the account-connection instructions below. Other browsers have different developer-tool menus.

### Only if building from source

- **Xcode with Swift 6 support.** Tested with Xcode 26.5. Install full Xcode, not just the standalone Command Line Tools.
- **XcodeGen 2.45 or later**, only if regenerating the project. It is not required to open or build the included Xcode project.

No paid Apple developer account is needed to build or run locally.

## Connect Your Account

After launching LeetBar:

1. Click its menu-bar icon, open the gear, and select **Open LeetCode Sign-In**.
2. Sign in on LeetCode in your browser. Choose **Google** if that is how you access your LeetCode account.
3. Stay on a signed-in leetcode.com page. In Chrome, press **Option-Command-I**, open **Application**, then **Storage > Cookies > https://leetcode.com**.
4. Copy only the **Value** of **LEETCODE_SESSION** into its matching masked field in LeetBar Settings.
5. Copy the **csrftoken** value from the same browser session into the other field. Do not copy an entire Cookie header.
6. Click **Connect**. Your username and live data appear after verification.
7. Clear your clipboard after pasting.

**Treat session cookies like passwords. Never share them in chat, screenshots, logs, or GitHub issues.** Enter them only into LeetBar's masked fields. LeetBar stores the session in your local macOS Keychain; it does not request your Google password or Gmail access.

The saved session is reused across launches. If it expires, repeat the steps with fresh values and choose **Reconnect**. **Disconnect** removes LeetBar's saved session but does not sign your browser out. macOS may request Keychain approval after a local rebuild; enter any requested Mac password only in the system dialog.

This is a manual browser-session connection, not automatic Google OAuth. LeetBar uses unofficial website endpoints that may change; review [LeetCode's terms](https://leetcode.com/terms/) before use.

## Run It in Xcode

1. Clone or download this repository and open [LeetBar.xcodeproj](LeetBar.xcodeproj).
2. Select the **LeetBar** scheme and **My Mac** destination in the toolbar.
3. Quit any already-running copy of LeetBar using the power button in its dropdown.
4. Press **Command-R** to build and run.
5. Look for the LeetCode logo in your **menu bar**. LeetBar intentionally has no Dock icon or main window.
6. Open Settings to connect your account, configure up to four **Quick Links**, and choose which sections you want to see.

Press **Command-U** to run the tests, or **Command-Period** to stop an Xcode-launched app.

## Build From Your Terminal

From the repository root, build and launch:

```sh
xcodebuild -project LeetBar.xcodeproj -scheme LeetBar -configuration Debug -destination 'platform=macOS' -derivedDataPath .build build
open .build/Build/Products/Debug/LeetBar.app
```

Quit an existing copy before launching a rebuilt app. Run the tests with:

```sh
xcodebuild -project LeetBar.xcodeproj -scheme LeetBar -destination 'platform=macOS' -derivedDataPath .build test
```

### Build a Universal release

The Release configuration builds both `arm64` (Apple silicon) and `x86_64` (Intel),
even when building on an Apple silicon Mac:

```sh
xcodebuild -project LeetBar.xcodeproj -scheme LeetBar -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath .build/universal build
lipo -archs .build/universal/Build/Products/Release/LeetBar.app/Contents/MacOS/LeetBar
codesign --verify --deep --strict .build/universal/Build/Products/Release/LeetBar.app
```

The architecture check should print `x86_64 arm64` (order may differ). The project
uses ad-hoc signing for local builds; this is not Developer ID signing or Apple
notarization. Release builds exclude the debugger entitlement. Rosetta tests on
Apple silicon can exercise the Intel build but do not replace physical Intel
hardware testing or testing every supported macOS version.

The included Xcode project is ready to build. If you change [project.yml](project.yml) or add/remove source files outside Xcode, regenerate it using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

If needed, install XcodeGen with Homebrew:

```sh
brew install xcodegen
```