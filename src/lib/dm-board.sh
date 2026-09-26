#!/usr/bin/env bash
# dm-board — board status helpers: GitHub Issues + Project V2, or GitLab Issues +
# status labels (dm-board-gitlab.sh overrides the platform functions below).
# Status labels exact: backlog | ready | in progress | test | shipped
# Parent never uses ready.
#
#   status-get <issue-key>
#   status-set <issue-key> <status>
#   issue-create-us <story-id> <title> <body-file>
#   issue-create-ticket <story-id> <ticket-id> <title> <body-file>
#   require-ready <story-id>/<ticket-id>
#   parent-sync <story-id>
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=dm-config.sh
source "$SCRIPT_DIR/dm-config.sh"

gh_bin() { command -v gh; }

# dm_config_load, then swap in the GitLab implementations when the project is on GitLab.
board_load() {
  dm_config_load
  if [ "${DM_PLATFORM:-github}" = gitlab ]; then
    if [ ! -f "$SCRIPT_DIR/dm-board-gitlab.sh" ]; then
      echo "dm-board: platform gitlab but $SCRIPT_DIR/dm-board-gitlab.sh is missing — reinstall .dm/lib" >&2
      return 1
    fi
    # shellcheck source=dm-board-gitlab.sh
    source "$SCRIPT_DIR/dm-board-gitlab.sh"
  fi
}

issues_json() {
  "$(gh_bin)" issue list \
    -R "$(dm_config_repo)" \
    --state all \
    --limit 200 \
    --json title,number,id,projectItems
}

# Exact title key match: "[key] ..." or "[key]"
find_issue_json() {
  local key="$1"
  issues_json | node -e '
    const key = process.argv[1];
    const prefix = "[" + key + "]";
    const issues = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const hit = issues.find((i) => {
      const t = i.title || "";
      return t === prefix || t.startsWith(prefix + " ");
    });
    if (!hit) process.exit(2);
    process.stdout.write(JSON.stringify(hit));
  ' "$key"
}

issue_status_name() {
  local key="$1"
  local raw
  if ! raw="$(find_issue_json "$key")"; then
    echo "dm-board: issue not found for key '$key'" >&2
    return 1
  fi
  node -e '
    const issue = JSON.parse(process.argv[1]);
    const items = issue.projectItems || [];
    if (!items.length || !items[0].status || !items[0].status.name) {
      console.error("dm-board: no project status for "+(issue.title||""));
      process.exit(1);
    }
    process.stdout.write(String(items[0].status.name));
  ' "$raw"
}

issue_project_item_id() {
  local key="$1"
  local raw
  raw="$(find_issue_json "$key")"
  node -e '
    const issue = JSON.parse(process.argv[1]);
    const items = issue.projectItems || [];
    if (!items.length || !items[0].id) {
      console.error("dm-board: no project item id");
      process.exit(1);
    }
    process.stdout.write(String(items[0].id));
  ' "$raw"
}

cmd_status_get() {
  local key="${1:-}"
  [ -n "$key" ] || { echo "usage: status-get <issue-key>" >&2; return 1; }
  board_load
  issue_status_name "$key"
  printf '\n'
}

cmd_status_set() {
  local key="${1:-}" status="${2:-}"
  [ -n "$key" ] && [ -n "$status" ] || {
    echo "usage: status-set <issue-key> <status>" >&2
    return 1
  }
  case "$status" in
    backlog|ready|"in progress"|test|shipped) ;;
    *)
      echo "dm-board: invalid status '$status' (backlog|ready|in progress|test|shipped)" >&2
      return 1
      ;;
  esac
  # Parent keys never use ready
  case "$key" in
    */*) ;;
    *)
      if [ "$status" = "ready" ]; then
        echo "dm-board: parent US must not use status 'ready'" >&2
        return 1
      fi
      ;;
  esac
  board_load
  board_set_status "$key" "$status"
}

board_set_status() {
  local key="$1" status="$2" item_id option_id
  item_id="$(issue_project_item_id "$key")"
  option_id="$(dm_config_status_option_id "$status")"
  "$(gh_bin)" project item-edit \
    --id "$item_id" \
    --project-id "$DM_PROJECT_ID" \
    --field-id "$DM_STATUS_FIELD_ID" \
    --single-select-option-id "$option_id" \
    >/dev/null
}

cmd_require_ready() {
  local key="${1:-}"
  [ -n "$key" ] || { echo "usage: require-ready <story-id>/<ticket-id>" >&2; return 1; }
  case "$key" in
    */*) ;;
    *)
      echo "dm-board: require-ready is child-only (got '$key')" >&2
      return 1
      ;;
  esac
  board_load
  local st
  if ! st="$(issue_status_name "$key")"; then
    return 1
  fi
  case "$st" in
    ready|"in progress") return 0 ;;
    *)
      echo "dm-board: '$key' status is '$st' (need ready or in progress)" >&2
      return 1
      ;;
  esac
}

