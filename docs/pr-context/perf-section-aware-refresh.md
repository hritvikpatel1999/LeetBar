# PR Context: Section-aware refresh and completed-day caching

## Summary

Previously, every refresh fetched all dashboard data even when optional sections
were hidden. This change skips disabled sections, caches slower-changing data,
loads newly enabled sections, and caches confirmed daily completion until UTC reset.
Launch-at-login behavior is not included.

## Key Decisions

| Decision | Rationale | Alternatives considered | Impact and tradeoffs |
| --- | --- | --- | --- |
| Derive requests from visible data dependencies | Hidden optional sections need no data; the dashboard still displays streak and rating | Visibility-only toggles were the previous behavior | Hiding the menu-bar streak does not disable the dashboard's streak request |
| Use per-section in-memory refresh intervals | Avoid repeatedly requesting slowly changing data | Fetch every endpoint on every refresh | Refresh respects cache freshness; study plans can be five minutes old, contests and rating one hour old |
| Cache completed daily challenges until UTC reset | Completion is stable for the challenge day | Continue one-minute requests after completion | Requires a valid server challenge date matching the current UTC day |
| Confirm streak increases using server samples | A cached count can predate a delayed server update | Incrementing locally or treating a stable count as confirmation | Unconfirmed streaks continue polling, including when first launched after completion |
| Clear caches across account changes and reconnects | Do not reuse data belonging to another account or session | Persistent caching was not implemented | App restarts also lose cache savings |

## Key Flows

### Refresh and preference changes

1. Read saved visibility preferences before the first connection or restored refresh.
2. Select enabled sections whose caches are missing, expired, or eligible for retry.
3. Verify the account, then fetch only the selected sections. An observed account
   change invalidates existing caches.
4. Merge fetched sections into the dashboard without discarding skipped sections.
   Ordinary section failures remain visible and can retry after one minute;
   rate limiting stops the fetch cycle and imposes five-minute backoff.
5. Enabling a section requests missing or stale data without the ordinary refresh
   cooldown. Changes during a fetch are queued; disabling a queued section removes
   it. Work already underway may finish fetching a section subsequently hidden.

### Completed-day caching

1. Incomplete or unknown completion status retains the normal one-minute cadence.
2. Confirmed completion with a valid current challenge date skips daily requests
   until 00:00 UTC, independently of the Mac's local midnight.
3. A higher server-reported streak than an earlier same-day sample, together with
   completion, confirms the streak cache for that challenge day.
4. Invalid or stale dates, unknown completion, and unconfirmed streak updates do
   not receive day-long caching. UTC reset makes daily and streak data eligible
   for normal refresh again.

## FAQs

### What is the measured request impact?

The mock-transport tests simulate 60 refresh opportunities one minute apart,
including a cold connection, one submission page per fetch, and no errors or
restarts. These are request counts, not measured latency or battery improvements.

| Scenario | Original requests | New requests | Reduction |
| --- | ---: | ---: | ---: |
| All enabled; daily remains incomplete | 420 | 254 | 39.5% |
| Study Plans disabled; daily incomplete | 420 | 242 | 42.4% |
| Today, Contests, Study Plans disabled; daily incomplete | 420 | 181 | 56.9% |
| All enabled; completed at launch; streak unconfirmed | 420 | 195 | 53.6% |
| All enabled; completion at minute 1; streak update at minute 2 | 420 | 139 | 66.9% |

### What remains unchanged?

There is no new background polling, dependency, or credential storage mechanism.
Quick Links remain local-only. Account verification still occurs for each fetch
cycle. Manual session-cookie onboarding and the existing unnotarized preview
distribution remain documented operational risks.

### How was this validated?

The full Xcode scheme build and all 60 tests passed before PR creation, including
request counts, cadence boundaries, in-flight toggles, rate limits, delayed streak
updates, UTC rollover, local-day activity validity, and cache invalidation.
`git diff --check` also passed.

A security review reported no vulnerabilities in the changes. A separate local
credential-pattern scan found no matches across 32 tracked paths and 58 historical
blobs from 27 reachable commits at the time of the scan. Neither check guarantees
the absence of all vulnerabilities or secrets.

### How can this be diagnosed or rolled back?

The dashboard displays fetch errors and a last-refresh-check timestamp.
[AccountStoreTests.swift](../../LeetBarTests/AccountStoreTests.swift) contains the
deterministic cache and request-count cases. Revert the performance implementation
commit to restore the previous fetch behavior. No data migration is needed.

For user-facing cache intervals and caveats, see the
[README](../../README.md#network-usage-and-refresh).
