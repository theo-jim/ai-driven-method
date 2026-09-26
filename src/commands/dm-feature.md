---
description: Add a feature to a shipped product — frame it, amend the PRD, append stories
argument-hint: <feature slug or short description>
allowed-tools:
  - Read
  - Glob
  - Grep
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---
# dm-feature — A feature on a product that already ships

Target feature: $ARGUMENTS

The product is framed, built and released. This command adds to it. It writes no
application code: it frames, amends, splits, and hands back to the normal per-story
pipeline.

## Prerequisites (fail-closed)
- `docs/prd.md` must exist. Missing → STOP: "No PRD — run /dm-prd, or /dm-continue on an existing project."
- `docs/stories.md` must exist. Missing → STOP: "Product not split yet — run /dm-stories."

## Step 1 — Frame the feature (AskUserQuestion, one at a time)
1. Need: what problem, for whom, why now?
2. Perimeter: what the feature delivers, and what stays out of it.
3. Graveyard check: read the PRD's "Explicitly NOT replicated / Out of scope" list.
   If this feature was killed there, ask for the justification of the reversal —
   what changed since that decision. A feature may leave the graveyard; it may not
   leave it silently.

Fill nothing you have not validated with me.

## Step 2 — Architecture impact (mechanical, not a judgement call)
Walk this list point by point and record which ones the feature hits:

- a new **runtime dependency**;
- an external **service or provider** (payment, mail, storage, AI…);
- a new **persistence store**, or a schema **migration**;
- a new **authentication or authorization** surface;
- an **asynchronous** mechanism, background job or **queue**.

One or more hits → the feature goes through `/dm-architect` (new ADR) before
`/dm-plan`. No hit → straight to `/dm-research`. Record the answer in the
amendment entry; do not decide by feel.

## Step 3 — Amend the PRD
Update the body of `docs/prd.md` in place — the perimeter table gains the feature,
the graveyard loses it if it came out — then add an entry at the top of the
`## Amendements` section:

    ### <AAAA-MM-JJ> — v<version cible> — <slug>
    **Entre dans le périmètre :** …
    **Sorti du cimetière ?** non | oui — <justification>
    **Stories :** <ids>

If `## Amendements` is absent (project framed before the template gained it),
create the section at the end of the file.

## Step 4 — Split into stories, and APPEND
Apply the `agentic-stories` skill: end-to-end shippable slices, testable acceptance
criteria, agentic notes, complexity 1-5 (a 5 gets split now).

Read the highest `s<NN>` already present in `docs/stories.md` and continue the
sequence. Ids name every pipeline file and every branch: a collision breaks the
whole cycle.

**Append** the new stories to `docs/stories.md`. Never overwrite the file — the
stories already there are shipped work, and their ids are referenced by
`docs/research/`, `docs/plans/`, `docs/reviews/` and by live branches.

## Step 5 — Parent Issues
One parent Issue per new story, status `backlog`, with the call that already
exists and is idempotent on the `[<story-id>]` title prefix:

```bash
bash .dm/lib/dm-board.sh issue-create-us <story-id> "<title>" <body-file>
```

## Step 6 — Fresh-context review
Delegate to the `stories-reviewer` subagent (read-only, fresh eyes — the context
that writes never reviews itself):

- prompt: Review the new feature stories against docs/prd.md (including its
  `## Amendements` section) and against the stories already shipped. The
  stories-review skill is preloaded; apply its "Reviewing a feature added after
  v1" section — duplication of shipped work, dependency on unshipped work,
  contradiction with production behaviour — on top of the eight standard checks.
  End with the exact lines "Max severity: <critical|major|minor|none>" and
  "Stories ready: <yes|no>".

Put the report in `docs/reviews/features/<id>.md`.

**Leave `docs/reviews/stories.md` alone.** That file is the product-level framing
signal: `/dm-status` and `/dm-research` grep it for `^Stories ready:`, and
overwriting it would report the whole breakdown as re-reviewed when it was not.

Soft gate, like the framing review: surfaced by `/dm-status`, not a hard block.

## Step 7 — Commit
Commit on the integration branch once /dm-init has run (resolve it with
`.dm/lib/dm-gate.sh default-integration-branch`), otherwise the current default
branch — with the message `docs: feature <slug>`.

End with, depending on Step 2:
- architecture touched → "Feature framed (<ids>). Next step: /dm-architect"
- otherwise → "Feature framed (<ids>). Next step: /dm-research <story-id>"
