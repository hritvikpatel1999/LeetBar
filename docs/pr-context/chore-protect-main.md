# PR Context: Protect main with owner-reviewed pull requests

## Summary

This PR publishes [.github/CODEOWNERS](../../.github/CODEOWNERS), assigning every file to @hritvikpatel1999, including the ownership configuration itself. Separately configured GitHub rulesets require pull requests into main and require the owner's review, with an owner-only exception for merging through a pull request.

## Key Decisions

| Decision | Rationale | Alternatives considered | Impact and tradeoffs |
| --- | --- | --- | --- |
| Protect main rather than every branch | Contributors need to push work to feature branches before opening a PR. | Applying the same rules to every branch | Feature branches remain usable; main is the controlled integration branch. |
| Keep the mandatory-PR rule separate from the review rule | The owner's review exception must not permit direct pushes to main. | One ruleset with a broad bypass | The mandatory-PR ruleset has no bypass actors and also blocks force pushes and deletion. |
| Require one approval and code-owner review | An arbitrary collaborator's approval must not substitute for the owner's approval. | One approval without CODEOWNERS | New reviewable commits dismiss stale approvals. |
| Give only @hritvikpatel1999 a pull-request-only review bypass | GitHub does not allow authors to approve their own PRs, and the owner requested no second reviewer for their own work. | A bypass for every administrator, or requiring another reviewer | The exception is based on who merges, not who authored the PR. The owner can personally merge any PR without a separate review, but must still use a PR. |

## Key Flows

1. A contributor pushes changes to a feature branch or fork and opens a PR targeting main.
2. CODEOWNERS identifies @hritvikpatel1999 as the reviewer for every changed file.
3. Without the owner's merge exception, merging requires the owner's approval. New reviewable commits invalidate earlier approvals.
4. The owner can merge a PR without obtaining another person's approval using the pull-request-only review bypass.
5. The separate mandatory-PR rule continues to reject direct pushes, force pushes, and deletion of main, including for the owner.

## FAQs

### Does CODEOWNERS enforce approval by itself?

No. The file must exist on the base branch, and an active GitHub rule must require code-owner review. The rulesets are repository settings, not configuration automatically applied from this document.

### Can the owner approve their own PR?

No. Their PR is merged using the owner-only review exception rather than a self-approval. The mandatory-PR requirement is not bypassed.

### What remains unchanged?

Application code, release assets, contributor permissions, and unrelated local documentation changes are outside this PR. No CI status checks or additional reviewer requirements are introduced.

### How is this validated?

The local CODEOWNERS file assigns all paths and the .github directory only to @hritvikpatel1999. Validation also checks GitHub's accepted ruleset definitions, effective main-branch rules, and CODEOWNERS errors. Merging this setup PR as the owner with no approving reviews exercises the intended owner workflow.

### How can this be diagnosed or changed?

Inspect Settings > Rules > Rulesets and the PR's merge requirements. Repository administrators can edit the settings; the rules do not remove the owner's administrative authority. Removing the review rule weakens owner-review enforcement, while removing the mandatory-PR rule permits direct updates, so these changes should be deliberate.