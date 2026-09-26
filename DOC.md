A fork of [killer-saas](https://github.com/MikeCodeur/killer-saas) by [Mike Codeur](https://github.com/MikeCodeur).

Commands: `/dm-*`.

driven keeps the original pipeline (no direct coding, file gates, subagents)
and adds: hybrid PRD (clone or greenfield), Grok install, GitHub or GitLab board + wiki,
`main`/`develop` flow (`develop` optional per project), a stricter quality bar,
and semver on release.

See [NOTICE](NOTICE) and [README.md](README.md).

# ai-driven-method — Method documentation

A complete agentic pipeline for product delivery with Claude Code, Codex, or Grok: frame a hybrid PRD (clone an existing SaaS **or** greenfield), cut shippable user stories and child tickets, enforce quality on a GitHub Project or GitLab Issue board + wiki + `main`/`develop` flow, and release with semver.
One method = a suite of commands. One principle = no direct coding.

## Philosophy

Three rules define the normal feature pipeline, enforced by the tooling — not by discipline:

1. **No direct coding.** No feature code is written outside the pipeline. `/dm-execute` doesn't have the Write/Edit/Bash tools: the main context *cannot* code, it delegates to the `implementer` subagent. The rule lives in the tooling, not in good intentions.
2. **The context that writes never reviews itself.** An agent is blind to its own hallucinations and to its own gaps. Reviews run in fresh-context, read-only subagents — `reviewer` for the code, `stories-reviewer` for the breakdown.
3. **Fail-closed.** No plan → no execution. A **critical or major** issue in review → no ship. Child ticket not `ready` / `in progress` → no code commit once the board exists. Every gate blocks by default; nothing gets forced through.

### Quick Fix mode

`Quick Fix` is the explicit, user-requested exception for a small, local,
well-understood, and easily reversible adjustment with no architectural or
business impact. The primary agent announces the exact scope, edits directly
on the integration branch (`develop`, or `main` when the project has no
`develop`), keeps the diff minimal, and performs a proportionate focused
verification. TDD and a fresh-context subagent review remain available but are
not mandatory.

It is not a shortcut for features or uncertain work. Changes involving shared
redesigns, data, APIs, authorization, security, business rules, persistence,
dependencies, or cross-cutting refactors return to the normal pipeline before
coding continues. A subagent may investigate or review a Quick Fix, but the
primary agent owns its implementation and must coordinate to prevent concurrent
edits to the same files or targets.

### Editing the workflow rules

`src/AGENTS.md` is the sole tracked source of truth for shared workflow rules.
Maintainers edit that file, never the root `AGENTS.md` produced by a local test
installation. Rules must not be copied into `CLAUDE.md`: Claude's project file
stays a one-line `@AGENTS.md` import so Claude, Codex and Grok always read the
same rules.

After changing the workflow, build targets with `bin/dm-build.mjs` and test
the relevant installer path. New installs receive `src/AGENTS.md`; updates never
overwrite a project's existing `AGENTS.md`, so evolved rules must be merged into
already-installed projects deliberately. Root `AGENTS.md` and `CLAUDE.md` in
this repository are ignored local installation artifacts, not editable sources.

## The pipeline

Framing once per product (including `/dm-init` for remote, board, wiki, `VERSION`).
Then story framing (docs on `feature/<story-id>`), then ticket delivery
(`feature/<story-id>/<ticket-id>` → the integration branch), then `/dm-release`
(the integration branch → `main`; skipped when the project has no `develop`).

    PRD → Init → User Stories → Stories Review → Architecture → Design System
    then, per story (docs):
    Research → Design → Plan → Docs
    then, per ticket (code, child ≥ ready):
    Execute → Review → Ship
    then production:
    Release (semver + wiki + shipped)

| Step | Command | Role | Output |
| --- | --- | --- | --- |
| Continue | `/dm-continue` | Existing project: product baseline + Issue mapping, mutates nothing | `docs/onboarding.md` |
| PRD | `/dm-prd` | Hybrid frame: clone **or** greenfield — the WHAT and the WHY | `docs/prd.md` |
| Init | `/dm-init` | GitHub or GitLab remote, `main` (+ optional `develop`), board, wiki, `VERSION`, CI | `.dm/config.json`, `VERSION`, protections |
| Stories | `/dm-stories` | Shippable US + **one parent Issue** per US (`backlog`) | `docs/stories.md` |
| Stories Review | `/dm-stories-review` | Fresh-context review of the breakdown vs the PRD | `docs/reviews/stories.md` |
| Architecture | `/dm-architect` | Stack from PRD / existing code; conventions | `docs/architecture.md` + `AGENTS.md` |
| Design System | `/dm-design-system` | Tokens, components, UI patterns — records, never draws | `docs/design-system.md` |
| Research | `/dm-research <story>` | Real state of the code in the story's scope (no ready gate) | `docs/research/<story>.md` |
| Design | `/dm-design <story>` | Story screen anchored to the design system (no ready gate) | `docs/designs/<story>.md` + `.html` |
| Plan | `/dm-plan <story>` | Child tickets with size (XS–XL) + person-day estimates | `docs/plans/<story>.md` + child Issues |
| Docs | `/dm-docs <story>` | Product page for the wiki (no wiki push) | `docs/product/<story>.md` |
| Execute | `/dm-execute <story> <ticket>` | TDD via `implementer`; `require-ready` first | code + tests + commits |
| Review | `/dm-review <story> <ticket>` | Quality-bar review by `reviewer` | `docs/reviews/<story>/<ticket>.md` |
| Ship | `/dm-ship <story> <ticket>` | PR/MR into **the integration branch**; after merge child → `test` | PR/MR / board update |
| Release | `/dm-release` | Bump `VERSION`, PR/MR integration branch → `main` (skipped without `develop`), wiki, `shipped` | tag + wiki + board |
| Feature | `/dm-feature <slug>` | Post-v1: frame, amend the PRD, append stories | `docs/prd.md` + `docs/stories.md` |

### Framing (once per product)

**/dm-continue** — the brownfield entry point. Read-only on the repo and on the code host: it
writes `docs/onboarding.md` (what the app does, the shipped baseline, a proposed
`issue #N → sNN-slug` mapping) and nothing else. It cannot touch the board — `.dm/config.json`
does not exist before `/dm-init`. The mapping is applied later by `/dm-stories`, one
confirmation per Issue, through `dm-board.sh issue-adopt`. Fail-closed both ways: empty
repo → `/dm-prd`; `docs/prd.md` already present → `/dm-status`.

**/dm-prd** — frames the product by interviewing the user. First question: **clone** an existing SaaS vs **greenfield**. Clone mode covers target, kill mode (internal replacement vs competing product), why, the 20% perimeter, complexity scores, graveyard, and angle beyond parity. Greenfield covers need, users, why now, in/out of scope (graveyard still kills creep), constraints, and success — no fake “target SaaS”. Nothing is filled without validation. The WHAT and the WHY, never the HOW.

**/dm-init** — bootstraps the app repo after the PRD: confirm the platform (GitHub or GitLab, see [GitHub or GitLab](#github-or-gitlab)) and remote name/visibility/owner, optionally create `develop` from `main` (`--no-develop` to skip it), protect the branch(es), create the board with statuses `backlog | ready | in progress | test | shipped` (Project V2 on GitHub, status labels + Issue Board on GitLab), write `.dm/config.json` (including `"platform"` and `"develop": true|false`), enable the wiki, write `VERSION` (`0.1.0` if absent), copy the CI gate. Idempotent: re-runs only fill gaps.

**/dm-stories** — breaks the PRD into agentic-ready user stories (`agentic-stories` skill). Each US gets **one parent Issue** in `backlog`. Child tickets are **not** created here. Parent US never uses status `ready`.

**/dm-stories-review** — reviews the breakdown in a fresh context (`stories-reviewer`, read-only). Soft gate: surfaced by `/dm-status` and warned about by `/dm-research`, not a hard mechanical block.

**/dm-architect** — analyzes existing code or **recommends a stack from the PRD** (no hardcoded Next.js). Records the choice as an ADR, fills architecture + conventions in `AGENTS.md`.

**/dm-design** offers three paths. On Claude Code the **canvas** path invokes the native
`/design` command: the artboards are drafted in session as `docs/designs/<id>.dc.html` and
refined by the user in the published Artifact. Codex and Grok have no `/design`, so they
keep the brief round-trip — the command offers only the paths the running tool can honour.
On every path the design system is copied into the request and the file gate is unchanged:
the published Artifact is never the deliverable, `docs/designs/<id>.md` plus the committed
mockup are.

**/dm-design-system** — captures tokens/components into `docs/design-system.md`. Fail-closed: no source, no design system.

### Story framing (docs — branch `feature/<story-id>`)

**/dm-research** / **/dm-design** / **/dm-plan** / **/dm-docs** — no board `ready` gate. `/dm-plan` cuts the US into child tickets (`tNN-…`) with **size** (XS–XL) and **estimate** (0.5-day steps). On Validate: create child Issues in `backlog`. `/dm-docs` writes `docs/product/<story>.md` for later wiki publish; it does **not** push the wiki.

### Ticket delivery (code — branch `feature/<story>/<ticket>`)

**/dm-execute** — `bash .dm/lib/dm-board.sh require-ready <story>/<ticket>` then `status-set … "in progress"`. Delegates TDD to `implementer`. Fail-closed without a validated plan and without child `ready`/`in progress`.

**/dm-review** — `reviewer` + `quality-bar` skill. Diff is `git diff <integration-branch>...feature/<story>/<ticket>` (resolved via `dm-gate.sh default-integration-branch`). Ends with `Max severity: …` and `Ship allowed: yes|no`. **A single critical or major = Ship allowed: no.**

**/dm-ship** — greps `Ship allowed: yes`, opens the pull/merge request into **the integration branch** (`dm-vcs.sh pr-create`). After a proven merge: child → `test`, `parent-sync`.

### Production

**/dm-release** — parents in `test`; user picks major/minor/patch; bump `VERSION`; PR/MR integration branch → `main` (via a dedicated `release/v<version>` branch when the project has no `develop`, since `main` is protected); after merge: tag, `dm-wiki.sh publish`, board → `shipped`.

**/dm-feature** — a feature on a product that already ships. The PRD is a living
document: the perimeter table is updated in place and the change is recorded under
`## Amendements` (date, target version, what enters the perimeter, and — when the
feature comes out of the graveyard — the justification for the reversal). Stories
are **appended** to `docs/stories.md`, ids continuing the existing sequence; the
file is never overwritten, since the ids already there are referenced by research,
plans, reviews and live branches. Architecture impact is decided by an
enumeration, not by feel: a new runtime dependency, an external service or
provider, a new persistence store or migration, a new auth surface, or an async
mechanism sends the feature through `/dm-architect` and a new ADR before
`/dm-plan`. The fresh-context review lands in `docs/reviews/features/<id>.md` and
leaves `docs/reviews/stories.md` alone — that file carries the product-level
`Stories ready:` signal.

### Utilities

**/dm-orchestrator `<story>`** — research → design → plan → docs, then lists backlog children. **`/dm-orchestrator <story> <ticket>`** — execute → review → ship.

**/dm-help** — French pipeline map (US vs tickets). User-invoked only.

**/dm-status** — framing + board columns via `status-get` + next useful command.

## US vs tickets

| | User story (parent) | Ticket (child) |
| --- | --- | --- |
| Id | `s01-…` | `s01-…/t01-…` |
| Board | backlog → in progress → test → shipped (**no** `ready`) | backlog → **ready** → in progress → test → shipped |
| Branch | `feature/<story>` (docs only) | `feature/<story>/<ticket>` (code) |
| Creation | `/dm-stories` | `/dm-plan` Validate |

## Data & storage

Markdown under `docs/`, plus board config and version:

| Data | Lives in |
| --- | --- |
| PRD, stories, architecture | `docs/prd.md`, `docs/stories.md`, `docs/architecture.md` |
| Research, plan, product doc | `docs/research/<id>.md`, `docs/plans/<id>.md`, `docs/product/<id>.md` |
| Ticket review | `docs/reviews/<story>/<ticket>.md` |
| Platform, board / project ids | `.dm/config.json` (JSON, committed; created by `/dm-init`) |
| Version | `VERSION`, `CHANGELOG.md` |
| Decisions | `docs/decisions/NNN-<slug>.md` |
| Pipeline state | derived — files + `Ship allowed:` + Issue status + git |

## Tooling anatomy

| Block | Location | Role |
| --- | --- | --- |
| Commands | `.claude/commands/dm-*.md` (or Codex/Grok equivalents) | The process |
| Skills | `*/skills/` | Reusable know-how (`quality-bar`, `tdd-skill`, …) |
| Agents | `*/agents/` | Isolated execution |
| Templates | `templates/` | Deliverable skeletons |
| Lib | `.dm/lib/*.sh` | Board, init, version, wiki helpers; `dm-vcs.sh` GitHub/GitLab layer |
| Rules | `AGENTS.md` (+ `CLAUDE.md` → `@AGENTS.md`) | Repo law |
| Hooks | `.dm-hooks/` via `--hooks` | Git-enforced gates |

### The subagents

- **implementer** (`opus`, `tdd-skill` + `quality-bar` preloaded) — implements the plan in TDD.
- **reviewer** (`quality-bar` preloaded, read-only apart from the restored bite-proof mutation) — fresh eyes. Judges, doesn't fix. **A single critical or major = ship refused.**
- **stories-reviewer** (`stories-review` preloaded, read-only, no shell) — breakdown vs PRD.
- **worktree-manager** — creates worktrees from **the integration branch**.

### The skills

- `agentic-stories` — agent-executable story breakdown
- `codebase-analysis` — structure, conventions, patterns
- `tdd-skill` — test-first discipline (preloaded in `implementer`)
- `quality-bar` — anti-hallucination, OWASP-on-diff, factorization, maintainability; **critical or major blocks ship** (preloaded in `reviewer` / `implementer`)
- `stories-review` — perimeter coverage, graveyard leaks, dependency order

## The gate

The review ends with `Max severity: ...` and `Ship allowed: yes|no`. `/dm-ship` greps that line.

- **Critical or major** → `Ship allowed: no` → ship blocked. Fix via `/dm-execute` (fix mode), then a new `/dm-review`.
- Minor → ship allowed, follow-ups in a later cycle.

Upstream: plan validation (`validated: yes`) and board ready-gate (child in `ready` / `in progress` when `.dm/config.json` exists) block code the same way.

## Definition of Done (per ticket)

- Single PR/MR into the integration branch, structured description, readable diff
- Passing tests on business logic
- No regression on existing code
- Review passed (no open critical **or major**)
- Child Issue moved to `test` after merge; released to `main` via `/dm-release`

## GitHub or GitLab

`/dm-init` records the code host in `.dm/config.json` → `"platform"`: `--platform
github|gitlab`, else detected from `origin` (`github.com` → GitHub, a host containing
`gitlab` → GitLab; any other host is refused until `--platform` is given). A config written
before GitLab support has no `platform` field and stays GitHub. Commands never call `gh` or
`glab` directly: pull/merge request and Issue steps go through `.dm/lib/dm-vcs.sh`, and the
board helpers load `dm-board-gitlab.sh` on a GitLab project.

| | GitHub (`gh`) | GitLab (`glab`) |
| --- | --- | --- |
| Remote | `gh repo create` | `glab repo create` (`--host` for a self-managed instance) |
| `main` / `develop` protection | branch protection + rulesets | protected branches: push *No one*, merge through a merge request (maintainers on `main` when `develop` exists, developers otherwise) |
| "`main` only from `develop`" | ruleset | `dm-gate` CI job (GitLab cannot restrict source branches natively — enable *Pipelines must succeed* to make it blocking) |
| Board statuses | Project V2 single-select `Status` field | one label per status (`dm::backlog`, `dm::ready`, `dm::in progress`, `dm::test`, `dm::shipped`), shown as Issue Board lists; `dm-board.sh` keeps exactly one per Issue |
| Parent / child | sub-issues (fallback `Parent: #n` + label `ticket`) | issue links (same fallback) |
| Ship / release | pull request | merge request — `dm-vcs.sh pr-create / pr-state / pr-merge` |
| Wiki | `<repo>.wiki.git`, `Home.md` | `<project>.wiki.git`, `home.md`; token from `GITLAB_TOKEN` / `glab` |
| CI gate | `.github/workflows/dm-gate.yml` | `.gitlab/ci/dm-gate.yml`, included from `.gitlab-ci.yml` |

"PR" in the commands means a GitHub pull request or a GitLab merge request.

## Install

The installer always targets the directory you run it from — your project's root, not this repo.

| Mode | From your project's root | Effect |
| --- | --- | --- |
| Project (default) | `curl -fsSL https://raw.githubusercontent.com/BarthGve/ai-driven-method/main/install.sh \| bash` — or `<clone>/install.sh` | Tooling + `templates/` + `AGENTS.md`/`CLAUDE.md` + `.dm/lib` |
| Codex / Grok | same one-liner with `--target codex` or `--target grok` | `.codex/` or `.grok/` trees |
| Global | `<clone>/install.sh --global [--target …]` | Tooling under `~/.claude` / `~/.codex` / `~/.grok` |
| Per project, after global | `~/.claude/ai-driven-method/install.sh init [--target …]` | Templates + rules + `.dm/lib` |
| Update | one-liner with `-s -- update` | Replaces method tooling; never overwrites `AGENTS.md` |
| Hooks | add `--hooks` | `core.hooksPath=.dm-hooks` |
| Profile | `--profile full\|framing\|delivery` | Installs a coherent subset of the commands |
| Uninstall | `uninstall [--dry-run]` | Removes exactly what `.dm-manifest` lists |

## Multi-tool support (Claude Code / Codex / Grok)

One canonical source (`src/`), one installer, per-tool emission — no forked copies.

| Building block | Claude Code | Codex | Grok |
| --- | --- | --- | --- |
| Rules (`AGENTS.md`) | native (+`CLAUDE.md` import) | **native** | **native** |
| Skills (`SKILL.md`) | native | **native** | copied |
| Templates | copied | copied | copied |
| Commands (`dm-*`) | `.claude/commands/*.md` | emitted as `.codex/skills/*` | `.grok/commands/*.md` |
| File/board/git gates | ✅ | ✅ | ✅ |
| "No direct coding" via tool permissions | ✅ mechanical | ~ agent sandbox | ~ agent sandbox |
| Subagent model routing | ✅ | note only | note only |
| Design canvas (`/design`) | ✅ native | brief round-trip | brief round-trip |

### Repo-level enforcement (`--hooks`)

- **pre-commit** — no **code** on `feature/<story>/<ticket>` without `validated: yes` plan; when `.dm/config.json` exists, child must be `ready` or `in progress`. Docs-only always allowed. Story framing branches are docs-only.
- **pre-push** — only the integration branch may update `main`; ticket branches need `Ship allowed: yes` before landing on the integration branch.

So plan, ready, and review gates hold on Claude, Codex and Grok alike — enforcement lives in the repo, not the harness. CI template `dm-gate.yml` (GitHub Actions) or `dm-gate.gitlab-ci.yml` (GitLab CI), copied at `/dm-init`, mirrors the ship / version checks on pull/merge requests.

## Provenance

driven is a public GitHub fork of Mike Codeur's [killer-saas](https://github.com/MikeCodeur/killer-saas). Credit stays explicit in [NOTICE](NOTICE), [README.md](README.md), and this document. We keep the fork network and the principle of no direct feature coding; the additions above (hybrid PRD, board, wiki, version, Grok, quality bar) are the driven layer on top.
