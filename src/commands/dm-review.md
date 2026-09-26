---
description: Review one child ticket in a fresh-context subagent. Gate before Ship.
argument-hint: <story id> <ticket id>
allowed-tools:
  - Read
  - Grep
  - Agent
  - Write
  - Bash
---
# dm-review — Delegated ticket review + gate

Target: $ARGUMENTS

## Execution contract (non-negotiable)
You MUST complete this command by delegating to the `reviewer` subagent (fresh context). You are FORBIDDEN from:
- Judging the code yourself: you are probably the context that produced it.
- Modifying source code. Your only write right is the report `docs/reviews/<story-id>/<ticket-id>.md`.
- Unblocking Ship if a critical or major issue is reported.

If you can't invoke the Agent tool, stop and report the error. Don't improvise.

## Fix tickets
If `$ARGUMENTS` is a single `fix/<id>` (or resolves to an existing
`docs/plans/fix-<id>.md`), this is a **fix ticket**: treat
`<story-id>/<ticket-id>` everywhere below as `fix/<id>`,
`feature/<story-id>/<ticket-id>` as `fix/<id>`,
`.worktrees/<story-id>/<ticket-id>` as `.worktrees/fix/<id>`,
`docs/plans/<story-id>.md` as `docs/plans/fix-<id>.md`, and
`docs/reviews/<story-id>/<ticket-id>.md` as `docs/reviews/fix/<id>.md`. A fix
has no parent story: skip any step that references cross-ticket dependencies
in the story plan. The reviewer subagent prompt below adapts the same way —
diff is `git diff <integration-branch>...fix/<id>`, judged against
`docs/plans/fix-<id>.md`, and the report is written to
`docs/reviews/fix/<id>.md`.

## Workflow

### Step 1 — Delegate
Resolve $ARGUMENTS to `<story-id>` and `<ticket-id>`.
Board gate (child only), same as execute:
```bash
bash .dm/lib/dm-board.sh require-ready <story-id>/<ticket-id>
```
Exit non-zero → STOP: move the child to `ready` on the Project board first (parent US never uses `ready`).
Locate `.worktrees/<story-id>/<ticket-id>`, verify branch `feature/<story-id>/<ticket-id>`, and use that absolute worktree. Missing → STOP.
Invoke the Agent tool:
- subagent_type: reviewer
- description: Anti-hallucination review of <story-id>/<ticket-id>
- working directory: the absolute ticket worktree
- prompt: Review ticket <ticket-id> of story <story-id>. Diff is `git diff <integration-branch>...feature/<story-id>/<ticket-id>` (resolve `<integration-branch>` with `.dm/lib/dm-gate.sh default-integration-branch`) — judge only that diff against the ticket section in docs/plans/<story-id>.md, docs/research/<story-id>.md when present, AGENTS.md and ADRs. When design docs exist, check design-system conformity for UI tickets. Run the test suite yourself. Fill templates/review-checklist.md, classify issues, end with exact lines "Max severity: …" and "Ship allowed: yes|no". A single critical or major = Ship allowed: no.

### Step 2 — Report
Write the full report to `docs/reviews/<story-id>/<ticket-id>.md`. It MUST end with `Max severity: …` and `Ship allowed: yes` or `Ship allowed: no`.

### Step 3 — Gate (fail-closed)
- CRITICAL or MAJOR → "Ship blocked. Fix via /dm-execute <story-id> <ticket-id> (fix mode), then rerun /dm-review …"
- Otherwise → "Review passed. Next step: /dm-ship <story-id> <ticket-id>"
