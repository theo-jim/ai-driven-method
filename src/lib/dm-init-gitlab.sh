#!/usr/bin/env bash
# dm-init-gitlab — GitLab implementations of dm-init.sh's platform functions.
# Sourced by dm-init.sh (resolve_platform), never run directly.
#   remote       glab repo create (namespace = --owner when it is not the current user)
#   protection   protected branches: nobody pushes, merges only through a merge request
#   board        one label per status + an Issue Board list per label
#   wiki         project wiki_access_level=enabled
#   CI           .gitlab/ci/dm-gate.yml, included from .gitlab-ci.yml

GL_STATUSES=("backlog" "ready" "in progress" "test" "shipped")

gl_host() {
  if [ -n "$HOST" ]; then
    printf '%s' "$HOST"
  else
    dm_vcs_gitlab_host
  fi
}

export GITLAB_HOST="${GITLAB_HOST:-$(gl_host)}"

gl_project() {
  printf 'projects/%s' "$(dm_vcs_urlencode "${OWNER}/${REPO_NAME}")"
}

gl_json_field() {
  node -e '
    const v = JSON.parse(require("fs").readFileSync(0, "utf8") || "null");
    const f = process.argv[1].split(".").reduce((o, k) => (o == null ? o : o[k]), v);
    if (f !== undefined && f !== null) process.stdout.write(String(f));
  ' "$1"
}

require_cli() {
  command -v glab >/dev/null || die "glab CLI required (platform gitlab)"
}

resolve_owner_repo() {
  local url parsed
  if [ -z "$OWNER" ] && url="$(git remote get-url origin 2>/dev/null)" \
    && parsed="$(dm_vcs_parse_remote "$url" 2>/dev/null)"; then
    OWNER="$(printf '%s\n' "$parsed" | sed -n 2p)"
    [ -n "$REPO_NAME" ] || REPO_NAME="$(printf '%s\n' "$parsed" | sed -n 3p)"
  fi
  if [ -z "$OWNER" ]; then
    OWNER="$(dm_glab api user 2>/dev/null | gl_json_field username || true)"
  fi
  [ -n "$OWNER" ] || die "cannot resolve owner (pass --owner or authenticate glab)"
  if [ -z "$REPO_NAME" ]; then
    REPO_NAME="$(basename "$(pwd)")"
  fi
}

create_remote_if_needed() {
  if [ "$CREATE_REMOTE" -eq 0 ]; then
    return 0
  fi
  if git remote get-url origin >/dev/null 2>&1; then
    echo "dm-init: origin already set — skip glab repo create"
    return 0
  fi
  confirm "Create GitLab project ${OWNER}/${REPO_NAME} on ${GITLAB_HOST} (${VISIBILITY})?"
  local vis_flag=--private me
  [ "$VISIBILITY" = public ] && vis_flag=--public
  local -a group=()
  me="$(dm_glab api user 2>/dev/null | gl_json_field username || true)"
  [ "$OWNER" = "$me" ] || group=(--group "$OWNER")
  dm_glab repo create "$REPO_NAME" "$vis_flag" --defaultBranch main --remoteName origin \
    ${group[@]+"${group[@]}"} >/dev/null
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://${GITLAB_HOST}/${OWNER}/${REPO_NAME}.git"
  fi
}

enable_wiki() {
  if [ "$CREATE_REMOTE" -eq 0 ]; then
    echo "dm-init: --no-remote — skip wiki enable (no GitLab project)" >&2
    return 0
  fi
  if ! git remote get-url origin >/dev/null 2>&1; then
    warn "no origin remote — wiki not enabled (not inventing fake protection)"
    return 0
  fi
  if ! dm_glab api -X PUT "$(gl_project)" -f wiki_access_level=enabled >/dev/null; then
    warn "failed to enable wiki for ${OWNER}/${REPO_NAME}"
  fi
}