derive_parent_status() {
  # stdin: one child status per line → prints parent status
  node -e '
    const lines = require("fs").readFileSync(0, "utf8").split(/\n/).map((s) => s.trim()).filter(Boolean);
    if (!lines.length) {
      process.stdout.write("backlog");
      process.exit(0);
    }
    const all = (set) => lines.every((s) => set.has(s));
    const any = (set) => lines.some((s) => set.has(s));
    if (all(new Set(["shipped"]))) process.stdout.write("shipped");
    else if (all(new Set(["test", "shipped"]))) process.stdout.write("test");
    else if (any(new Set(["in progress", "test", "shipped"]))) process.stdout.write("in progress");
    else process.stdout.write("backlog");
  '
}

cmd_parent_sync() {
  local story="${1:-}"
  [ -n "$story" ] || { echo "usage: parent-sync <story-id>" >&2; return 1; }
  case "$story" in
    */*)
      echo "dm-board: parent-sync expects story-id only" >&2
      return 1
      ;;
  esac
  board_load
  local children_statuses desired current
  children_statuses="$(
    issues_json | node -e '
      const story = process.argv[1];
      const needle = "[" + story + "/";
      const issues = JSON.parse(require("fs").readFileSync(0, "utf8"));
      for (const i of issues) {
        const t = i.title || "";
        if (!t.startsWith(needle)) continue;
        const st = (i.projectItems && i.projectItems[0] && i.projectItems[0].status && i.projectItems[0].status.name) || "";
        if (st) console.log(st);
      }
    ' "$story"
  )"
  desired="$(printf '%s\n' "$children_statuses" | derive_parent_status)"
  if ! current="$(issue_status_name "$story" 2>/dev/null)"; then
    echo "dm-board: parent issue '$story' not found" >&2
    return 1
  fi
  if [ "$current" = "$desired" ]; then
    printf '%s\n' "$desired"
    return 0
  fi
  cmd_status_set "$story" "$desired"
  printf '%s\n' "$desired"
}

extract_issue_number_from_url() {
  node -e '
    const u = process.argv[1];
    const m = u.match(/\/issues\/(\d+)/);
    if (!m) { console.error("dm-board: cannot parse issue url "+u); process.exit(1); }
    process.stdout.write(m[1]);
  ' "$1"
}

add_issue_to_project_backlog() {
  local url="$1"
  local key_guess="$2"
  local number item_id
  number="$(extract_issue_number_from_url "$url")"
  if [ -n "${DM_PROJECT_NUMBER:-}" ]; then
    if ! "$(gh_bin)" project item-add "$DM_PROJECT_NUMBER" \
      --owner "$DM_OWNER" \
      --url "$url" \
      --format json >/dev/null 2>&1; then
      echo "dm-board: item-add failed for issue #${number} (${key_guess}), retrying once" >&2
      if ! "$(gh_bin)" project item-add "$DM_PROJECT_NUMBER" \
        --owner "$DM_OWNER" \
        --url "$url" \
        --format json >/dev/null 2>&1; then
        echo "dm-board: WARNING: issue #${number} (${key_guess}) could not be added to the project board" >&2
      fi
    fi
  fi
  if item_id="$(issue_project_item_id "$key_guess" 2>/dev/null)"; then
    local option_id
    option_id="$(dm_config_status_option_id "backlog")"
    "$(gh_bin)" project item-edit \
      --id "$item_id" \
      --project-id "$DM_PROJECT_ID" \
      --field-id "$DM_STATUS_FIELD_ID" \
      --single-select-option-id "$option_id" \
      >/dev/null
  else
    echo "dm-board: WARNING: issue #${number} (${key_guess}) has no project item — not on the board" >&2
  fi
  printf '%s\n' "$number"
}

# When GitHub sub-issues are unavailable: Parent: #<n> in the body + label ticket.
fallback_parent_link() {
  local child_num="$1" parent_num="$2" body_file="$3"
  local repo tmp
  repo="$(dm_config_repo)"
  tmp="$(mktemp)"
  cat "$body_file" >"$tmp"
  if ! grep -q "^Parent: #${parent_num}$" "$tmp" 2>/dev/null; then
    printf '\n\nParent: #%s\n' "$parent_num" >>"$tmp"
  fi
  "$(gh_bin)" label create ticket -R "$repo" --force >/dev/null 2>&1 || \
    echo "dm-board: WARNING: could not ensure label 'ticket'" >&2
  if ! "$(gh_bin)" issue edit "$child_num" -R "$repo" \
    --body-file "$tmp" --add-label ticket >/dev/null; then
    echo "dm-board: WARNING: failed to write Parent: #${parent_num} on issue #${child_num}" >&2
  fi
  rm -f "$tmp"
}

issue_create() {
  local title="$1" body_file="$2"
  "$(gh_bin)" issue create -R "$(dm_config_repo)" -t "$title" -F "$body_file"
}

issue_rename() {
  local number="$1" title="$2"
  "$(gh_bin)" issue edit "$number" -R "$(dm_config_repo)" --title "$title" >/dev/null
}

issue_url() {
  printf 'https://github.com/%s/issues/%s' "$(dm_config_repo)" "$1"
}

# Link child <key> under the parent Issue JSON; exit 1 when the link could not be made.
link_sub_issue() {
  local parent_raw="$1" key="$2" parent_id child_id
  parent_id="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).id||"")' "$parent_raw")"
  child_id="$(node -e '
    const issues=JSON.parse(require("fs").readFileSync(0,"utf8"));
    const key=process.argv[1];
    const prefix="["+key+"]";
    const hit=issues.find(i=> (i.title||"")===prefix || (i.title||"").startsWith(prefix+" "));
    process.stdout.write(hit && hit.id ? hit.id : "");
  ' "$key" <<<"$(issues_json)" 2>/dev/null || true)"
  [ -n "$parent_id" ] && [ -n "$child_id" ] || return 1
  "$(gh_bin)" api graphql -f query='mutation($p:ID!,$c:ID!){addSubIssue(input:{issueId:$p,subIssueId:$c}){issue{id}}}' \
    -f p="$parent_id" -f c="$child_id" >/dev/null 2>&1
}

cmd_issue_create_us() {
  local story_id="${1:-}" title="${2:-}" body_file="${3:-}"
  [ -n "$story_id" ] && [ -n "$title" ] && [ -n "$body_file" ] || {
    echo "usage: issue-create-us <story-id> <title> <body-file>" >&2
    return 1
  }
  [ -f "$body_file" ] || { echo "dm-board: body file missing: $body_file" >&2; return 1; }
  board_load
  local full_title url
  full_title="[${story_id}] ${title}"
  url="$(issue_create "$full_title" "$body_file")"
  add_issue_to_project_backlog "$url" "$story_id"
}

# Adopt an Issue written by hand: rename to the driven convention, then board it.
# status-set cannot do this — it resolves an existing project item, and a
# hand-written Issue was never added to the project.
cmd_issue_adopt() {
  local key="${1:-}" number="${2:-}" title="${3:-}"
  [ -n "$key" ] && [ -n "$number" ] && [ -n "$title" ] || {
    echo "usage: issue-adopt <issue-key> <issue-number> <title>" >&2
    return 1
  }
  board_load
  local full_title url
  full_title="[${key}] ${title}"
  issue_rename "$number" "$full_title"
  url="$(issue_url "$number")"
  add_issue_to_project_backlog "$url" "$key"
}

cmd_issue_create_ticket() {
  local story_id="${1:-}" ticket_id="${2:-}" title="${3:-}" body_file="${4:-}"
  [ -n "$story_id" ] && [ -n "$ticket_id" ] && [ -n "$title" ] && [ -n "$body_file" ] || {
    echo "usage: issue-create-ticket <story-id> <ticket-id> <title> <body-file>" >&2
    return 1
  }
  [ -f "$body_file" ] || { echo "dm-board: body file missing: $body_file" >&2; return 1; }
  board_load
  local key full_title url parent_raw child_num
  key="${story_id}/${ticket_id}"
  full_title="[${key}] ${title}"
  url="$(issue_create "$full_title" "$body_file")"
  child_num="$(add_issue_to_project_backlog "$url" "$key")"
  # "fix" is a reserved namespace key, never a real parent — a fix ticket must
  # never be sub-issue-linked, even if an unrelated issue happens to be titled
  # "[fix]" or "[fix] ...".
  if [ "$story_id" != "fix" ] && parent_raw="$(find_issue_json "$story_id" 2>/dev/null)"; then
    local parent_num sub_ok=0
    parent_num="$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).number||""))' "$parent_raw")"
    if link_sub_issue "$parent_raw" "$key"; then
      sub_ok=1
    fi
    if [ "$sub_ok" -eq 0 ] && [ -n "$parent_num" ]; then
      echo "dm-board: WARNING: sub-issue link failed for $key — writing Parent: #${parent_num} and label ticket" >&2
      fallback_parent_link "$child_num" "$parent_num" "$body_file"
    fi
  fi
  printf '%s\n' "$child_num"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    status-get) shift; cmd_status_get "$@" ;;
    status-set) shift; cmd_status_set "$@" ;;
    issue-create-us) shift; cmd_issue_create_us "$@" ;;
    issue-create-ticket) shift; cmd_issue_create_ticket "$@" ;;
    issue-adopt) shift; cmd_issue_adopt "$@" ;;
    require-ready) shift; cmd_require_ready "$@" ;;
    parent-sync) shift; cmd_parent_sync "$@" ;;
    *)
      echo "usage: dm-board.sh status-get|status-set|issue-create-us|issue-create-ticket|issue-adopt|require-ready|parent-sync ..." >&2
      return 1
      ;;
  esac
}

main "$@"
