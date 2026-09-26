# driven — Repo rules

## Absolute rule
No direct coding. Every feature goes through the driven pipeline, in order:

PRD → Init → Stories → Stories Review → Architecture (+ Design System) → then, per story: Research → Design → Plan → Docs → then, per ticket: Execute → Review → Ship. Production: Release (the integration branch → `main`).

Throughout this file, **"the integration branch"** means `develop` when the project
has one (`.dm/config.json` → `"develop": true`, the default), otherwise `main`
directly. Resolve it for the current repo with
`.dm/lib/dm-gate.sh default-integration-branch`.

No code is written before the story has a validated plan (`/dm-plan`) and the **child ticket** is `ready`. No feature ships before a passed review (`/dm-review`). `ready` is child-only — a parent US never uses it.

### Quick Fix mode — exception to the pipeline

`Quick Fix` is the explicit exception for a small, local, well-understood, and
easily reversible adjustment. It applies only when the user explicitly requests
a Quick Fix. The primary agent implements it directly, without the full
driven pipeline and without mandatory TDD. It must not delegate
implementation to a subagent; a subagent may be used only for read-only
investigation or optional review.

Typical Quick Fixes include:

- changing a color, spacing, radius, font size, or button style;
- correcting short UI copy or a translation;
- making a small layout alignment or responsive adjustment;
- restoring or adjusting an already-existing presentation affordance;
- another similarly narrow change with no architectural or business impact.

Quick Fix mode does **not** apply to a new feature, shared-component redesign,
data model or migration, API or contract change, authorization, security,
business rules, persistence, cross-cutting refactor, dependency change, or any
change whose impact is uncertain. If the requested Quick Fix is too large or
investigation reveals one of these, the primary agent must stop Quick Fix mode,
recommend using the normal pipeline, and must not continue coding until the work
has passed the appropriate pipeline stages.

The primary agent must announce Quick Fix mode and its exact scope before
editing, keep the diff minimal, preserve existing abstractions, and perform a
proportionate verification (at minimum a focused lint, typecheck, existing test,
or visual browser check when applicable). TDD and subagent review are optional,
not forbidden.

Quick Fix work happens only in the repository's base directory on the
integration branch. It never gets a feature branch or a worktree. When the
project has a `develop` branch, Quick Fix never edits `main` directly — only
`develop`. Before editing, check the current branch. If it is not the
integration branch, stop and ask the user whether they really want to continue
on that branch; never switch branches automatically. Before editing, verify
that no other agent owns the base directory. If another agent is working
there, coordinate ownership or stop; never overlap edits.

### Fix ticket mode

A fix ticket is a standalone, parentless ticket that gets the **full**
pipeline rigor — dedicated worktree, mandatory TDD via the `implementer`
subagent, review via the `reviewer` subagent, ship into the integration
branch — without any story above it. It runs the same execute → review → ship
cycle as a child ticket, just without a story-level framing phase:

`/dm-fix <description>` → `/dm-execute fix/<id>` → `/dm-review fix/<id>` → `/dm-ship fix/<id>`

Branch `fix/<id>`, worktree `.worktrees/fix/<id>`, plan
`docs/plans/fix-<id>.md`, review `docs/reviews/fix/<id>.md`, board key
`fix/<id>` with the same statuses as any ticket (backlog → ready → in
progress → test → shipped).

Fix ticket mode is intended to eventually replace Quick Fix for anything that
needs real rigor, but it does not remove or change Quick Fix mode today — both
coexist.

## Pipeline (commands)
- `/dm-prd`        frames the product: clone an existing SaaS **or** greenfield (WHAT + WHY). Not kill-only.
- `/dm-init`       GitHub remote, `main` (+ optional `develop`), Project board, wiki, `VERSION`, CI
- `/dm-stories`    breaks it down into shippable user stories (parent Issues)
- `/dm-stories-review`  reviews the breakdown against the PRD perimeter (stories-reviewer subagent)
- `/dm-architect`  sets the technical HOW + the conventions (fills `<< IP Mike >>` below)
- `/dm-design-system`  captures the global design system (docs/design-system.md)
- `/dm-research`   explores the story's real context (current code, APIs, traps)
- `/dm-design`     derives a story's screen from the design system (UI stories)
- `/dm-plan`       breaks a story into sequenced child tickets (size + person-day estimates)
- `/dm-docs`       product page `docs/product/<story-id>.md` (wiki publish is release)
- `/dm-fix`        frames a standalone **fix ticket** (no parent story) — same rigor as a ticket
- `/dm-execute`    implements a **ticket** in TDD (implementer subagent)
- `/dm-review`     quality-bar review + gate (reviewer subagent)
- `/dm-ship`       opens the PR into the integration branch; merge per the ship strategy (manual by default)
- `/dm-release`    production: merge the integration branch → `main` (skipped when there is no `develop` — tickets already land on `main`), semver, wiki, board `shipped`

