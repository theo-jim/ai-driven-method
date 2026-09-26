---
description: Release the integration branch → main — bump VERSION, tag, wiki per US, board shipped
allowed-tools:
  - Read
  - Bash
  - AskUserQuestion
---
# dm-release — Production release (integration branch → `main`)

Resolve the integration branch once: `INTEG="$(bash .dm/lib/dm-gate.sh default-integration-branch)"`.
- If `$INTEG` is `develop`: work from the repository base on branch `develop`. Never release from a feature branch.
- If `$INTEG` is `main` (no `develop`): tickets already land on `main` directly — there
  is no branch to merge. This command only bumps VERSION, tags, publishes the wiki,
  and marks the board `shipped`; Steps 3–4 use a dedicated short-lived branch since
  `main` is protected and cannot take a direct commit.

## Step 1 — Candidates
List **parent** US Issues currently in status `test` (children already merged into the integration branch). Use `bash .dm/lib/dm-board.sh status-get <story-id>` for each story id in docs/stories.md; keep those whose status is exactly `test`.

No parent in `test` → STOP: "Nothing to release — ship tickets until their parent US reaches test."

Present the candidate US ids (and their children) to the user.

## Step 2 — Semver
AskUserQuestion: bump type — options major / **minor** (default) / patch.

## Step 3 — Bump (once per release)
Refuse a second bump if VERSION on the head branch already differs from `main` **and** a release PR is already open:

```bash
git fetch origin main "$INTEG" 2>/dev/null || git fetch origin main
main_ver="$(git show origin/main:VERSION 2>/dev/null | tr -d '[:space:]' || true)"
head_ver="$(tr -d '[:space:]' < VERSION)"
if [ -n "$main_ver" ] && [ "$head_ver" != "$main_ver" ]; then
  open="$(gh pr list --base main --state open --json url,headRefName --jq ".[] | select(.headRefName | startswith(\"release/\") or . == \"$INTEG\") | .url" | head -1)"
  if [ -n "$open" ]; then
    echo "Release already in flight ($open). VERSION is $head_ver vs main $main_ver. Do not bump again — squash-merge that PR."
    exit 1
  fi
fi
```

If that check passes:
```bash
bash .dm/lib/dm-version.sh bump <major|minor|patch>
ver="$(tr -d '[:space:]' < VERSION)"
```

- With `develop` (`$INTEG` = `develop`): commit `VERSION`, `CHANGELOG.md`, and any synced `package.json` / `pyproject.toml` on `develop` (message like `chore: release v$ver`). Push `develop`.
- Without `develop` (`$INTEG` = `main`): create `release/v$ver` from `main`, commit the same files there, push that branch instead of committing to `main`.

## Step 4 — PR into `main`
```bash
head="$INTEG"
[ "$INTEG" = main ] && head="release/v$ver"
gh pr create --base main --head "$head" --title "Release v$ver" --body "…"
```
Do **not** merge in this command unless the user explicitly confirms an auto merge. Default: stop at the open PR.

**Always squash-merge** this PR (`gh pr merge --squash` or the GitHub squash-merge button). One release = one commit on `main`. Never merge-commit the head branch into `main`.

## Step 5 — After MERGED only
Prove merge: `gh pr view <url> --json state --jq .state` must be `MERGED`. Then:

1. Fetch `origin/main` and tag **that** SHA (the squash commit on `main`), never the head branch's SHA:
   ```bash
   git fetch origin main
   ver="$(tr -d '[:space:]' < VERSION)"
   main_sha="$(git rev-parse origin/main)"
   git tag "v${ver}" "$main_sha"
   git push origin "v${ver}"
   ```
2. Wiki (one page per US in this release):
   ```bash
   bash .dm/lib/dm-wiki.sh publish "$(pwd)" "$(cat VERSION)" <story-id...>
   ```
3. Board — for each released parent and **every** of its children:
   ```bash
   bash .dm/lib/dm-board.sh status-set <story-id> shipped
   bash .dm/lib/dm-board.sh status-set <story-id>/<ticket-id> shipped
   ```
   Optionally `parent-sync <story-id>` after children are shipped.
4. Without `develop`: delete the merged `release/v$ver` branch (`git push origin --delete release/v$ver`).

End with: "Released vX.Y.Z — wiki updated, board shipped." or the open PR URL if still awaiting merge.
