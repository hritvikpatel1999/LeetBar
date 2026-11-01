# PR Context: Privacy-safe local diagnostics and Universal Preview 4

## Summary

Add bounded local diagnostic logs and a Settings panel for verbose opt-in, ZIP export,
Finder access, and clearing history. Instrument startup, authentication, network requests,
cache decisions, and login-item changes without recording credentials or account content.
Preview 4 retains one Universal download for Intel and Apple silicon on macOS 14 or later.

## Key Decisions

| Decision | Rationale | Alternatives considered | Impact and tradeoffs |
| --- | --- | --- | --- |
| Separate always-on warnings/errors from optional verbose events | Preserve failure evidence without collecting routine activity by default | One combined log was discussed; two files were requested | Warnings/errors enter both files only while verbose is enabled |
| Retain startup metadata in both files even with verbose off | Startup diagnosis was an explicit priority | Suppressing all informational events by default | Records app/build, macOS version, architecture, timestamps, and a random session ID |
| Accept only fixed events/reasons/operations and numeric or random-ID fields | Avoid credential and personal-data exposure through logs | Raw headers, bodies, variables, and arbitrary error text were explicitly excluded | Failures use sanitized categories; users may need verbose logging to reproduce a problem |
| Cap each file at 5 MiB with seven-day retention | Bound long-running disk use and record eviction notices | Rotating backup files would expand the two-file footprint | Removes oldest complete entries; user-exported ZIPs are not governed by the cap |
| Synchronize writes and drain the serial queue on graceful lifecycle stops | Preserve pending diagnostics at normal shutdown and sleep | Waiting until quit to write everything was discussed | Disk I/O stays on a utility queue; hard stops and power loss cannot guarantee a final flush |

## Key Flows

### Startup and termination

1. The app delegate records startup metadata and marks the session active.
2. A prior active marker produces an always-on unclean-session warning.
3. Sleep and deactivation drain queued writes. Handled SIGTERM/SIGINT use normal application termination.
4. Normal termination drains the shutdown event and clears the active marker. Forced stops are best-effort only.

### Authentication and requests

1. Production stores and the HTTP client receive the shared logger; test defaults remain disabled.
2. Saved-session restore, verification, save, expiry, disconnect, and failures emit structured events.
3. Refresh tasks carry a random cycle ID; requests have separate random IDs and fixed operation names.
4. HTTP completion records status, elapsed time, response bytes, and sanitized failure categories.
   GraphQL errors are classified before attempting to decode partial data as a successful payload.
5. Cache/disabled-section decisions are verbose-only. Existing request cadences and counts remain unchanged.

### Diagnostics controls

1. Verbose logging is off by default and changes through Settings.
2. Clear confirms destructive removal of historical entries, retaining current startup metadata.
3. Export snapshots both files plus a version-only diagnostic summary on the logger queue.
4. ZIP creation runs off the main actor. The user chooses the destination; nothing is uploaded.
5. Storage and action failures remain visible in Settings. Unsafe log-file symlinks are rejected.

## FAQs

### Does this refresh authentication tokens automatically?

No. The app still reuses manually supplied LeetCode cookies stored in the local macOS Keychain.
Instrumentation describes the actual restore/verification/reconnect flow, not a nonexistent token-refresh API.

### What does the export exclude?

Cookies, CSRF tokens, raw headers/bodies, GraphQL variables, usernames, account statistics,
personal links, and arbitrary server/system error descriptions. Timestamps and system versions
are still diagnostic information: review exports before sharing.

### What remains unchanged?

Menu-bar behavior, manual account connection, launch-at-login opt-in, section-aware caching,
daily/streak confirmation logic, and macOS 14 minimum support. There is no background polling
or automatic diagnostics upload.

### How was this validated?

The 92-test suite passed natively on arm64 and under Rosetta x86_64, including the existing
performance request-count matrix. New tests cover routing, opt-out after storage failure,
concurrent writes/flush, strict size limits, preexisting oversized files, retention, lifecycle
markers, clear/export, unsafe paths, visible failures, auth expiry/Keychain error categories,
request correlation, and credential/error sentinels absent from files and exports.
Universal slices, strict code signature, and whitespace were also checked. Physical Intel
hardware and an actual sign-out/sign-in lifecycle were not tested.

### What are the release limitations?

The Universal preview is ad-hoc signed, not Developer ID signed or Apple-notarized. Managed
Macs may prevent approval. This PR does not bypass macOS security protections or change the
unofficial LeetCode API dependency.

### How can this be diagnosed or rolled back?

Enable verbose logging before reproducing, then use Settings to inspect/export the local logs.
Disable verbose collection afterward or clear history. Reinstall Preview 3 to roll back the
app; diagnostics remain local unless explicitly cleared. No account-data migration is added.
