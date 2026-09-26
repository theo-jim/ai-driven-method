#!/usr/bin/env bash
# dm-board-gitlab — GitLab implementations of dm-board.sh's platform functions.
# Sourced by dm-board.sh (board_load) after dm_config_load, never run directly.
# GitLab has no Project V2 single-select field: the board status is one label per
# status (.dm/config.json status_labels, e.g. "dm::ready"), shown as Issue Board
# lists. Exactly one status label per Issue — set_status removes the other four,
# since scoped-label exclusivity is a paid tier feature.

# shellcheck source=dm-vcs.sh
source "$SCRIPT_DIR/dm-vcs.sh"

export GITLAB_HOST="${GITLAB_HOST:-$DM_HOST}"
GL_PROJECT="projects/$(dm_vcs_urlencode "$(dm_config_repo)")"

# Same shape as `gh issue list --json title,number,id,projectItems`: projectItems
# holds one {id, status:{name}} when the Issue carries exactly one status label.
issues_json() {
  dm_glab api "${GL_PROJECT}/issues?state=all&per_page=100" --paginate --output ndjson | node -e '
    const labels = JSON.parse(process.env.DM_STATUS_JSON || "{}");
    const byLabel = Object.fromEntries(Object.entries(labels).map(([s, l]) => [l, s]));
    const out = require("fs").readFileSync(0, "utf8").split("\n").filter(Boolean).map((line) => {
      const i = JSON.parse(line);
      const found = (i.labels || []).filter((l) => l in byLabel);
      return {
        title: i.title,
        number: i.iid,
        id: String(i.id),
        projectItems: found.length === 1 ? [{ id: String(i.iid), status: { name: byLabel[found[0]] } }] : [],
      };
    });
    process.stdout.write(JSON.stringify(out));
  '
}

# Issue iid → status label on, the four others off.
gl_apply_status_label() {
  local number="$1" status="$2" label others
  label="$(dm_config_status_option_id "$status")"
  others="$(node -e '
    const map = JSON.parse(process.env.DM_STATUS_JSON || "{}");
    process.stdout.write(Object.values(map).filter((l) => l !== process.argv[1]).join(","));
  ' "$label")"
  dm_glab api -X PUT "${GL_PROJECT}/issues/${number}" \
    -f "add_labels=${label}" -f "remove_labels=${others}" >/dev/null
}

board_set_status() {
  local key="$1" status="$2" raw number
  if ! raw="$(find_issue_json "$key")"; then
    echo "dm-board: issue not found for key '$key'" >&2
    return 1
  fi
  number="$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).number||""))' "$raw")"
  gl_apply_status_label "$number" "$status"
}

issue_create() {
  local title="$1" body_file="$2"
  dm_glab api -X POST "${GL_PROJECT}/issues" \
    -f "title=${title}" -f "description=$(cat "$body_file")" \
    -f "labels=$(dm_config_status_option_id backlog)" \
    | node -e '
      const i = JSON.parse(require("fs").readFileSync(0, "utf8"));
      if (!i.web_url) { console.error("dm-board: GitLab issue create returned no web_url"); process.exit(1); }
      console.log(i.web_url);
    '
}

issue_rename() {
  local number="$1" title="$2"
  dm_glab api -X PUT "${GL_PROJECT}/issues/${number}" -f "title=${title}" >/dev/null
}

issue_url() {
  printf 'https://%s/%s/-/issues/%s' "$DM_HOST" "$(dm_config_repo)" "$1"
}

# No item to add on GitLab: being on the board = carrying a status label.
add_issue_to_project_backlog() {
  local url="$1" key_guess="$2" number
  number="$(extract_issue_number_from_url "$url")"
  if ! gl_apply_status_label "$number" backlog; then
    echo "dm-board: WARNING: issue #${number} (${key_guess}) could not be labelled backlog — not on the board" >&2
  fi
  printf '%s\n' "$number"
}

# Issue links are the hierarchy available on every GitLab tier.
link_sub_issue() {
  local parent_raw="$1" key="$2" parent_num child_raw child_num
  parent_num="$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).number||""))' "$parent_raw")"
  child_raw="$(find_issue_json "$key" 2>/dev/null)" || return 1
  child_num="$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).number||""))' "$child_raw")"
  [ -n "$parent_num" ] && [ -n "$child_num" ] || return 1
  dm_glab api -X POST "${GL_PROJECT}/issues/${parent_num}/links" \
    -f "target_project_id=$(dm_config_repo)" -f "target_issue_iid=${child_num}" >/dev/null 2>&1
}

fallback_parent_link() {
  local child_num="$1" parent_num="$2" body_file="$3" tmp
  tmp="$(mktemp)"
  cat "$body_file" >"$tmp"
  if ! grep -q "^Parent: #${parent_num}$" "$tmp" 2>/dev/null; then
    printf '\n\nParent: #%s\n' "$parent_num" >>"$tmp"
  fi
  dm_glab api -X POST "${GL_PROJECT}/labels" -f name=ticket -f color=#428BCA >/dev/null 2>&1 || true
  if ! dm_glab api -X PUT "${GL_PROJECT}/issues/${child_num}" \
    -f "description=$(cat "$tmp")" -f add_labels=ticket >/dev/null; then
    echo "dm-board: WARNING: failed to write Parent: #${parent_num} on issue #${child_num}" >&2
  fi
  rm -f "$tmp"
}
