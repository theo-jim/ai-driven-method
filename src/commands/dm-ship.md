---
description: Open the pull/merge request into the integration branch; merge per the project's ship strategy (manual by default)
argument-hint: <story id> <ticket id>
allowed-tools:
  - Read
  - Bash
---
You are shipping a **ticket**. Target: $ARGUMENTS

Resolve $ARGUMENTS to `<story-id>` and `<ticket-id>` (`s<number>-<slug>` and `t<number>-<slug>`). The review file `docs/reviews/<story-id>/<ticket-id>.md` must exist. Full work id: `<story-id>/<ticket-id>`.

Resolve the integration branch: `INTEG="$(bash .dm/lib/dm-gate.sh default-integration-branch)"` — `develop` if the project has one, otherwise `main` directly.

Every pull/merge request call goes through `bash .dm/lib/dm-vcs.sh` — it runs `gh` on
GitHub and `glab` on GitLab (`.dm/config.json` → `"platform"`), so never call `gh pr` or
`glab mr` directly. "PR" below means a GitHub pull request or a GitLab merge request.

Locate `.worktrees/<story-id>/<ticket-id>`, verify its branch is exactly
`feature/<story-id>/<ticket-id>`, and run the entire command from that absolute
worktree. Missing worktree, wrong branch, detached HEAD or repository base →
STOP; never checkout the feature branch in the repository base directory.

## Step 0 — Gate (fail-closed, mechanical)
Run: `grep -q '^Ship allowed: yes' docs/reviews/<story-id>/<ticket-id>.md`
If the file is missing or the command fails, STOP immediately: "Ship blocked — review missing or negative. Run /dm-review <story-id> <ticket-id>." Nothing below runs without a passing gate.

Board gate (child only), same as execute:
```bash
bash .dm/lib/dm-board.sh require-ready <story-id>/<ticket-id>
```
Exit non-zero → STOP: move the child to `ready` (or it must already be `in progress`) first. Parent US never uses `ready`.

Require `docs/product/<story-id>.md` (from `/dm-docs`). Missing → STOP: "Product doc required — run /dm-docs <story-id>."

Then proceed:
1. Without switching branches, commit `docs/reviews/<story-id>/<ticket-id>.md` on the already verified ticket branch if not already committed (the PR must carry its review). Then verify the tests pass. Failing tests → stop.
2. If a PR for `feature/<story-id>/<ticket-id>` already exists, don't open a duplicate — check its state with `bash .dm/lib/dm-vcs.sh pr-state feature/<story-id>/<ticket-id>` (non-zero exit = no PR yet): MERGED → jump straight to the Cleanup step; OPEN → continue. Otherwise push the branch, write the description to a temporary file, and open a clean PR from `feature/<story-id>/<ticket-id>` to **`$INTEG`**: `bash .dm/lib/dm-vcs.sh pr-create "$INTEG" feature/<story-id>/<ticket-id> "<title>" <body-file>` (prints the PR URL). Clear title, structured description (what, why, how to test), readable diff. Include the review verdict (max severity + findings summary) in the PR body.
3. Read the ship strategy from AGENTS.md ("Ship strategy" section). No section, or no explicit `auto` → the mode is manual.

## Step 4 — Merge (per the ship strategy)

**Always squash.** One ticket = one commit on `$INTEG`. The working commits stay on the branch, the history stays readable, and no merge commit is created.

- **manual (default): do NOT merge.** End with: "PR opened: <url> (base: `$INTEG`). Merging is yours to decide (human review, protected branch, CI) — **squash-merge it**. After merging, rerun /dm-ship <story-id> <ticket-id> to clean up the ticket worktree."
- **auto**: `bash .dm/lib/dm-vcs.sh pr-merge <url>` (squash, source branch kept — on GitLab it clears the MR's "delete source branch" flag, then fails if the branch is gone after the merge), then run the Cleanup step. End with: "Ticket merged into `$INTEG`. Cycle complete for this ticket."

Never merge in manual mode, even if everything is green — the gate authorizes the ship, the human decides it. When the project has a `develop` branch, never open or merge a PR into `main` from this command; production is `/dm-release` (`develop` → `main`). Without `develop`, `$INTEG` is `main` itself — that is the intended ship target, not a bypass.

## Final step — Cleanup (ONLY after a PROVEN merge)
Never clean up on the promise of a merge — only on proof:
1. Verify: `bash .dm/lib/dm-vcs.sh pr-state feature/<story-id>/<ticket-id>` must print exactly `MERGED`. An OPEN PR, a closed-unmerged PR, or an "about to be merged" does NOT qualify: skip cleanup entirely.

   Do NOT use `git merge-base --is-ancestor` here: a squash merge rewrites the work into a new commit, so the branch's commits are never ancestors of `$INTEG`. The check would fail on every correctly merged ticket and no branch would ever be cleaned up.
2. Verify the dedicated ticket worktree is clean, then remove that exact worktree with
   `git worktree remove <repository-base>/.worktrees/<story-id>/<ticket-id>`. A dirty worktree is
   a hard stop; never use `--force`.
3. Only after the worktree is gone, delete the branch, local and remote:
   `git branch -D feature/<story-id>/<ticket-id>` and `git push origin --delete feature/<story-id>/<ticket-id>`.

   `-D` is required, again because of the squash: `-d` refuses a branch git
   considers unmerged, which is every squashed branch. The safety therefore
   rests entirely on step 1 — never remove the worktree or branch without the
   `MERGED` proof.
4. Board — child to `test`, then derive parent:
   ```bash
   bash .dm/lib/dm-board.sh status-set <story-id>/<ticket-id> test
   bash .dm/lib/dm-board.sh parent-sync <story-id>
   ```
   (`parent-sync` moves the parent US to `test` only when every child is `test` or `shipped`; parent never uses `ready`.)

The content is on `$INTEG`, the audit trail is in the merged PR: the ticket branch has no further use.
