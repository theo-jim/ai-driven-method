---
description: Bootstrap the app repo — GitHub or GitLab remote, main (+ optional develop), board, wiki, VERSION, CI
allowed-tools:
  - Read
  - Bash
  - AskUserQuestion
---
# dm-init — Repo + board bootstrap

## Prerequisites (fail-closed)
- `docs/prd.md` must exist. Missing → STOP: "No PRD — run /dm-prd first."
- The platform CLI authenticated: `gh` for GitHub, `glab` for GitLab. Missing → STOP and
  ask the user to run `gh auth login` / `glab auth login` (add `--hostname <host>` for a
  self-managed GitLab).

## Confirm with the user (AskUserQuestion, one at a time)
1. Platform: GitHub or GitLab. When `origin` exists, propose what
   `bash .dm/lib/dm-vcs.sh detect "$(git remote get-url origin)"` prints; it fails on a host
   it cannot place (self-managed GitLab on a custom domain) → ask, and for GitLab also ask
   the host (`--host`, default `gitlab.com`).
2. Create a remote? (yes / no — local-only with `--no-remote`)
3. Repository name (default: current directory basename)
4. Visibility: public / private (default private)
5. Owner: user or org login on GitHub, user or group path on GitLab (default: the authenticated user)
6. Board title (default: driven) — the Project V2 on GitHub, the Issue Board on GitLab
7. Use a `develop` integration branch? (yes / no — no-`develop` with `--no-develop`; default yes)

Nothing is created without confirmation.

## Actions
Run the mechanical bootstrap (post-install path):

```bash
bash .dm/lib/dm-init.sh run \
  --repo <name> \
  --owner <login> \
  --public|--private \
  --title <project-title> \
  --platform github|gitlab \
  [--host <gitlab-host>] \
  [--no-remote] \
  [--no-develop] \
  --yes
```

If `.dm/lib/dm-init.sh` is missing, the method was not installed into this app — stop and point to `install.sh` (it must copy `src/lib` → `.dm/lib`).

The script is idempotent: existing remote / `develop` / project / wiki / `VERSION` are detected and only gaps are filled. `.dm/config.json` records `"platform"`; every later command reads it.

| | GitHub | GitLab |
| --- | --- | --- |
| Remote | `gh repo create` | `glab repo create` |
| Protection | branch protection + rulesets | protected branches (push: no one, merge through a merge request) |
| Board | Project V2, single-select `Status` field | one label per status (`dm::backlog` … `dm::shipped`) + Issue Board lists |
| Wiki | `has_wiki` | `wiki_access_level=enabled` |
| CI gate | `.github/workflows/dm-gate.yml` | `.gitlab/ci/dm-gate.yml`, included from `.gitlab-ci.yml` |

GitLab cannot restrict which source branch targets a protected branch: the `dm-gate` CI
job carries the "`main` only from `develop`" rule. Tell the user to enable **Pipelines
must succeed** if they want it blocking.

End with: what was created (remote URL, `develop` or "no develop — main only", project, `.dm/config.json`, `VERSION`), then "Next: /dm-stories".
