# PR Context: Publish the MIT license

## Summary

Publish the pending [MIT license](../../LICENSE) and [README licensing notice](../../README.md) for LeetBar's original source code and documentation. The notice excludes the bundled LeetCode logo images and grants no rights to LeetCode's names, logos, or trademarks.

## Key Decisions

| Decision | Rationale | Alternatives considered | Impact and tradeoffs |
| --- | --- | --- | --- |
| Publish the standard MIT license | The owner requested MIT licensing and publication of the prepared changes. | Other licenses were not requested. | Reuse is permitted under the license's terms, including retaining the copyright and permission notices. |
| Keep third-party branding outside the MIT grant | The project does not own LeetCode's branding. | Replacing the logos was discussed previously; the owner chose to retain them. | Logos remain unchanged. The exclusion does not establish permission to use them or imply endorsement. |

## Key Flows

1. A repository reader follows the README's MIT License link to the root license text.
2. The same notice identifies the third-party branding excluded from the license grant.

No runtime flow changes are introduced.

## FAQs

### What remains unchanged?

Application code, logo assets, account handling, build configuration, and branch protections remain unchanged. Existing downloadable release assets are not rebuilt or replaced.

### How was this validated?

The pending license text and the licensing-only README diff were inspected. Validation for publication covers the standard MIT wording, relative documentation links, the exact PR file scope, and secret scanning. Application tests are not run for this documentation-only update.

### Does the MIT license grant rights to LeetCode branding?

No. The README explicitly excludes the bundled LeetCode logo images and grants no rights to LeetCode's names, logos, or trademarks. Those remain subject to their owners' rights.