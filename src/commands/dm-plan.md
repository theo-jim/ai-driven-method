---
description: Break a story into child tickets with size and person-day estimates
argument-hint: <story id or name>
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - AskUserQuestion
  - Bash
---
You are planning a story's implementation as **child tickets**. Target story: $ARGUMENTS

Resolve $ARGUMENTS to the story id (`s<number>-<slug>`) against docs/stories.md. If there is no unambiguous match, list the available stories and stop.

Locate the dedicated `.worktrees/<id>` worktree, verify that it is on exactly
`feature/<id>`, and perform every read and write there. Missing worktree, wrong
branch, detached HEAD or the repository base directory itself → STOP and run
`/dm-research <id>` first. Never create or switch branches here.

Read: docs/stories.md (the target story), docs/research/<id>.md (if it exists), docs/design-system.md and docs/designs/<id>.md (if they exist), docs/architecture.md, AGENTS.md
Output structure: @templates/plan.md

If docs/research/<id>.md doesn't exist, point out that /dm-research <id> is recommended before planning — without research, the plan relies on possibly stale docs. Continue only if I confirm.

If the story has UI, the plan follows the screen defined in docs/designs/<id>.md: it references the design system's components and never invents new ones. The HTML mockup is a reference, not a source of code.

## Tickets (not a flat task list)
Decompose the US into child tickets `t<number>-<slug>`. Each ticket is one execute → review → ship cycle (API slice, screen, migration) — not a technical-layer US and not every checkbox.

Every ticket **must** carry:
- `size:` one of **XS | S | M | L | XL**
- `estimate:` person-days in **0.5** steps (0.5, 1, 1.5, …)

Proceed as follows:
1. Isolate the target story and its acceptance criteria.
2. Break it into ordered tickets with dependencies, tasks under each ticket, run interdicts, size, and estimate. Lean on the research: real files, verified APIs, known traps. A behavior, business rule, data contract or interaction must name the test that can fail. A purely presentational task may instead name a focused visual/browser check plus lint and typecheck.
3. Anticipate the touched files and the test strategy per ticket. If the story is scored complexity 5, or the plan grows past roughly ten tickets, the story is too big: propose a US split instead of a bloated plan.
4. If planning forces a structural choice, record an ADR in `docs/decisions/` (@templates/adr.md).
5. Write the plan to `docs/plans/<id>.md`, frontmatter `validated: no`. Include a US total: sum of estimates + size mix.
6. Validation checkpoint (AskUserQuestion): "Validate this plan?" — options: Validate / I'll review it first.
   - The summary **must** list each ticket with `size` + `estimate` and the US total days. Missing either field on any ticket → cannot Validate.
   - On **Validate**: set `validated: yes`. Then for each ticket create a **child** Issue in `backlog` (never `ready`):
     ```bash
     bash .dm/lib/dm-board.sh issue-create-ticket <story-id> <ticket-id> "<title> (SIZE, Nd)" <body-file>
     ```
     Title includes size and estimate (e.g. `(M, 1.5d)`). Body includes `Size:` and `Estimate:` lines plus the ticket scope.
     Update the **parent** US Issue body with the sum of person-days and the size mix (best-effort via `bash .dm/lib/dm-vcs.sh issue-body-set <number> <body-file>` when the parent exists).
   - Do **not** call `require-ready` in this command.

If the plan file already exists when the command runs, skip straight to the validation checkpoint: show the summary and ask.

Write no code. This command produces a plan and (on Validate) child Issues — not code.

End with: "Plan validated. Child tickets in backlog. Next: /dm-docs <id>, then move a ticket to ready and /dm-execute <id> <ticket>" — or "Plan awaiting validation. Rerun /dm-plan <id> to validate." if it wasn't validated.