Utilities:
- `/dm-orchestrator`  two modes: `<story>` = framing (research → design → plan → docs); `<story> <ticket>` = execute → review → ship. Human checkpoints, not an autopilot.
- `/dm-help`          prints the pipeline map (French, user-facing cheat sheet)
- `/dm-status`        derives pipeline state (framing, per-US progress, **remaining person-days** on children not yet `test`/`shipped`, next command)

One user story = Research → Design → Plan (child tickets) → Docs → then per ticket Execute → Review → Ship into the integration branch. Production ships via `/dm-release` (the integration branch → `main`, skipped when there is no `develop`).
`ready` exists **only on child tickets**. Parent US: backlog → in progress → test → shipped (never `ready`).

## Git branches

| Branch | Role | Rule |
| --- | --- | --- |
| `main` | production | only updated from the integration branch (GitHub branch protection is the real guarantee) |
| `develop` | integration — **optional** (`.dm/config.json` → `"develop"`, default `true`) | PRs from `feature/*`; Quick Fix lands here. When absent, `feature/*` and Quick Fix target `main` directly. |
| `feature/<story-id>` | story framing (research, design, plan, product doc) | docs only, created from the integration branch |
| `feature/<story-id>/<ticket-id>` | one child ticket | implementation worktree, created from the integration branch |
| `fix/<id>` | standalone fix ticket (no parent story) | implementation worktree, created from the integration branch — see Fix ticket mode above |

## Where work happens

There are exactly four modes. A complexity score never chooses the directory:

| Mode | Working directory | Branch |
| --- | --- | --- |
| Explicit Quick Fix | Repository base directory | The integration branch; if another branch is checked out, stop and ask before continuing |
| Story framing (research / design / plan / docs) | `.worktrees/<story-id>/` | Exact `feature/<story-id>` (docs only) |
| Ticket implementation | `.worktrees/<story-id>/<ticket-id>/` | Exact `feature/<story-id>/<ticket-id>` |
| Fix ticket implementation | `.worktrees/fix/<id>/` | Exact `fix/<id>` |

Every change that is not explicitly announced and eligible as a Quick Fix is a
feature. Story framing uses the story worktree; implementation uses the ticket
worktree. Never create or check out a feature branch in the repository base
directory.

The `worktree-manager` subagent creates or verifies the worktree from the
integration branch before Research (story) or Execute (ticket). It imports
untracked `.env*` files and installs dependencies inside the worktree. Before
every later phase, resolve and state the absolute worktree path and verify the
exact branch. Missing worktree, wrong branch, detached HEAD or a second branch
name is a hard stop. Never improvise with `git switch`, `git checkout`, `git
stash` or an `-isolated` suffix.

One agent, one working directory. While an agent owns a directory, no second
agent and no main context may edit, checkout or stash in it.

## Story ids, tickets and branches
- Every story has an id: `s<number>-<short-slug>` (e.g. `s01-submit-testimonial`). It is assigned in docs/stories.md and reused verbatim: `docs/research/<id>.md`, `docs/plans/<id>.md`, `docs/product/<id>.md`, branch `feature/<id>`.
- `/dm-plan` decomposes the US into child tickets `t<number>-<slug>`. Full work id: `<story-id>/<ticket-id>` (e.g. `s01-submit-testimonial/t01-persist-entry`). Ticket branch: `feature/<story-id>/<ticket-id>`. Ticket review: `docs/reviews/<story-id>/<ticket-id>.md`.
- Story framing and ticket branches are created from the integration branch. Never commit feature work to `main`.
- The ticket diff = `git diff <integration-branch>...feature/<story-id>/<ticket-id>` (resolve `<integration-branch>` with `.dm/lib/dm-gate.sh default-integration-branch`). That is what the review judges.
- A command that receives a fuzzy story name resolves it against docs/stories.md; a second argument is a ticket id resolved against docs/plans/<story-id>.md. Ambiguous → list matches and stop.

