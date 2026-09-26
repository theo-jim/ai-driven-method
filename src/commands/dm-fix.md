---
description: Frame and validate a standalone fix ticket (no parent story) — same rigor as a ticket, worktree + TDD + subagents
argument-hint: <fix description>
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Bash
  - Agent
  - AskUserQuestion
---
You are framing a **fix ticket**: a standalone, parentless ticket that gets the
full pipeline rigor (dedicated worktree, mandatory TDD via the `implementer`
subagent, review via the `reviewer` subagent, ship into the integration
branch) without a story above it. Description: $ARGUMENTS

This command replaces Research + Design + Plan + Docs for a fix — a fix has no
story-level framing, so it goes straight to a validated, board-ready ticket in
one pass.

## Step 1 — Derive the id, check for collisions
Derive a kebab-case `<id>` slug from the description (e.g. "cart total doesn't
update after removing the last item" → `cart-total-not-updating`).

Check for collisions:
- `docs/plans/fix-<id>.md` (Read/Glob)
- branch `fix/<id>` (`git branch -a`)
- worktree `.worktrees/fix/<id>` (`git worktree list`)

If none exist, this is a new fix — continue to Step 2.

If `docs/plans/fix-<id>.md` already exists and describes this same fix (a
rerun to validate, mirroring `/dm-plan`), skip straight to the Step 3
validation checkpoint.

If `docs/plans/fix-<id>.md`, branch `fix/<id>` or worktree `.worktrees/fix/<id>`
already exist for a **different** fix, this is a genuine collision: STOP and
ask the user for a more specific description, or an explicit id, to
disambiguate. Never overwrite an existing fix's plan, branch or worktree.

The derived `<id>` must be a flat kebab-case slug matching
`^[a-z0-9]+(-[a-z0-9]+)*$` — no slashes, uppercase or underscores. This keeps
`fix/<id>` a well-formed branch name that `dm-gate.sh` will accept.

## Step 1.5 — Create or verify the dedicated worktree
`/dm-fix` has no earlier framing step (unlike `/dm-plan`, which can assume
`/dm-research` already created the story worktree) — so `/dm-fix` itself must
invoke the `worktree-manager` subagent, exactly like `dm-execute.md`'s own
Step 1.4:
- Resolve the integration branch: `.dm/lib/dm-gate.sh default-integration-branch`.
- Invoke `worktree-manager` for path `.worktrees/fix/<id>` on branch `fix/<id>`,
  created from that integration branch.
- Continue only after the absolute worktree path and the exact branch
  (`fix/<id>`) are confirmed. Missing worktree, wrong branch, detached HEAD or
  uncommitted conflicting work is a hard stop, same as `worktree-manager`'s own
  fail-closed procedure.
- `worktree-manager` is idempotent: if `/dm-execute fix/<id>` later runs and
  the worktree already exists (created here) on the correct branch and clean,
  `worktree-manager` will simply verify it, not fail.

Every subsequent read and write in this command — writing
`docs/plans/fix-<id>.md`, setting `validated: yes`, committing — happens
inside that worktree, on branch `fix/<id>`. Never in the repository base
directory.

## Step 2 — Write the plan
From inside `.worktrees/fix/<id>`, write `docs/plans/fix-<id>.md` from
@templates/fix-plan.md, frontmatter `validated: no`. A fix is a single unit of
work — there is no "Tickets (ordered)" breakdown into multiple child tickets.
Fill in inline:
- **problem** — what's broken, how it manifests, how to reproduce
- **approach** — the fix
- **size:** one of **XS | S | M | L | XL**
- **estimate:** person-days in **0.5** steps (0.5, 1, 1.5, …)
- **tasks** — checkboxes, verifiable, in TDD order
- **run interdicts** — what must NOT change, verifiable by the reviewer
- **test strategy** — what to test, at what level
- **definition of done** — the repo DoD, specialized to this fix

## Step 3 — Validation checkpoint
AskUserQuestion: "Validate this plan?" — options: Validate / I'll review it
first.
- The summary **must** show `size` + `estimate`. Missing either field →
  cannot Validate.
- On **Validate**: set `validated: yes` in the plan frontmatter. Then create
  the board issue, landing in `backlog` (never `ready`):
  ```bash
  bash .dm/lib/dm-board.sh issue-create-ticket fix <id> "<title> (SIZE, Nd)" <body-file>
  ```
  Literally pass `fix` as the story_id argument and `<id>` as the ticket_id
  argument — this is the existing `issue-create-ticket` subcommand, unmodified.
  It produces a GitHub Issue titled `[fix/<id>] <title>` with board key
  `fix/<id>`. `issue-create-ticket` treats `story_id = "fix"` as a reserved
  namespace key and never attempts parent sub-issue-linking for it, regardless
  of whether an unrelated issue happens to be titled `[fix]` or `[fix] ...`:
  the fix issue always lands standalone in `backlog`. Title includes size and
  estimate (e.g. `(M, 1.5d)`). Body includes `Size:` and `Estimate:` lines plus
  the fix scope.
- Do **not** call `require-ready` in this command — that's enforced later by
  `/dm-execute`.
- After setting `validated: yes`, commit the plan on branch `fix/<id>` inside
  `.worktrees/fix/<id>`: `git add docs/plans/fix-<id>.md && git commit -m
  "docs: validate fix plan fix/<id>"`. This is a docs-only change — `dm-gate.sh`'s
  `pre_commit` only counts non-`docs/*` paths as "code staged", so it never
  trips the code gate. Commit it before ending so the validated plan is
  actually present on `fix/<id>` when `/dm-execute fix/<id>` starts from that
  same worktree/branch.

If the plan file already exists when the command runs (rerun case from Step
1), skip straight to this checkpoint: show the summary and ask.

Write no code. This command produces a plan and (on Validate) a board issue —
not code.

## Step 4 — Report
End with: "Fix ticket created: `fix/<id>` (backlog). Next: move it to `ready`
on the board, then `/dm-execute fix/<id>`." — or "Fix plan awaiting
validation. Rerun `/dm-fix <description>` to validate." if it wasn't
validated.
