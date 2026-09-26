---
description: Implement one child ticket in TDD via the implementer subagent
argument-hint: <story id> <ticket id>
allowed-tools:
  - Read
  - Glob
  - Agent
  - Bash
---
# dm-execute — Delegated ticket implementation

Target: $ARGUMENTS

## Execution contract (non-negotiable)
You MUST complete this command by delegating to the `implementer` subagent. You are FORBIDDEN from:
- Writing or modifying code yourself — you don't have the Write/Edit tools, on purpose.
- Starting without a validated plan and a child Issue that is ready (or already in progress).
- Running from the repository base directory.
- Creating or checking out the ticket branch in the repository base directory.
- Summarizing work the agent didn't actually do.

If you can't invoke the Agent tool, stop and report the error. Don't improvise.

## Fix tickets
If `$ARGUMENTS` is a single `fix/<id>` (or resolves to an existing
`docs/plans/fix-<id>.md`), this is a **fix ticket**: treat
`<story-id>/<ticket-id>` everywhere below as `fix/<id>`,
`feature/<story-id>/<ticket-id>` as `fix/<id>`,
`.worktrees/<story-id>/<ticket-id>` as `.worktrees/fix/<id>`,
`docs/plans/<story-id>.md` as `docs/plans/fix-<id>.md`, and
`docs/reviews/<story-id>/<ticket-id>.md` as `docs/reviews/fix/<id>.md`. A fix
has no parent story: resolve it directly against `docs/plans/fix-<id>.md`
(skip the `docs/stories.md` lookup in step 1), and skip step 1.6 (ticket
dependencies) — a standalone fix has no cross-ticket dependencies to check.

## Workflow

### Step 1 — Prerequisites (fail-closed)
1. Resolve $ARGUMENTS to `<story-id>` and `<ticket-id>` (`s<number>-<slug>` and `t<number>-<slug>`) against docs/stories.md and docs/plans/<story-id>.md. Ambiguous → list matches, STOP.
2. Board gate (child only):
   ```bash
   bash .dm/lib/dm-board.sh require-ready <story-id>/<ticket-id>
   ```
   Exit non-zero → STOP: move the child to `ready` on the Project board first (parent US never uses `ready`).
3. Then mark in progress:
   ```bash
   bash .dm/lib/dm-board.sh status-set <story-id>/<ticket-id> "in progress"
   ```
4. Invoke `worktree-manager` for `.worktrees/<story-id>/<ticket-id>` on `feature/<story-id>/<ticket-id>` from **the integration branch**. Continue only after the absolute path and exact branch are confirmed.
5. From that worktree, read docs/plans/<story-id>.md. Frontmatter must contain `validated: yes`. Otherwise STOP.
6. Ticket dependencies in the plan that are not yet `test` or `shipped` → STOP and name them.
7. If `docs/reviews/<story-id>/<ticket-id>.md` contains `Ship allowed: no`, this is a FIX run: those findings come first.

### Step 2 — Delegate
Invoke the Agent tool:
- subagent_type: implementer
- description: Implement ticket <story-id>/<ticket-id> in TDD
- working directory: the absolute ticket worktree path
- prompt: Implement ticket <ticket-id> of story <story-id> from docs/plans/<story-id>.md (only that ticket's tasks), following docs/architecture.md and AGENTS.md. Read docs/research/<story-id>.md when it exists. Strict TDD task by task. One single commit at the end of the ticket. Do not create a worktree or switch branches.
- On a FIX run, prepend: Fix every critical and major finding from docs/reviews/<story-id>/<ticket-id>.md first, test-first.

### Step 3 — Report
Summarize: tasks done, files touched, tests added, blockers.

End with: "Implementation done. Next step: /dm-review <story-id> <ticket-id>"