# push: nobody (0). merge: maintainers (40) or developers (30).
gl_protect_branch() {
  local branch="$1" merge_level="$2" proj
  proj="$(gl_project)"
  local -a body=(-f "name=${branch}" -F push_access_level=0 -F "merge_access_level=${merge_level}" -F allow_force_push=false)
  if dm_glab api -X POST "${proj}/protected_branches" "${body[@]}" >/dev/null 2>&1; then
    return 0
  fi
  # Already protected (GitLab protects the default branch on creation, pushable by
  # maintainers): replace those rules with driven's.
  if dm_glab api "${proj}/protected_branches/$(dm_vcs_urlencode "$branch")" >/dev/null 2>&1 \
    && dm_glab api -X DELETE "${proj}/protected_branches/$(dm_vcs_urlencode "$branch")" >/dev/null 2>&1 \
    && dm_glab api -X POST "${proj}/protected_branches" "${body[@]}" >/dev/null 2>&1; then
    return 0
  fi
  local integ; integ="$([ "$USE_DEVELOP" -eq 1 ] && printf 'develop' || printf 'feature/*')"
  warn "branch protection for '${branch}' FAILED — ${branch} is NOT protected. Set it in GitLab (Settings → Repository → Protected branches: push No one, merge via merge request) so $( [ "$branch" = main ] && echo "only $integ can merge into main" || echo "feature/* merge requests are required into $branch" ). Do not assume protection is on."
}

# Fail-closed: a branch that never reached origin leaves the project half-initialized.
push_branches() {
  if ! git remote get-url origin >/dev/null 2>&1; then
    return 0
  fi
  git push -u origin main || die "push of main to origin failed — init incomplete, fix and re-run"
  if [ "$USE_DEVELOP" -eq 1 ]; then
    git push -u origin develop || die "push of develop to origin failed — init incomplete, fix and re-run"
  fi
}

# GitLab cannot restrict which source branch may target a protected branch: the
# dm-gate CI job enforces "main ← develop" and the ticket review gate instead.
apply_rulesets() {
  if [ "$CREATE_REMOTE" -eq 0 ]; then
    echo "dm-init: --no-remote — skip branch protection (no GitLab project)" >&2
    return 0
  fi
  if ! git remote get-url origin >/dev/null 2>&1; then
    warn "no origin remote — branch protection NOT applied"
    return 0
  fi
  # Push first: "push: No one" would refuse the very first push of main/develop.
  push_branches
  if [ "$USE_DEVELOP" -eq 1 ]; then
    gl_protect_branch main 40
    gl_protect_branch develop 30
  else
    gl_protect_branch main 30
  fi
  echo "dm-init: GitLab cannot restrict merge request source branches — the dm-gate CI job checks them; enable 'Pipelines must succeed' to make it blocking." >&2
}

gl_status_color() {
  case "$1" in
    backlog) printf '#8E8E8E' ;;
    ready) printf '#1F75CB' ;;
    "in progress") printf '#E9BE74' ;;
    test) printf '#9E5CE4' ;;
    shipped) printf '#108548' ;;
  esac
}

create_project_and_config() {
  mkdir -p .dm
  if [ -f .dm/config.json ]; then
    echo "dm-init: .dm/config.json exists — skip board create"
    return 0
  fi
  confirm "Create GitLab status labels and Issue Board '${PROJECT_TITLE}' for ${OWNER}/${REPO_NAME}?"
  local proj st name label_id board_id status_json="{}"
  proj="$(gl_project)"

  board_id="$(dm_glab api "${proj}/boards" 2>/dev/null | gl_json_field 0.id || true)"
  if [ -z "$board_id" ]; then
    board_id="$(dm_glab api -X POST "${proj}/boards" -f "name=${PROJECT_TITLE}" 2>/dev/null | gl_json_field id || true)"
  fi
  [ -n "$board_id" ] || warn "no Issue Board could be read or created — statuses still live in the dm:: labels"

  for st in "${GL_STATUSES[@]}"; do
    name="dm::${st}"
    dm_glab api -X POST "${proj}/labels" -f "name=${name}" -f "color=$(gl_status_color "$st")" >/dev/null 2>&1 || true
    label_id="$(dm_glab api "${proj}/labels/$(dm_vcs_urlencode "$name")" | gl_json_field id)" \
      || die "cannot read label '${name}'"
    [ -n "$label_id" ] || die "failed to create label '${name}'"
    if [ -n "$board_id" ]; then
      dm_glab api -X POST "${proj}/boards/${board_id}/lists" -F "label_id=${label_id}" >/dev/null 2>&1 || true
    fi
    status_json="$(node -e '
      const m = JSON.parse(process.argv[1]); m[process.argv[2]] = process.argv[3];
      process.stdout.write(JSON.stringify(m));
    ' "$status_json" "$st" "$name")"
  done

  assert_status_option_ids "$status_json"

  node -e '
    const fs = require("fs");
    const cfg = {
      platform: "gitlab",
      host: process.argv[1],
      owner: process.argv[2],
      repo: process.argv[3],
      board_id: process.argv[4] ? Number(process.argv[4]) : null,
      status_labels: JSON.parse(process.argv[5]),
      develop: process.argv[6] === "1"
    };
    fs.mkdirSync(".dm", { recursive: true });
    fs.writeFileSync(".dm/config.json", JSON.stringify(cfg, null, 2) + "\n");
  ' "$GITLAB_HOST" "$OWNER" "$REPO_NAME" "$board_id" "$status_json" "$USE_DEVELOP"
}

copy_ci_workflow() {
  local src="" cand
  for cand in \
    "$SCRIPT_DIR/../workflows/dm-gate.gitlab-ci.yml" \
    "$SCRIPT_DIR/../../src/workflows/dm-gate.gitlab-ci.yml" \
    "$SCRIPT_DIR/../../workflows/dm-gate.gitlab-ci.yml"
  do
    if [ -f "$cand" ]; then src="$cand"; break; fi
  done
  if [ -z "$src" ]; then
    echo "dm-init: no dm-gate.gitlab-ci.yml template yet — skip CI copy" >&2
    return 0
  fi
  mkdir -p .gitlab/ci
  cp "$src" .gitlab/ci/dm-gate.yml
  if [ ! -f .gitlab-ci.yml ]; then
    printf 'include:\n  - local: .gitlab/ci/dm-gate.yml\n' >.gitlab-ci.yml
  elif ! grep -q '\.gitlab/ci/dm-gate\.yml' .gitlab-ci.yml; then
    warn ".gitlab-ci.yml exists — add 'include: [{ local: .gitlab/ci/dm-gate.yml }]' to run the dm-gate job (its stages: must list test)"
  fi
}
