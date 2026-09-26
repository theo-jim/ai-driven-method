#!/usr/bin/env bash
# dm-gate — driven repo-level guardrails, enforced by git (tool-independent).
# Works the same whether the harness is Claude Code, Codex or Gemini CLI:
# the gates live in the repo, not in a tool's per-command permissions.
#
# Branches (app git flow):
#   main     = production (only updated from the integration branch; server-side branch
#              protection is the real guarantee)
#   develop  = integration (optional — see .dm/config.json "develop"; feature PRs/MRs
#              land here when present, otherwise feature/* targets main directly)
#   feature/<story-id>              = story framing (docs only)
#   feature/<story-id>/<ticket-id>  = ticket implementation
#
# Subcommands:
#   dm-gate plan-validated <id>              exit 0 if docs/plans/<story>.md has `validated: yes`
#   dm-gate ship-allowed  <id>               exit 0 if the review has `Ship allowed: yes`
#   dm-gate ready-ok [story/ticket]          exit 0 if board child is ready|in progress (or no config)
#   dm-gate default-integration-branch       prints `develop` (or `main` when .dm/config.json has "develop": false)
#   dm-gate quickfix-push                    push a Quick Fix directly, falling back to a PR when refused
#   dm-gate pre-commit                       block code without validated plan + ready child;
#                                            block app code on story framing branches (docs only)
#   dm-gate pre-push                         refuse non-integration pushes into main; gate ticket merges into the integration branch
set -euo pipefail

repo_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# Reads .dm/config.json's "develop" field (default true when missing or unreadable).
# false → the project has no integration branch; "the integration branch" is main.
integration_branch() {
  local root cfg out
  root="$(repo_root)"
  cfg="$root/.dm/config.json"
  if [ -f "$cfg" ] && command -v node >/dev/null 2>&1; then
    out="$(node -e '
      const fs = require("fs");
      try {
        const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        process.stdout.write(cfg.develop === false ? "main" : "develop");
      } catch (e) {
        process.stdout.write("develop");
      }
    ' "$cfg" 2>/dev/null)"
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
  fi
  printf 'develop'
}
production_branch() { printf 'main'; }

# Reads the project's ship strategy (same "Merge mode:" line /dm-ship reads).
# Missing or malformed configuration remains manual: opening a PR does not
# authorize merging it. Case/markdown-tolerant, but still requires "auto" to
# be the word immediately after "Merge mode:" — not just present anywhere on
# the line, since the line's own parenthetical always mentions "auto".
quickfix_merge_mode() {
  local root mode="manual" match
  root="$(repo_root)"
  if [ -f "$root/AGENTS.md" ]; then
    match="$(awk '{
      l = tolower($0); gsub(/\*/, "", l)
      if (l ~ /^merge mode:[ \t]+auto([ \t]|$)/) { print "auto"; exit }
    }' "$root/AGENTS.md" 2>/dev/null || true)"
    [ "$match" = "auto" ] && mode="auto"
  fi
  printf '%s' "$mode"
}

quickfix_fallback_branch() {
  local stamp sha branch attempt=1
  stamp="$(date -u +%Y%m%d%H%M%S)"
  sha="$(git rev-parse --short HEAD)"
  branch="quickfix/${stamp}-${sha}"
  while git show-ref --verify --quiet "refs/heads/$branch" \
    || git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    branch="quickfix/${stamp}-${sha}-${attempt}"
  done
  printf '%s' "$branch"
}

# Quick Fixes commit on the integration branch. A rejected direct push is
# recovered through a temporary PR, which follows the same manual/auto ship
# strategy as /dm-ship. The branch is deliberately left intact unless GitHub
# proves that the squash merge completed.
quickfix_push() {
  local integ fallback title body url mode state current
  integ="$(integration_branch)"
  current="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$current" != "$integ" ]; then
    echo "dm-gate: quickfix-push must run on the integration branch ('$integ'); currently on '$current'." >&2
    return 1
  fi

  if git push origin "$integ"; then
    printf 'Quick Fix pushed directly to %s.\n' "$integ"
    return 0
  fi

  echo "dm-gate: direct Quick Fix push to $integ was refused; opening a short-lived fallback PR." >&2
  fallback="$(quickfix_fallback_branch)"
  git branch "$fallback"
  git push origin "$fallback"

  title="Quick Fix: $(git log -1 --format=%s)"
  body="## What

Quick Fix commit $(git rev-parse --short HEAD).

## Why

The direct push to $integ was refused, so this PR uses the protected-branch path.

## How to test