## Gate (mechanical)
- The ticket review `docs/reviews/<story-id>/<ticket-id>.md` must end with the exact lines `Max severity: <critical|major|minor|none>` and `Ship allowed: <yes|no>`. A single critical or major = no.
- `/dm-ship` refuses to run unless that file exists and contains the line `Ship allowed: yes`. No file, no line, or `no` → ship blocked. No exceptions.
- After a blocked review, `/dm-execute` runs in fix mode: the review findings are fed to the implementer and fixed before anything else.
- A plan executes only if its frontmatter says `validated: yes` — set by the human validation checkpoint (/dm-plan or the orchestrator), never by the file merely existing. /dm-execute is fail-closed on it.
- `dm-gate.sh` resolves the integration branch (`develop` or `main` — see `.dm/config.json`) and treats `main` as production. Client-side pre-push refuses updates to `main` that don't come from the integration branch; GitHub branch protection is the real guarantee for `main`.

## Ship strategy
Merge mode: manual   (manual | auto — default: manual)
Target of `/dm-ship`: **the integration branch** (per ticket) — `develop` if the project has one, otherwise `main` directly. When targeting `develop`, production (`main`) is updated only by releasing `develop` → `main`.
- manual: /dm-ship opens the PR into the integration branch and stops. Merging is a human decision (review on GitHub, protected branch, CI). After the merge, rerun /dm-ship to confirm cleanup. Parent US moves to `test` only when every child is `test` or `shipped`.
- auto: /dm-ship merges into the integration branch immediately after the gate. Only for solo flows where running /dm-ship IS the decision.

## Design
The global design system lives in `docs/design-system.md` (components + tokens, anchored to the boilerplate). Each story's design lives in `docs/designs/<id>.md` (+ a reference `.html` mockup).
- A story's design can be generated by the agent or produced in Claude Design / Gemini and brought back. Either way it builds on the design system.
- Inventing a component or token outside the design system is forbidden. Compose with what exists.
- The HTML mockup is a reference, not code: the implementation uses the boilerplate's real components.
- A need the system doesn't cover = a "design system gap" to report, never to fill freestyle.
- Stories without UI skip `/dm-design`.

## Data & docs lifecycle
All pipeline data lives in markdown files under docs/, versioned by git. No database, no state file: the pipeline state is derived from the files (a story is planned if docs/plans/<id>.md exists, a ticket is shippable if its review says `Ship allowed: yes` and the branch is merged into the integration branch) — a derived state can't go stale.

- Framing docs — docs/prd.md, docs/stories.md, docs/reviews/stories.md, docs/architecture.md, docs/design-system.md: land on the integration branch (then `main` via release, or directly on `main` when there is no `develop`). (docs/reviews/stories.md reviews the breakdown, not a story: it is a framing doc.)
- Story docs — docs/research/<id>.md, docs/designs/<id>* (brief, md, html), docs/plans/<id>.md, docs/product/<id>.md: committed on `feature/<id>`, then into the integration branch.
- Ticket reviews — docs/reviews/<story-id>/<ticket-id>.md: committed on the ticket branch; /dm-ship commits the review. Every ticket PR carries its review.
- Task progress — the checkboxes in docs/plans/<id>.md: the implementer ticks each **ticket** task as it lands. The plan file is the live progress tracker, never a commit trigger.
- Estimates — each child ticket has `size` (XS–XL) and `estimate` (person-days, 0.5 steps). US total = sum. **Remaining person-days** = sum of estimates of children not yet `test` or `shipped` (`/dm-status`). No actuals in V1.
- Commits — **one commit per ticket** (squash into the integration branch). A second commit only for something you would want to revert on its own (typically a migration). One release = one squash commit on `main`.
- Decisions — docs/decisions/NNN-<slug>.md (MADR format, @templates/adr.md): one file per structural decision, with the considered options and why they were rejected. Immutable: a change means a new ADR superseding the old one.

## Technical conventions
<< IP Mike: boilerplate structure, stack, patterns, naming, commit rules. >>

## Definition of Done (per ticket / release)
- Ticket: single PR into the integration branch, structured description, readable diff, passing tests, review passed (no open critical or major), merged to the integration branch
- Release: the integration branch → `main` (skipped when there is no `develop`), version bumped, deployed to production
