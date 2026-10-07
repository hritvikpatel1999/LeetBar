# LeetBar

A native macOS menu-bar starter for LeetCode quick checks, built with Swift and SwiftUI.

Connect your LeetCode account to fetch your contest rating, the daily challenge, current LeetCode streak, today's submissions and distinct solves, and upcoming contests. The header shows your clickable username above your contest rating. Google sign-in happens on LeetCode in your normal browser; LeetBar stores only your LeetCode session and CSRF cookie in macOS Keychain. It never requests your Google password, Google tokens, or Gmail access.

The integration uses unofficial LeetCode website endpoints. Public daily and contest fields were checked live; private requests need your own session. The current streak uses LeetCode's authenticated counter rather than an estimate from recent submissions. All-time best streaks are not provided by the verified query and are omitted from the live view. Local sample data is still available as an explicit preview mode.

## Connect your account

1. Open the menu-bar dropdown, click the gear, and select Open LeetCode Sign-In.
2. On LeetCode, choose Google and sign in with the Google account linked to your LeetCode profile. You can also use another sign-in method supported by LeetCode.
3. Stay on a signed-in leetcode.com page. In Chrome, open Developer Tools with Option-Command-I, then choose Application. It may be inside the overflow menu.
4. Under Storage, expand Cookies and select https://leetcode.com.
5. Find the cookie named LEETCODE_SESSION. Copy only its Value and paste it into the matching masked field in LeetBar Settings.
6. Do the same for csrftoken from the same browser session, then click Connect. Do not copy an entire Cookie header.
7. LeetBar verifies the session, saves it to Keychain, and fetches your data. Your LeetCode username appears when account validation succeeds. Section-specific failures stay visible rather than becoming zeroes.
8. Clear your clipboard after pasting. Never put cookie values into chat, source code, screenshots, logs, or GitHub issues. The cookie provides account access and must be treated like a password.

Cookie values are entered directly into the app, not through an assistant or a terminal command. The fields are cleared after Connect and when Settings closes. Safari and other browsers have different developer-tool menus; Chrome is the documented setup path.

Opening the live dropdown refreshes when at least a minute has passed; its refresh button lets you request another update after that cooldown. There is no continuous background polling. Cached dashboard data is kept only in memory, with a last-checked timestamp. Today's cached totals disappear after a local day boundary until refreshed.

If your browser session expires, use fresh values and Reconnect. Disconnect deletes LeetBar's Keychain item, cancels pending requests, and clears the in-memory account data. It does not sign your browser out or revoke the session on LeetCode's servers.

The Keychain item is labeled LeetBar LeetCode Session, with service dev.leetbar.leetcode-session and account leetcode.com. It uses the local login Keychain and is not marked for iCloud synchronization. During local development, macOS may request permission to access it, especially after a rebuild changes the app signature. Only approve a prompt for the LeetBar app you built; enter any requested Mac password in the macOS dialog, never in chat.

