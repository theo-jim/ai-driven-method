# ai-driven-method

[![Release](https://img.shields.io/github/v/release/theo-jim/ai-driven-method?label=version)](https://github.com/theo-jim/ai-driven-method/releases)


A fork of [killer-saas](https://github.com/MikeCodeur/killer-saas) by [Mike Codeur](https://github.com/MikeCodeur) and [ai-driven-method](https://github.com/theo-jim/ai-driven-method/) by [BarthGve](https://github.com/BarthGve)

Commands: `/dm-*`.

driven keeps the original pipeline (no direct coding, file gates, subagents)
and adds: hybrid PRD (clone or greenfield), Grok install, GitHub board + wiki,
`main`/`develop` flow (`develop` optional per project), a stricter quality bar,
and semver on release.

See [NOTICE](NOTICE), [DOC.md](DOC.md), [CHANGELOG.md](CHANGELOG.md) and [RELEASING.md](RELEASING.md).

A complete agentic pipeline for product delivery: frame a hybrid PRD (clone an existing SaaS or greenfield), cut shippable user stories and child tickets, enforce quality on a GitHub board + wiki + `main`/`develop` flow, and release with semver.
One method = a suite of commands. One principle = no direct coding.

Small presentation or copy adjustments can use the explicit **Quick Fix**
exception when the user requests it. The primary agent edits directly, keeps the
scope narrow, and verifies the result. If the impact is architectural, business,
cross-cutting, or uncertain, the normal pipeline remains mandatory. See
[DOC.md](DOC.md#quick-fix-mode) for the complete boundary.

## Pipeline

PRD → Init (board / wiki / `VERSION`) → User Stories → Stories Review → Architecture + Design System → then, per story: Research → Design → Plan → Docs → then, per ticket: Execute → Review → Ship → Release (the integration branch → `main`).

Full method documentation: [DOC.md](DOC.md)

### Existing project

`/dm-continue` — the code already runs and the Issues are already written. It records a
product baseline in `docs/onboarding.md` and proposes a mapping for the open Issues,
mutating nothing. Then the normal framing resumes at `/dm-prd` (brownfield mode).

### Framing — once per product

`/dm-prd` → `/dm-init` → `/dm-stories` → `/dm-stories-review` → `/dm-architect` → `/dm-design-system`

Hybrid PRD: clone an existing SaaS **or** greenfield. Then board, wiki, `main` (+ optional `develop`).

### Per story — docs on `feature/<story-id>`

`/dm-research <story>` → `/dm-design <story>` → `/dm-plan <story>` (child tickets) → `/dm-docs <story>`

Story branches are docs only. `ready` is **child-only**.

### Per ticket — code on `feature/<story-id>/<ticket-id>` into the integration branch

`/dm-execute <story> <ticket>` → `/dm-review <story> <ticket>` → `/dm-ship <story> <ticket>`

One worktree, one branch, one commit, one PR per ticket. Child must be `ready`.

### After v1

`/dm-feature <slug>` — the product ships and a new feature arrives. It frames the
feature, amends the PRD (living document: the perimeter is updated and the change
recorded under `## Amendements`), and appends stories to the existing backlog. A
mechanical impact list decides whether it goes through `/dm-architect` first.

### Production

`/dm-release` — parents in `test`, bump `VERSION`, squash-merge the integration branch → `main` (skipped when there is no `develop`), tag, wiki, board `shipped`.

## Install

You don't clone this repo into your project: the installer drops its files into whatever directory you run it from.

Quickest — choose your tool and run the matching one-liner from your project's
root (the script fetches the repo itself).

**Claude Code:**

    cd your-project
    curl -fsSL https://raw.githubusercontent.com/theo-jim/ai-driven-method/main/install.sh | bash

**Codex:**

    cd your-project
    curl -fsSL https://raw.githubusercontent.com/theo-jim/ai-driven-method/main/install.sh | bash -s -- --target codex

To install the Codex skills globally instead:

    curl -fsSL https://raw.githubusercontent.com/theo-jim/ai-driven-method/main/install.sh | bash -s -- --global --target codex

The Codex target requires Node.js and installs the skills in `.codex/skills`
for a project install or `~/.codex/skills` for a global install.

**Grok:**

    cd your-project
    curl -fsSL https://raw.githubusercontent.com/theo-jim/ai-driven-method/main/install.sh | bash -s -- --target grok

To install Grok tooling globally instead:

    curl -fsSL https://raw.githubusercontent.com/theo-jim/ai-driven-method/main/install.sh | bash -s -- --global --target grok

The Grok target requires Node.js and installs commands, skills, and agents in
`.grok/` for a project install or `~/.grok` for a global install.

Prefer to read before you run? Clone the repo somewhere, then run the script from your project's root:

    git clone https://github.com/theo-jim/ai-driven-method.git ~/tools/ai-driven-method
    cd your-project
    ~/tools/ai-driven-method/install.sh

### Targets and scopes

One source of truth, one installer, per-tool output. Pick a **target** with `--target`, in **project** (default) or **global** (`--global`) scope:

    ./install.sh                           # Claude Code, project (default)
    ./install.sh --target codex            # Codex, project → .codex/skills + AGENTS.md
    ./install.sh --target grok             # Grok, project → .grok/commands + skills + agents
    ./install.sh --target all              # Claude + Codex + Grok, project
    ./install.sh --global                  # Claude, global (commands in every repo)
    ./install.sh --global --target codex   # Codex, global → ~/.codex/skills
    ./install.sh --global --target grok    # Grok, global → ~/.grok
    ./install.sh --global --target all     # all three, global

After a global install, drop the per-project files (templates + rules) in each project:

    ~/.claude/ai-driven-method/install.sh init                 # Claude
    ~/.claude/ai-driven-method/install.sh init --target codex  # Codex
    ~/.claude/ai-driven-method/install.sh init --target grok   # Grok

`AGENTS.md` (the rules) is shared and read natively by Codex and Grok; on Claude a one-line `CLAUDE.md` imports it. The skills are the open `SKILL.md` standard, so they carry over unchanged; the `dm-*` commands are emitted as Codex skills, and copied as-is for Claude/Grok. See the fidelity matrix in [DOC.md](DOC.md).

When maintaining driven itself, edit only `src/AGENTS.md`. The root
`AGENTS.md` and `CLAUDE.md` are ignored local-install artifacts; `CLAUDE.md`
must remain a one-line `@AGENTS.md` import. See
[Editing the workflow rules](DOC.md#editing-the-workflow-rules).

### Repo-level enforcement (git hooks)

The method's guardrails don't have to depend on a specific tool's permissions. Opt in with `--hooks` to enforce them in **git**, identically for every tool:

    ./install.sh --hooks        # (add to any target)

- **pre-commit** — refuses **code** on `feature/<story>/<ticket>` without a validated plan (`docs/plans/<story>.md` → `validated: yes`) and, when `.dm/config.json` exists, without the child Issue in `ready` or `in progress`. Docs-only commits always pass. Story framing branches (`feature/<story>`) are docs-only.
- **pre-push** — refuses updates to `main` that don't come from the integration branch; refuses integrating a ticket branch into the integration branch without `Ship allowed: yes`.

Reversible: `git config --unset core.hooksPath`. On Claude the harness also enforces "no direct coding" via tool permissions; the hooks make the same guarantees hold on Codex and Grok — enforcement lives in the repo, not the tool.

### Profiles and prompts

Run `./install.sh` with no flags **on a terminal** and it asks for the target and the
profile. Pass any flag, or run it outside a terminal (CI, `curl | bash` redirected),
and it asks nothing — same behaviour as before.

    ./install.sh --profile framing     # PRD → design system: frame without delivering
    ./install.sh --profile delivery    # research → release: deliver, framing done elsewhere
    ./install.sh --profile full        # everything (default)

Profiles pick **commands**, never skills or agents: commands reference those by name,
and a missing skill breaks the command that preloads it. The table lives in
`src/profiles.txt`.

## Uninstall

    ./install.sh uninstall [--target claude|codex|grok|all]
    ./install.sh uninstall --dry-run    # list what would go, delete nothing

It removes exactly what `.dm-manifest` lists — the files the install put there. Commands
and skills you wrote yourself are not in the manifest, so they survive. Templates,
`docs/`, `.dm/` and `AGENTS.md` are left in place: they hold your work, not the tooling.
Git hooks come off with `git config --unset core.hooksPath`.

## Update

From your project's root:

    ~/tools/ai-driven-method/install.sh update              # Claude
    ~/tools/ai-driven-method/install.sh update --target codex   # Codex
    ~/tools/ai-driven-method/install.sh update --target grok    # Grok
    # or, without a clone:
    curl -fsSL https://raw.githubusercontent.com/theo-jim/ai-driven-method/main/install.sh | bash -s -- update
    # overwrite locally modified templates too:
    curl -fsSL https://raw.githubusercontent.com/theo-jim/ai-driven-method/main/install.sh | bash -s -- update --force

What it does — and doesn't:
- Cleanly replaces the method's tooling, tracked per target in `.dm-manifest` (`.claude/`, `.codex/`, or `.grok/` — your own commands/skills are never touched, renamed or removed files leave no ghosts).
- Refreshes the templates you haven't modified; a locally modified template is never overwritten (you get a warning instead — add `--force` to overwrite).
- Stamps the installed version in `.dm-version`.
- Never touches `AGENTS.md`: if the method's rules evolved, merge by hand.

## Usage

    # existing project (code already there):
    /dm-continue
    # then:
    /dm-prd
    /dm-init
    /dm-stories
    /dm-stories-review
    /dm-architect
    /dm-design-system
    # then, per story (framing — branch feature/<story>, docs only):
    /dm-research <story>
    /dm-design <story>
    /dm-plan <story>
    /dm-docs <story>
    # then, per ticket (child must be ready — branch feature/<story>/<ticket>):
    /dm-execute <story> <ticket>
    /dm-review <story> <ticket>
    /dm-ship <story> <ticket>
    # production:
    /dm-release

    # after v1, a new feature:
    /dm-feature <slug>

    # or run with human checkpoints:
    /dm-orchestrator <story>            # research → design → plan → docs
    /dm-orchestrator <story> <ticket>   # execute → review → ship

    # where does the project stand?
    /dm-status

    # lost? pipeline map (français) :
    /dm-help

On **Codex** / **Grok**, the same steps run as skills or commands (e.g. `dm-prd`, `dm-execute`) — same order, same gates. The git hooks (`--hooks`) enforce the pipeline the same way on every tool.

## Manual smoke

Method CI does not live-mutate GitHub. After install, smoke `/dm-init` on a **throwaway** repo:

    mkdir /tmp/dm-smoke && cd /tmp/dm-smoke && git init -b main
    # install driven into this directory (see Install), then in the tool:
    /dm-prd
    /dm-init
    # confirm remote / board / wiki, then delete the throwaway repo
