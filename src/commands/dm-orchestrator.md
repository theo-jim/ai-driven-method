---
description: Conduct story framing or one ticket cycle — checkpoints kept
argument-hint: <story id> [ticket id]
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - AskUserQuestion
  - Agent
  - Bash
---
# dm-orchestrator — Conductor (two modes)

Target: $ARGUMENTS

You conduct; you never do a phase's work inline when a subagent owns it, and you never write application code yourself. Checkpoints are real AskUserQuestion calls. This is a conductor, not an autopilot.

Resolve the first argument to `<story-id>` against docs/stories.md. If a second argument is present, resolve it to `<ticket-id>` against docs/plans/<story-id>.md.

---

## Mode A — `/dm-orchestrator <story>` (framing)

### Phase 0 — Prerequisites (fail-closed)
1. docs/prd.md exists? Missing → STOP, and point to the right entry command. Same predicate as /dm-status: source files outside `docs/` **and** a git history of more than one commit means the project predates driven → "run /dm-continue first (existing project), then /dm-prd". Otherwise the repo is empty → "run /dm-prd".
2. docs/stories.md exists? Missing → STOP: run /dm-stories.
3. docs/architecture.md exists? Missing → STOP: run /dm-architect.
4. docs/reviews/stories.md says `Stories ready: yes`? Warn if missing/negative (don't hard-stop).

Invoke `worktree-manager` for `.worktrees/<story-id>` on `feature/<story-id>` from the integration branch. Every framing phase uses that worktree.

### Phase 1 — Research
Follow the `/dm-research` contract if docs/research/<id>.md is missing. **No `require-ready`.**

### Phase 2 — Design (UI only)
Follow `/dm-design` when the story has UI and docs/designs/<id>.md is missing. Fail-closed on docs/design-system.md.

### Phase 3 — Plan + checkpoint
Follow `/dm-plan`: tickets with `size` (XS–XL) and `estimate` (0.5 steps). AskUserQuestion "Validate this plan?" — options: Validate / I'll review it first (same as `/dm-plan`). On Validate: `validated: yes` + `issue-create-ticket` for each child (see /dm-plan).

### Phase 4 — Docs
Follow `/dm-docs`: write docs/product/<id>.md. **No wiki push. No `require-ready`.**

### Phase 5 — Hand-off
List child tickets still in `backlog` (from the plan + `bash .dm/lib/dm-board.sh status-get <story>/<ticket>` when config exists). Tell the user to move the next ticket to `ready`, then run `/dm-orchestrator <story> <ticket>` (or `/dm-execute`).

End with the backlog ticket list — do **not** start execute in Mode A.

---

## Mode B — `/dm-orchestrator <story> <ticket>` (delivery)

### Phase 0
Fail-closed: plan `validated: yes`, product doc exists (or warn to run /dm-docs), then:

```bash
bash .dm/lib/dm-board.sh require-ready <story-id>/<ticket-id>
```

Worktree: `.worktrees/<story-id>/<ticket-id>` on `feature/<story-id>/<ticket-id>`.

### Phase 1 — Execute
Same as `/dm-execute`: `status-set … "in progress"`, delegate `implementer` for that ticket only.

### Phase 2 — Review
Same as `/dm-review` for `<story-id> <ticket-id>`. Gate: `Ship allowed: no` → fix loop via execute (max 2).

### Phase 3 — Ship checkpoint
AskUserQuestion: "Ship now?" — Ship / Not now. Only explicit Ship runs `/dm-ship` (pull/merge request into the integration branch; after MERGED: `status-set … test` + `parent-sync`).

End with the ship outcome for this ticket (PR/MR URL or merged + board test).