Review the commit and run the verification recorded with this Quick Fix."
  url="$(gh pr create --base "$integ" --head "$fallback" --title "$title" --body "$body")"
  mode="$(quickfix_merge_mode)"

  if [ "$mode" = "manual" ]; then
    printf 'Quick Fix PR opened: %s (base: %s). Merging is yours to decide — squash-merge it.\n' "$url" "$integ"
    return 0
  fi

  if ! gh pr merge "$url" --squash --delete-branch=false; then
    echo "dm-gate: gh pr merge failed for $url; fallback branch kept for a retry." >&2
  fi

  state="$(gh pr view "$url" --json state,mergedAt --jq '.state')"
  if [ "$state" != "MERGED" ]; then
    echo "dm-gate: Quick Fix PR is '$state', not MERGED; fallback branch kept." >&2
    return 1
  fi

  git branch -D "$fallback"
  # GitHub can auto-delete the head branch server-side on merge regardless of
  # --delete-branch=false; tolerate that instead of crashing on a proven merge.
  git push origin --delete "$fallback" 2>/dev/null || true

  # The merge created a new squash commit on origin/$integ that local $integ
  # (still at the pre-fallback commit) has no ancestry relation to. Realign so
  # the next Quick Fix's direct push isn't rejected as non-fast-forward.
  git fetch origin "$integ"
  git reset --hard "origin/$integ"
  printf 'Quick Fix merged into %s and fallback branch %s was removed.\n' "$integ" "$fallback"
}

# Prefer app install path (.dm/lib); fall back to method-repo sibling of this hook.
resolve_board() {
  local root script_dir
  root="$(repo_root)"
  script_dir="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$root/.dm/lib/dm-board.sh" ]; then
    printf '%s' "$root/.dm/lib/dm-board.sh"
    return 0
  fi
  if [ -f "$script_dir/../lib/dm-board.sh" ]; then
    printf '%s' "$script_dir/../lib/dm-board.sh"
    return 0
  fi
  return 1
}

# feature/<story-id> or feature/<story-id>/<ticket-id> → id after feature/
# fix/<id> → fix/<id> unchanged (own namespace: no parent story, work id IS the branch)
story_id_from_branch() {
  local branch="$1"
  case "$branch" in
    feature/*) printf '%s' "${branch#feature/}" ;;
    fix/*) printf '%s' "$branch" ;;
    *) printf '' ;;
  esac
}

# s01-x/t01-y → s01-x; s01-x → s01-x (plan lives at docs/plans/<story-id>.md)
# fix/<id> → fix-<id> (hyphenated: docs/plans/fix-<id>.md, a top-level plans file)
# A malformed fix id (embedded slashes, uppercase, empty) is rejected outright
# rather than silently building a nonsensical nested path.
plan_id_from_work_id() {
  local id="$1"
  case "$id" in
    fix/*)
      if [[ ! "$id" =~ ^fix/[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        echo "dm-gate: malformed fix id '$id' (expected fix/<kebab-id>, e.g. fix/null-cart-crash)." >&2
        return 1
      fi
      printf 'fix-%s' "${id#fix/}"
      ;;
    */*) printf '%s' "${id%%/*}" ;;
    *) printf '%s' "$id" ;;
  esac
}

# feature/<story-id>/<ticket-id> → ticket-id; framing branch → empty
ticket_id_from_branch() {
  local id; id="$(story_id_from_branch "$1")"
  case "$id" in
    */*) printf '%s' "${id#*/}" ;;
    *) printf '' ;;
  esac
}

plan_validated() {
  local id="$1" root plan_id; root="$(repo_root)"
  plan_id="$(plan_id_from_work_id "$id")"
  local f="$root/docs/plans/$plan_id.md"
  [ -f "$f" ] || { echo "dm-gate: no plan for '$plan_id' (docs/plans/$plan_id.md missing). Run /dm-plan $plan_id." >&2; return 1; }
  if grep -qE '^validated:[[:space:]]*yes[[:space:]]*$' "$f"; then
    return 0
  fi
  echo "dm-gate: plan '$plan_id' not validated (docs/plans/$plan_id.md lacks 'validated: yes'). Validate it via /dm-plan $plan_id." >&2
  return 1
}

# id may be <story-id> or <story-id>/<ticket-id> → docs/reviews/<id>.md
ship_allowed() {
  local id="$1" root; root="$(repo_root)"
  local f="$root/docs/reviews/$id.md"
  [ -f "$f" ] || { echo "dm-gate: no review for '$id' (docs/reviews/$id.md missing). Run /dm-review $id." >&2; return 1; }
  if grep -qE '^Ship allowed:[[:space:]]*yes[[:space:]]*$' "$f"; then
    return 0
  fi
  echo "dm-gate: ship blocked for '$id' (docs/reviews/$id.md is not 'Ship allowed: yes')." >&2
  return 1
}

