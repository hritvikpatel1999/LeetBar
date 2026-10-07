# PR Context: Make downloading LeetBar easier

## Summary

Put a no-Xcode installation section at the top of the [README](../../README.md), linking directly to the existing Preview 2 app ZIP. Replace outdated private Preview 1 instructions and separate downloaded-app requirements from source-build tools.

## Key Decisions

| Decision | Rationale | Alternatives considered | Impact and tradeoffs |
| --- | --- | --- | --- |
| Link directly to the versioned Preview 2 ZIP | The user requested fewer steps to download and use the app without Xcode. | Sending readers to the release's Assets list | No GitHub sign-in or asset selection is needed. The link must be updated when a newer preview is recommended. |
| Retain compatibility and first-launch security guidance | The existing download is Apple silicon only and not Apple-notarized. | Omitting these limitations to shorten the instructions | Readers can check compatibility and understand macOS approval before connecting their account. |

## Key Flows

1. Click the download link, open the ZIP, and drag LeetBar into Applications.
2. Open the app and find its menu-bar icon. If macOS blocks it, use the documented per-app approval only when the download is trusted; managed devices may prohibit approval.
3. Follow the account-connection link for live LeetCode data. Installing does not require Xcode, Terminal, or a GitHub account.

## FAQs

### What remains unchanged?

Application code, release assets and notes, licensing, account setup, and branch protections are unchanged. This PR does not notarize the app, add Intel support, or automate cookie-based account setup.

### How was this validated?

An unauthenticated download of the exact README URL succeeded. Its ZIP signature, byte count, and SHA-256 match the published Preview 2 asset. Focused checks verified section placement, removal of private Preview 1 instructions, retained security guidance, and whitespace. Application tests are not run for this documentation-only change.