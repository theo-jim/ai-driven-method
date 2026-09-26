---
description: Break the PRD down into shippable, agentic-ready user stories
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
---
You are breaking the PRD down into user stories.

## Prerequisites
- `docs/prd.md` must exist.
- Board init recommended: `.dm/config.json` present (from `/dm-init`). Missing → warn that parent Issues cannot be created until init; continue writing `docs/stories.md` only if the user confirms.

Read the PRD: docs/prd.md
Output structure: @templates/stories.md

Apply the agentic-stories skill for the breakdown.

The target SaaS is a living spec: for each story, the agentic notes may point to the target's equivalent screen or flow — the reference implementation already runs in production. Stay inside the PRD perimeter: nothing from the graveyard becomes a story.

Proceed as follows:
1. Break the need into stories: each one an end-to-end shippable slice, testable. Give each story an id: `s<number>-<short-slug>` (e.g. s01-submit-testimonial) — this id names every pipeline file and the story branch, so keep it short and stable.
2. For each story, write verifiable acceptance criteria (each one must be able to become a test), the agentic notes useful for execution, and a complexity score (1-5, same scale as the PRD perimeter) — a 5 gets split now, not at planning.
3. Order the stories by dependency: no story may assume work not yet done.
4. Write the result to `docs/stories.md` and commit it on the integration branch after init (resolve with `.dm/lib/dm-gate.sh default-integration-branch`), else the current default branch — message `docs: stories`.
5. **Board — parent US only.** For each story id, create one parent Issue (status `backlog`). Do **not** create child tickets here:
   ```bash
   bash .dm/lib/dm-board.sh issue-create-us <story-id> "<title>" <body-file>
   ```
   Body file: short summary + acceptance criteria excerpt. Skip create if an Issue with title prefix `[<story-id>]` already exists.

   **Onboarded project.** If `docs/onboarding.md` exists, read its `## Open issue mapping`
   table before creating anything (the heading is a verbatim anchor). When a story id
   appears in that table, the Issue is already written by hand: do **not** create a second
   one. Ask the user, **one Issue at a time** (AskUserQuestion), whether to adopt it:
   - adopt → one call, which renames the Issue, adds it to the project and sets `backlog`:
     ```bash
     bash .dm/lib/dm-board.sh issue-adopt <story-id> <N> "<title>"
     ```
     Never use `status-set` for this: it resolves an existing **project item**, and a
     hand-written Issue is not on the board yet.
   - decline → leave the Issue untouched and create the parent Issue normally.

   Nothing is renamed or moved without that explicit per-Issue answer. Issues listed under
   `## Closed issues (context)` are never touched.

End with: "Stories ready in docs/stories.md (parent Issues in backlog). Next step: /dm-stories-review"
