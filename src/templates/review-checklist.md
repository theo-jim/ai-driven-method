# Review — Ticket <story-id>/<ticket-id>

> For a fix ticket (branch `fix/<id>`, no parent story), substitute throughout
> this document: `<story-id>/<ticket-id>` → `fix/<id>`,
> `feature/<story-id>/<ticket-id>` → `fix/<id>`,
> `docs/reviews/<story-id>/<ticket-id>.md` → `docs/reviews/fix/<id>.md`. The
> diff is `git diff <integration-branch>...fix/<id>`. There is no per-ticket
> plan section for a fix — `docs/plans/fix-<id>.md` in its entirety is the
> ticket. Same procedure otherwise.

> Fresh-context review. Each issue classified: critical / major / minor.
> Diff reviewed: `git diff <integration-branch>...feature/<story-id>/<ticket-id>` (resolve `<integration-branch>` with `.dm/lib/dm-gate.sh default-integration-branch`)
> Report path: `docs/reviews/<story-id>/<ticket-id>.md`

## Plan compliance
- [ ] The code does what the plan specifies, nothing more
- [ ] Run interdicts respected — each one checked and named

## Anti-hallucination
- [ ] No invented API/function/import (each one opened and verified)
- [ ] No plausible-but-wrong value or logic
- [ ] The code matches what it claims to do

## Security
- [ ] No injection (SQL/command/template/shell) from untrusted input
- [ ] Authz next to the rule; no authz bypass
- [ ] No secrets in source, logs, or client bundles
- [ ] No IDOR (object access scoped by ownership)
- [ ] No XSS from unescaped user content
- [ ] No sensitive data in logs

## Factorization
- [ ] One business rule, one place (no duplicated rule or copied flow)
- [ ] No speculative abstraction; no unevolvable module introduced in this diff

## Rules compliance
- [ ] Repo conventions followed (AGENTS.md)
- [ ] No accepted ADR contradicted (docs/decisions/)
- [ ] Design system respected — components/tokens from docs/design-system.md, screen matches the intent of docs/designs/<id>.md (UI stories)

## Tests
- [ ] Test suite run by the reviewer, passing
- [ ] Assertions pin the acceptance criteria (no assertion-free tests)
- [ ] Bite proven by neutralization: <what was neutralized> → <N> tests red, restored (`git diff --exit-code` clean)
- [ ] Tests the ticket made redundant are named and removed — or their absence justified

## Regressions
- [ ] No impact on existing code paths

## Findings
<one line per issue: severity — file — what's wrong>

## Not verified
<what this review could NOT check, and why: no browser, no database, no real third-party call.
 Name the concrete gestures a human should make — the screen to open, the button to click, the
 device to test on. A review that lists nothing here is claiming it saw everything.>

## Verdict
Max severity: <critical | major | minor | none>
Ship allowed: <yes | no>

