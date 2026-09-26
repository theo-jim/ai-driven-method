---
description: Onboard an existing codebase into the driven pipeline — baseline + Issue mapping
argument-hint: (none — reads the current repo)
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Write
  - AskUserQuestion
---
# dm-continue — Adopt driven on a project already under way

You are onboarding an **existing** project into driven. The code already runs; the
documentation does not exist yet. Your single deliverable is `docs/onboarding.md`.

`Bash` is for read-only queries (`git log`, `git ls-files`, `gh issue list`) and for
the docs commit at the end. Never mutate the board, never write through `gh`.

## Prerequisites (fail-closed)
- Source files must exist outside `docs/`, and the git history must hold more than one
  commit. Neither → STOP: "Empty repo — run /dm-prd instead."
- `docs/prd.md` must **not** exist. Present → STOP: "Project already framed — run /dm-status."

## What you must NOT do
- Do not analyse code structure, conventions, patterns or stack. `/dm-architect` already
  does that with the `codebase-analysis` skill; a second analysis here would be a second
  source of truth that drifts.
- Do not create, rename, close or move any Issue. The board does not exist yet:
  `.dm/lib/dm-board.sh` needs `.dm/config.json`, which only `/dm-init` writes. You only
  **propose** a mapping.
- Do not write `docs/prd.md`, `docs/stories.md` or `docs/architecture.md`. The commands
  that own those files come next in the chain.

## Gather the real state (read-only)
1. Inventory the product surface: entry points, routes/screens, main flows. Use Glob and
   Grep. You are answering "what does this app do for its users", not "how is it built".
2. Read the git history (`git log --oneline`) for what has already shipped and when.
3. If `gh auth status` succeeds, list the open and closed Issues:
   ```bash
   gh issue list --state open --limit 200 --json number,title,labels
   gh issue list --state closed --limit 200 --json number,title
   ```
   `gh` missing or unauthenticated → skip the mapping section, print an explicit warning,
   and write the baseline anyway. A missing board must never block documenting the product.

## Confirm with the user (AskUserQuestion, one at a time)
1. Product summary: state what you understood the app does in one sentence; ask them to
   confirm or correct it.
2. Baseline boundary: which of the flows you listed do they consider already shipped?
3. For each open Issue, propose an id `s<NN>-<short-slug>` and ask them to confirm, amend
   or exclude it. Record the answer; nothing is applied here.

## Write `docs/onboarding.md`
Sections, in this order:

1. `## What the app does` — the value loop and the users, as confirmed.
2. `## Shipped baseline` — the shipped flows, with the commits or dates that show it.
3. `## Remaining work (leads)` — non-contractual; `/dm-stories` owns the real breakdown.
4. `## Open issue mapping` — **this heading is a verbatim anchor**: `/dm-stories` greps for
   it literally. Do not translate it, do not reword it. A table, one row per open Issue,
   exactly this shape:

   | Issue | Title | Proposed story |
   | --- | --- | --- |
   | #12 | Export CSV | s03-export-csv |

   This section is a **proposal**. `/dm-stories` reads it after `/dm-init` and applies the
   conversion, one confirmation per Issue.
5. `## Closed issues (context)` — listed, never touched.

Write nothing you have not validated with the user.

## Commit
The integration branch does not exist yet at this stage. Commit on the default branch, docs-only, so the
`pre-commit` hook passes without a validated plan:

```bash
git add docs/onboarding.md && git commit -m "docs: onboarding baseline"
```

End with: "Baseline ready in docs/onboarding.md (N issues mapped, nothing mutated). Next step: /dm-prd"
