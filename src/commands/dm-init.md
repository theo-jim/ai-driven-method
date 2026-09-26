---
description: Bootstrap the app repo — remote, main (+ optional develop), Project board, wiki, VERSION, CI
allowed-tools:
  - Read
  - Bash
  - AskUserQuestion
---
# dm-init — Repo + board bootstrap

## Prerequisites (fail-closed)
- `docs/prd.md` must exist. Missing → STOP: "No PRD — run /dm-prd first."
- `gh` authenticated. Missing → STOP and ask the user to run `gh auth login`.

## Confirm with the user (AskUserQuestion, one at a time)
1. Create a GitHub remote? (yes / no — local-only with `--no-remote`)
2. Repository name (default: current directory basename)
3. Visibility: public / private (default private)
4. Owner: user or org login (default: authenticated `gh` user)
5. Project title (default: driven)
6. Use a `develop` integration branch? (yes / no — no-`develop` with `--no-develop`; default yes)

Nothing is created without confirmation.

## Actions
Run the mechanical bootstrap (post-install path):

```bash
bash .dm/lib/dm-init.sh run \
  --repo <name> \
  --owner <login> \
  --public|--private \
  --title <project-title> \
  [--no-remote] \
  [--no-develop] \
  --yes
```

If `.dm/lib/dm-init.sh` is missing, the method was not installed into this app — stop and point to `install.sh` (it must copy `src/lib` → `.dm/lib`).

The script is idempotent: existing remote / `develop` / project / wiki / `VERSION` are detected and only gaps are filled. It also copies `.dm/workflows/dm-gate.yml` (or the method template) into `.github/workflows/dm-gate.yml`.

End with: what was created (remote URL, `develop` or "no develop — main only", project, `.dm/config.json`, `VERSION`), then "Next: /dm-stories".
