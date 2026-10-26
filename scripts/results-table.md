# Red-team run — results

**Target:** `<url>` **Environment:** local / preview **DB:** `<db>` (confirmed non-prod by: `<how>`)
**Run id:** `<run-id>` **Accounts:** A / B / admin (per group) **Date:** `<date>`
**Ownership:** `<local-default | user asserted ownership of non-local target>`

> The **main agent is the sole writer** of this file — it merges the rows each
> subagent returns. Subagents never write here. Mask every token, cookie, and key
> (`$VAR`, never the value). `Result` ∈ VULNERABLE · PASS (correctly refused) ·
> NOT PROVEN (did not execute) · N/A (no such feature / prerequisite unmet).

## Headline — before / after (the deliverable)

**_N_ vulnerable · _N_ fixed · _N_ not proven · _N_ N/A**

For each item that was VULNERABLE, prove the fix: with the guard **off** (clean
revert of the fix, local) the attack must succeed; with it **on** it must be
refused. Stateful attacks (4, 6, 7) use fresh state each run.

| # | Attack | Severity | Before | After | Evidence (off → on) | Env (before / after) | Fix (file:line) |
|---|--------|----------|--------|-------|---------------------|----------------------|-----------------|
|   |        |          |        |       |                     |                      |                 |

## Attack log

| # | Attack | How it was run | Request (masked) | Response | Expected-safe response | Result |
|---|--------|----------------|------------------|----------|------------------------|--------|
| 1 | Anon-key table sweep |  |  |  | empty / permission error |  |
| 2 | IDOR — read B |  |  |  | 403 / 404 / scoped-empty |  |
| 2 | IDOR — edit B |  |  |  | 403 / 404 |  |
| 2 | IDOR — delete B |  |  |  | 403 / 404 |  |
| 3 | Privilege escalation (role) |  |  |  | field ignored (allow-list) |  |
| 4 | Reset token reuse |  |  |  | replay rejected |  |
| 5 | Client-only gating |  |  |  | 403 server-side |  |
| 6 | Quota bypass via API |  |  |  | quota / 429 |  |
| 7 | Credit race |  |  |  | successes ≤ balance; ≥0 |  |
| 8 | Input validation |  |  |  | validated / rejected |  |
| 9 | Open redirect |  |  |  | same-origin only |  |
| 10 | Stored XSS |  |  |  | escaped as text |  |
| 11 | SSRF |  |  |  | blocked (allow-list/filter) |  |
| 12 | Broken access / cache |  |  |  | 403 / scoped to caller |  |
| 13 | Unprotected preview |  |  |  | auth required |  |
| 14 | Prompt injection |  |  |  | treated as data; in-scope |  |

## Not proven / skipped

List anything that did not actually execute, and why (no browser, logs
unreachable, feature absent, preview possibly prod). These are neither safe nor
vulnerable until run.