# Child ticket must be ready or in progress when the board is initialized.
# No .dm/config.json → warn and allow (board not initialized yet).
ready_ok() {
  local id="${1:-}" root cfg board st
  root="$(repo_root)"
  cfg="$root/.dm/config.json"

  if [ ! -f "$cfg" ]; then
    echo "dm-gate: no .dm/config.json — board ready-gate skipped (run /dm-init)." >&2
    return 0
  fi

  if [ -z "$id" ]; then
    local branch; branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
    id="$(story_id_from_branch "$branch")"
  fi

  case "$id" in
    */*) ;;
    *)
      # Parent / framing id — ready is child-only; callers enforce docs-only separately.
      return 0
      ;;
  esac

  if ! board="$(resolve_board)"; then
    echo "dm-gate: .dm/config.json present but dm-board.sh missing — cannot verify ready for '$id'." >&2
    return 1
  fi

  if ! st="$("$board" status-get "$id" 2>/dev/null | tr -d '\r' | head -n1)"; then
    echo "dm-gate: cannot read board status for '$id' (need ready or in progress)." >&2
    return 1
  fi
  st="${st%"${st##*[![:space:]]}"}"

  case "$st" in
    ready|"in progress") return 0 ;;
    *)
      echo "dm-gate: refusing — '$id' board status is '${st:-unknown}' (need ready or in progress)." >&2
      return 1
      ;;
  esac
}

pre_commit() {
  local branch id ticket; branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
  id="$(story_id_from_branch "$branch")"
  # Not on a feature branch → nothing to enforce here (e.g. Quick Fix on the integration branch).
  [ -n "$id" ] || return 0

  local code_staged=0 path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      docs/*) : ;;
      *) code_staged=1 ;;
    esac
  done < <(git diff --cached --name-only)
  [ "$code_staged" = 1 ] || return 0

  ticket="$(ticket_id_from_branch "$branch")"
  if [ -z "$ticket" ]; then
    echo "dm-gate: refusing code commit on $branch — story framing branches are docs-only. App code goes on feature/<story-id>/<ticket-id>." >&2
    return 1
  fi

  if ! plan_validated "$id"; then
    echo "dm-gate: refusing code commit on $branch — no validated plan for child '$ticket'. (docs-only commits are always allowed.)" >&2
    return 1
  fi

  if ! ready_ok "$id"; then
    return 1
  fi
  return 0
}

pre_push() {
  local prod integ; prod="$(production_branch)"; integ="$(integration_branch)"
  local local_ref local_sha remote_ref remote_sha rc=0 zero="0000000000000000000000000000000000000000"
  while read -r local_ref local_sha remote_ref remote_sha; do
    [ -n "${local_ref:-}" ] || continue
    [ "$local_sha" != "$zero" ] || continue

    # Production: when there is a distinct integration branch, only it may update
    # main. When there isn't (integ == prod, e.g. no develop), skip this block so
    # the integration checks below run for main itself instead of being short-
    # circuited by the `continue`. Client-side hint — server-side (GitHub/GitLab) branch protection is
    # authoritative either way.
    if [ "$remote_ref" = "refs/heads/$prod" ] && [ "$integ" != "$prod" ]; then
      if [ "$local_ref" != "refs/heads/$integ" ]; then
        echo "dm-gate: refusing push to $prod from ${local_ref#refs/heads/} — only $integ may update production. (server-side branch protection on GitHub/GitLab is the real guarantee for $prod.)" >&2
        rc=1
      fi
      continue
    fi

    # Integration: ticket branches need a passed review before landing on the integration branch.
    if [ "$remote_ref" = "refs/heads/$integ" ]; then
      local range id
      if printf '%s' "$remote_sha" | grep -qE '^0+$'; then
        range="$local_sha"
      else
        range="$remote_sha..$local_sha"
      fi

      case "$local_ref" in
        refs/heads/feature/*|refs/heads/fix/*)
          # Ticket/fix branches require Ship allowed; story framing (docs-only) does not.
          id="$(story_id_from_branch "${local_ref#refs/heads/}")"
          if [ -n "$(ticket_id_from_branch "${local_ref#refs/heads/}")" ] \
            && [ -n "$id" ] && ! ship_allowed "$id"; then
            echo "dm-gate: refusing to push $remote_ref — '$id' has no passed review." >&2
            rc=1
          fi
          ;;
      esac

      while IFS= read -r id; do
        [ -n "$id" ] || continue
        case "$id" in
          */*) ;; # ticket or fix work id
          *) continue ;; # story framing merge — no review file required
        esac
        if ! ship_allowed "$id"; then
          echo "dm-gate: refusing to push $remote_ref — ticket '$id' was merged without a passed review." >&2
          rc=1
        fi
      done < <(git log --merges --format='%s' "$range" 2>/dev/null \
                | sed -E -n "s/.*Merge branch '(feature\\/[^']*|fix\\/[^']*)'.*/\\1/p" \
                | sed 's#^feature/##' | sort -u)
    fi
  done
  return "$rc"
}

cmd="${1:-}"
case "$cmd" in
  plan-validated)               plan_validated "${2:?story id required}" ;;
  ship-allowed)                 ship_allowed   "${2:?story or ticket id required}" ;;
  ready-ok)                     ready_ok       "${2:-}" ;;
  default-integration-branch)   integration_branch; printf '\n' ;;
  quickfix-push)                quickfix_push ;;
  pre-commit)                   pre_commit ;;
  pre-push)                     pre_push ;;
  *)
    echo "usage: dm-gate {plan-validated <id>|ship-allowed <id>|ready-ok [story/ticket]|default-integration-branch|quickfix-push|pre-commit|pre-push}" >&2
    exit 2
    ;;
esac
