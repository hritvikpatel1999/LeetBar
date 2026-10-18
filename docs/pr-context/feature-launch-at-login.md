# PR Context: Launch at login and Universal Preview 3

## Summary

Add an opt-in Launch at login setting and package Preview 3 as one Universal app
for Apple silicon and Intel Macs running macOS 14 or later. The release includes
the performance improvements already merged in PR #4.

## Key Decisions

| Decision | Rationale | Alternatives considered | Impact and tradeoffs |
| --- | --- | --- | --- |
| Use `SMAppService.mainApp` | Native API supports the existing macOS 14 minimum without a helper app | A helper or custom LaunchAgent is unnecessary for this feature | macOS may require user approval; no automatic registration occurs |
| Read system status, not a saved Boolean | Login Items can change outside LeetBar | A preference alone can become stale | Refresh on Settings appearance and app activation; pending approval is distinct from enabled |
| Display pending registration as an on toggle with approval text | The user has requested registration but macOS has not authorized launch | Reporting it as fully enabled would be misleading | Automatic startup still requires approval in System Settings |
| Build one Universal Release app | Both Mac architectures use the same installer instructions | Separate architecture ZIPs were not selected | Explicit `arm64 x86_64` Release architectures; larger download |
| Continue ad-hoc-signed previews | No local Developer ID signing identity is available | Developer ID signing and notarization require separate setup | Gatekeeper approval may be required; no notarization claim |

## Key Flows

### Launch-at-login registration

1. Read the native status without registering on launch.
2. The user explicitly toggles Launch at login in Settings > General.
3. Register or asynchronously unregister the main app; disable the toggle while
   work is in progress, then reread actual macOS status.
4. Display errors and approval-required status. The System Settings button opens
   Login Items; returning to LeetBar refreshes the displayed status.
5. Unregistering prevents later login launches without quitting the current app.

### Universal release

1. Generate the project from `project.yml`; Release builds both architectures,
   uses build number 3, and excludes debugger base entitlements.
2. Run the full Release tests on Apple silicon and run the same Universal test
   bundle for `x86_64` under Rosetta.
3. Verify both executable slices, macOS 14 minimum, and code signature before
   packaging the app with `ditto` and producing a SHA-256 checksum.
4. Publish `v0.1.0-preview.3` from this branch's release source commit. Main remains
   protected until this PR is reviewed and merged.

## FAQs

### How was this validated?

All 73 tests passed natively on Apple silicon and all 73 passed with the Intel
destination under Rosetta. This includes 13 fake-service login-item tests without
changing the developer's actual automatic-startup registration. Both the app and
test binary contain `x86_64` and `arm64`. Signature verification passed, and both
app slices declare macOS 14.0 as their minimum.

### What has not been validated?

Physical Intel hardware, all supported macOS releases, and automatic startup
after a real sign-out/sign-in were not tested. Launch-at-login registration from
the installed app remains an explicit user action, subject to macOS approval and
signing restrictions.

### What remains unchanged?

The app is menu-bar-only, stores its session in Keychain, uses unofficial LeetCode
endpoints, and is not sandboxed or Apple-notarized. No new network dependency,
analytics, or automatic updater is introduced.

### How can this be rolled back?

Users can disable Launch at login in LeetBar or System Settings and replace the
app with an older release. Reverting this PR restores the prior source behavior;
it does not unregister an existing macOS login item on the user's behalf.

See the [README](../../README.md) for installation, privacy cautions, and build
commands.