LeetBar sends credentials only to the fixed HTTPS leetcode.com GraphQL endpoint, rejects redirects, and disables persistent HTTP cookie storage and response caching. It issues read-only GraphQL queries, but the underlying session is not a read-only-scoped credential. Google OAuth for a separate LeetBar client would not grant access to LeetCode; this is a manual browser-session handoff, not a one-click OAuth integration. Review [LeetCode's terms](https://leetcode.com/terms/) before using or distributing an integration based on its website endpoints.

## Quick Links

Quick Links is a collapsible section beneath Upcoming Contests. It starts as a single header with the number of saved links. Expand it to open a bookmark using the entire row; long titles truncate and hovering shows the full title and destination. Empty Quick Links offers an Add Quick Link action that opens Settings.

In Settings, the Quick Links section supports up to four entries. Add a title and an http:// or https:// URL, then Save. Use the pencil to edit, the arrows to reorder, and the trash icon to remove an entry. Cancel leaves the saved entry unchanged. Adding is disabled at four links, but editing and removing remain available.

Links are stored locally in UserDefaults, separately from the LeetCode session, and survive app restarts. They work without a connected account and are not cleared by Disconnect. Sample mode uses the same personal bookmarks. Destinations open in your default browser, which handles its own login. LeetBar does not read or synchronize spreadsheet contents, download favicons, or fetch link previews. Local files and custom URL schemes are not supported. Avoid putting credentials or private access tokens in bookmark URLs; these preferences are not secret storage.

## Run it in Xcode

1. Open [LeetBar.xcodeproj](LeetBar.xcodeproj).
2. In Xcode's top toolbar, select the LeetBar scheme and My Mac destination.
3. If a separately launched copy of LeetBar is already running, quit it using the power button in its dropdown.
4. Press Command-R to build and run.
5. Look in the macOS menu bar for the LeetCode logo. The app intentionally has no Dock icon or main window. After opening the dropdown to refresh, the current streak appears beside the icon when Show streak count is enabled. Dashes mean the count has not loaded or is unavailable.
6. Click the icon to see Daily Problem, Today, and Upcoming Contest.
7. Click the gear to connect your account. For a UI preview without credentials, set Data source to Local sample data and select a sample state. The preview header uses @sample-user and marks its fictional rating as sample data.
8. Press Command-U in Xcode to run the tests. Stop an Xcode-launched app with Command-Period.

If Xcode's editor is open but the menu-bar icon is absent, make sure you have run the project, not just opened it. macOS can hide status items when the menu bar is crowded; switching to an app with fewer menus can make more room.

Preferences persist in UserDefaults; account credentials persist only in Keychain. In preview mode, the pending sample has 7 submissions, 3 distinct problems solved, and a fictional 7-day streak. The completed sample has 8 submissions, 4 distinct solves, and a fictional 8-day streak. The sample daily problem and contest date are not live LeetCode data.

## What you are learning

**Swift** is the programming language. **SwiftUI** is Apple's framework for declaring interfaces. **Xcode** is the editor, build tool, debugger, and preview host. Use Xcode for your first build/run loop; VS Code remains an option for editing text.

The app source files have these responsibilities:

| File | Responsibility |
| --- | --- |
| [LeetBarApp.swift](LeetBar/LeetBarApp.swift) | App entry point, menu-bar item, shared preferences, and Settings scene. |
| [DashboardView.swift](LeetBar/DashboardView.swift) | The dropdown's layout and browser links. Start your UI edits here. |
| [DashboardData.swift](LeetBar/DashboardData.swift) | Sample states, submission records, and the daily-count calculation. |
| [SettingsView.swift](LeetBar/SettingsView.swift) | Masked session entry, connect/disconnect, data-source selection, and preferences. |
| [LeetCodeSession.swift](LeetBar/LeetCodeSession.swift) | Cookie validation, redacted credential descriptions, and Keychain storage. |
| [LeetCodeClient.swift](LeetBar/LeetCodeClient.swift) | Read-only requests, response decoding, paginated submissions, and errors. |
| [AccountStore.swift](LeetBar/AccountStore.swift) | Shared account state, connection validation, refresh, and cancellation. |
| [QuickLinksStore.swift](LeetBar/QuickLinksStore.swift) | Validated, ordered, local bookmarks with a four-link limit. |

A View describes what the UI should look like for its current data. Its body combines smaller views. VStack arranges them vertically, HStack horizontally, and modifiers such as padding or font adjust their presentation.

MenuBarExtra creates the status item. The window style gives it a custom dropdown. The LSUIElement setting makes this a menu-bar-only app rather than a normal Dock app.

AppStorage persists simple preferences in macOS UserDefaults. Binding lets a child view edit a value owned by its parent: Settings edits the same scenario the app uses. State keeps a local value stable while a view exists; here it anchors the sample date. SwiftUI updates the affected UI when state changes.

AccountStore is shared between the scenes through StateObject and ObservedObject. Published properties update the UI after asynchronous network work. A connection is saved only after the account endpoint confirms a signed-in user. Failed validation does not overwrite a previously saved session.

## Your first edits

1. In [DashboardView.swift](LeetBar/DashboardView.swift), change the preview username from @sample-user to @learning-swift. Switch to Local sample data in Settings, run again, and find the change.
2. Change a spacing or padding value in that view, then compare the result. Keep the panel compact.
3. In [DashboardData.swift](LeetBar/DashboardData.swift), add another sample accepted submission for an already-solved problem. Predict what happens: submissions should increase, but distinct solves should not.
4. Run Command-U. The fixture expectation test should now fail because its expected submission count changed. Update the expectation deliberately; keep the distinct-solve assertion intact.

The #Preview declaration at the bottom of the dashboard can also show the view in Xcode's Canvas. The real menu-bar app remains the source of truth for window and Settings behavior.

## How the numbers work

Contest rating comes from userContestRanking for the verified signed-in username and is rounded to a whole number for display. A valid null ranking or zero attended contests displays Unrated. Failed or malformed responses display dashes and an error rather than a zero or an unrated claim. The header shows contest rating, not profile rank or global contest rank; rating refreshes with the dashboard.

DailyStats counts all attempts in the selected calendar day, then counts distinct problem slugs among accepted attempts. Repeat accepts count as multiple submissions but one solved problem. A previously solved problem accepted again today counts as a solve today; this is not a first-ever-solves metric.

Tests in [DailyStatsTests.swift](LeetBarTests/DailyStatsTests.swift) cover counting and day boundaries. [LeetCodeClientTests.swift](LeetBarTests/LeetCodeClientTests.swift) covers credential validation, a disposable Keychain round trip, identity validation, error handling, pagination, and partial data. [AccountStoreTests.swift](LeetBarTests/AccountStoreTests.swift) covers connect/disconnect, persistence failures, and cancellation races. Tests use fake credentials and responses, never your account; the Keychain test creates and removes its own uniquely named dummy item.

[QuickLinksTests.swift](LeetBarTests/QuickLinksTests.swift) covers URL/title validation, the four-link limit, editing, removal, ordering, and persistence using disposable preferences suites rather than your bookmarks.

Submission pages are fetched until the local day boundary or the end of the list. Duplicate IDs are removed; unexpected ordering, missing pages, or a 25-page safety limit produce unavailable totals rather than partial counts advertised as exact. Results reflect the refresh snapshot, not a continuous activity stream.

The daily completion status comes from the challenge's userStatus field, not the problem's lifetime solved status. Unknown values stay Unknown. The challenge's server-provided date is displayed separately from your local practice date.

The LeetCode streak comes directly from streakCounter.streakCount and is shared by the dropdown and menu-bar label. It is not calculated from the profile activity calendar, recent submission counts, or the daily problem's completion flag. A real zero is displayed as zero; missing, invalid, or failed counter responses stay unavailable without hiding the other dashboard sections. This query does not provide an all-time best, so the live view does not show one.

## Build from the terminal

The checked-in Xcode project is sufficient for normal development. This starter targets macOS 14 or later and Swift 6. It was verified with Xcode 26.5 on an Apple Silicon Mac.

From this folder:

```sh
xcodebuild -project LeetBar.xcodeproj -scheme LeetBar -configuration Debug -destination 'platform=macOS' -derivedDataPath .build build
open .build/Build/Products/Debug/LeetBar.app
```

Run tests:

```sh
xcodebuild -project LeetBar.xcodeproj -scheme LeetBar -destination 'platform=macOS' -derivedDataPath .build test
```

[project.yml](project.yml) is the readable project configuration. XcodeGen 2.45 or later generates the Xcode project from it. If you add or remove source files outside Xcode, or change that configuration, run the following and reopen the project:

```sh
xcodegen generate
```

If XcodeGen is missing on another Mac, install it with Homebrew using brew install xcodegen. It is not needed just to open and run the existing project. Keep both the configuration and generated Xcode project when sharing the source. Regeneration overwrites project settings edited only inside Xcode, so make durable configuration changes in the YAML file.

Signing is configured as Sign to Run Locally. No paid Apple developer account is required for this local build; this is not a notarized distribution build.

## Next milestones

1. Learn the edit/build/run loop and settle the dropdown layout with sample data.
2. Connect your own account and compare its live counts and daily status with the website.
3. Verify historical streak data before adding an all-time best. Add a reset countdown and opt-in reminders after verifying their rules.
4. Add launch-at-login support and test sleep/wake, calendar rollover, and offline behavior.
5. Before publishing, review the integration terms and branding, choose an open-source license, and check for private data. Signing, notarization, and updates are separate work if distributing a downloadable app.

The app requires no backend, paid services, or third-party runtime dependencies. Build products, Xcode user-specific state, local MCP configuration, and private signing keys are excluded by [.gitignore](.gitignore).

## Logo assets

The bundled menu-bar and dropdown images are resized from LeetCode's hosted [light-background logo](https://leetcode.com/static/images/LeetCode_logo.png) and [dark-background logo](https://leetcode.com/static/images/LeetCode_logo_rvs.png). No logo download happens at runtime. The menu-bar image is a monochrome template that adapts to macOS appearance; the dropdown uses the matching color variant.

The LeetCode name and logo belong to LeetCode. LeetBar is an independent personal utility, not an official LeetCode app. Review logo and trademark usage before public distribution.

## References

- [Apple: SwiftUI tutorials](https://developer.apple.com/tutorials/swiftui)
- [Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)