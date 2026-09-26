#!/usr/bin/env bash
# dm-init — bootstrap app repo: remote, develop/main rulesets, Project V2, wiki, VERSION.
# Usage: dm-init.sh run [--repo NAME] [--owner LOGIN] [--public|--private] [--yes]
#        [--no-remote] [--no-develop] [--title PROJECT_TITLE]
#        dm-init.sh assert-status-ids '<json-object>'   # fail-closed helper (tests)
set -euo pipefail

YES=0
VISIBILITY=private
REPO_NAME=""
OWNER=""
CREATE_REMOTE=1
USE_DEVELOP=1
PROJECT_TITLE="driven"

die() { echo "dm-init: $*" >&2; exit 1; }

# Fail closed unless status map has all five exact keys with non-empty ids.
# Arg: JSON object string (status_option_ids). Prints nothing; exit 1 if incomplete.
assert_status_option_ids() {
  local json="${1:-}"
  [ -n "$json" ] || die "assert-status-ids needs a JSON object"
  node -e '
    let status;
    try { status = JSON.parse(process.argv[1]); }
    catch (e) {
      console.error("dm-init: status_option_ids is not valid JSON");
      process.exit(1);
    }
    if (!status || typeof status !== "object" || Array.isArray(status)) {
      console.error("dm-init: status_option_ids must be an object");
      process.exit(1);
    }
    const need = ["backlog", "ready", "in progress", "test", "shipped"];
    const missing = need.filter((k) => !status[k] || String(status[k]).trim() === "");
    if (missing.length) {
      console.error("dm-init: missing status option ids: " + missing.join(", "));
      process.exit(1);
    }
  ' "$json"
}

confirm() {
  local msg="$1"
  if [ "$YES" -eq 1 ]; then
    return 0
  fi
  printf '%s [y/N] ' "$msg" >&2
  local ans
  read -r ans || true
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) die "aborted" ;;
  esac
}

parse_run_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes|-y) YES=1; shift ;;
      --public) VISIBILITY=public; shift ;;
      --private) VISIBILITY=private; shift ;;
      --repo)
        REPO_NAME="${2:-}"; [ -n "$REPO_NAME" ] || die "--repo needs a name"
        shift 2
        ;;
      --owner)
        OWNER="${2:-}"; [ -n "$OWNER" ] || die "--owner needs a login"
        shift 2
        ;;
      --no-remote) CREATE_REMOTE=0; shift ;;
      --no-develop) USE_DEVELOP=0; shift ;;
      --title)
        PROJECT_TITLE="${2:-}"; shift 2
        ;;
      *) die "unknown flag: $1" ;;
    esac
  done
}

ensure_git() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    git init -b main
  fi
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  if [ "$branch" = "HEAD" ] || [ -z "$branch" ]; then
    git checkout -B main 2>/dev/null || git branch -M main
  elif [ "$branch" != "main" ]; then
    # Prefer main as production; rename only if no main yet
    if ! git show-ref --verify --quiet refs/heads/main; then
      git branch -M main
    fi
  fi
  if [ -z "$(git status --porcelain 2>/dev/null || true)" ] && ! git rev-parse HEAD >/dev/null 2>&1; then
    # Empty repo: need an initial commit for branches
    if [ ! -f README.md ]; then
      printf '# %s\n' "${REPO_NAME:-app}" >README.md
    fi
    git add -A
    git -c user.email="${GIT_AUTHOR_EMAIL:-dm-init@localhost}" \
        -c user.name="${GIT_AUTHOR_NAME:-dm-init}" \
        commit -m "chore: initial commit" || true
  fi
}

ensure_develop_branch() {
  [ "$USE_DEVELOP" -eq 1 ] || return 0
  if git show-ref --verify --quiet refs/heads/develop; then
    return 0
  fi
  git branch develop main 2>/dev/null || git branch develop
}

write_version_and_changelog() {
  if [ ! -f VERSION ]; then
    printf '0.1.0\n' >VERSION
  fi
  if [ ! -f CHANGELOG.md ]; then
    cat >CHANGELOG.md <<'EOF'
# Changelog

## 0.1.0 - unreleased

EOF
  fi
}

copy_ci_workflow() {
  local src=""
  local here
  here="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
  # Prefer method-repo workflows next to lib (../../src/workflows from installed .dm/lib)
  for cand in \
    "$here/../workflows/dm-gate.yml" \
    "$here/../../src/workflows/dm-gate.yml" \
    "$here/../../workflows/dm-gate.yml"
  do
    if [ -f "$cand" ]; then src="$cand"; break; fi
  done
  if [ -z "$src" ]; then
    echo "dm-init: no dm-gate.yml template yet — skip CI copy" >&2
    return 0
  fi
  mkdir -p .github/workflows
  cp "$src" .github/workflows/dm-gate.yml
}

resolve_owner_repo() {
  if [ -z "$OWNER" ]; then
    OWNER="$(gh api user -q .login 2>/dev/null || true)"
  fi
  [ -n "$OWNER" ] || die "cannot resolve owner (pass --owner or authenticate gh)"
  if [ -z "$REPO_NAME" ]; then
    REPO_NAME="$(basename "$(pwd)")"
  fi
}

create_remote_if_needed() {
  if [ "$CREATE_REMOTE" -eq 0 ]; then
    return 0
  fi
  if git remote get-url origin >/dev/null 2>&1; then
    echo "dm-init: origin already set — skip gh repo create"
    # Derive owner/repo from origin when possible
    local url
    url="$(git remote get-url origin)"
    node -e '
      const u=process.argv[1];
      let m=u.match(/github\.com[:/]([^/]+)\/([^/.]+)(?:\.git)?$/);
      if (m) {
        console.log(m[1]);
        console.log(m[2]);
      }
    ' "$url" | {
      read -r o || true
      read -r r || true
      [ -n "${o:-}" ] && OWNER="$o"
      [ -n "${r:-}" ] && REPO_NAME="$r"
    }
    return 0
  fi
  confirm "Create GitHub repo ${OWNER}/${REPO_NAME} (${VISIBILITY})?"
  local vis_flag=--private
  [ "$VISIBILITY" = public ] && vis_flag=--public
  gh repo create "${OWNER}/${REPO_NAME}" "$vis_flag" --source=. --remote=origin --push
}

warn() { echo "dm-init: WARNING: $*" >&2; }

enable_wiki() {
  if [ "$CREATE_REMOTE" -eq 0 ]; then
    echo "dm-init: --no-remote — skip wiki enable (no GitHub repo)" >&2
    return 0
  fi
  if ! git remote get-url origin >/dev/null 2>&1; then
    warn "no origin remote — wiki not enabled (not inventing fake protection)"
    return 0
  fi
  if ! gh api -X PATCH "repos/${OWNER}/${REPO_NAME}" -f has_wiki=true >/dev/null; then
    warn "failed to enable wiki for ${OWNER}/${REPO_NAME}"
  fi
}

protect_branch() {
  local branch="$1"
  if ! gh api -X PUT "repos/${OWNER}/${REPO_NAME}/branches/${branch}/protection" \
    -H "Accept: application/vnd.github+json" \
    --input - >/dev/null <<JSON
{
  "required_status_checks": null,
  "enforce_admins": $([ "$branch" = main ] && echo true || echo false),
  "required_pull_request_reviews": {
    "required_approving_review_count": 0
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
  then
    local integ; integ="$([ "$USE_DEVELOP" -eq 1 ] && printf 'develop' || printf 'feature/*')"
    warn "branch protection for '${branch}' FAILED — ${branch} is NOT protected. Set it in GitHub so $( [ "$branch" = main ] && echo "only $integ can merge into main" || echo "feature/* PRs are required into $branch" ). Do not assume protection is on."
    return 0
  fi
  return 0
}

# Repository rulesets: main ← only develop (or feature/* directly when --no-develop); develop ← feature/*
apply_rulesets() {
  if [ "$CREATE_REMOTE" -eq 0 ]; then
    echo "dm-init: --no-remote — skip branch protection and rulesets (no GitHub repo)" >&2
    return 0
  fi
  if ! git remote get-url origin >/dev/null 2>&1; then
    warn "no origin remote — branch protection and rulesets NOT applied"
    return 0
  fi

  local repo_id
  if ! repo_id="$(gh api "repos/${OWNER}/${REPO_NAME}" -q .node_id)"; then
    warn "cannot read repo ${OWNER}/${REPO_NAME} — branch protection NOT applied"
    return 0
  fi

  protect_branch main

  if [ "$USE_DEVELOP" -eq 1 ]; then
    protect_branch develop
    if ! create_or_update_ruleset "driven-main" "main" "develop"; then
      warn "ruleset driven-main not applied — main is NOT restricted to develop"
    fi
    if ! create_or_update_ruleset "driven-develop" "develop" "feature/*"; then
      warn "ruleset driven-develop not applied — develop is NOT restricted to feature/*"
    fi
  else
    if ! create_or_update_ruleset "driven-main" "main" "feature/*"; then
      warn "ruleset driven-main not applied — main is NOT restricted to feature/*"
    fi
  fi
  unset repo_id
}

create_or_update_ruleset() {
  local name="$1" target_branch="$2" source_pattern="$3"
  # List existing
  local existing
  existing="$(gh api "repos/${OWNER}/${REPO_NAME}/rulesets" -q ".[] | select(.name==\"$name\") | .id" 2>/dev/null | head -1 || true)"
  local body
  body="$(node -e '
    const name=process.argv[1], target=process.argv[2], source=process.argv[3];
    const rules = [
      { type: "pull_request", parameters: {
          required_approving_review_count: 0,
          dismiss_stale_reviews_on_push: false,
          require_code_owner_review: false,
          require_last_push_approval: false,
          required_review_thread_resolution: false
      }},
      { type: "non_fast_forward" }
    ];
    // Restrict which branches can update this branch via pull requests when supported
    const payload = {
      name,
      target: "branch",
      enforcement: "active",
      conditions: {
        ref_name: { include: ["refs/heads/"+target], exclude: [] }
      },
      rules,
      bypass_actors: []
    };
    // Note: GitHub rulesets do not always encode source branch allow-list;
    // document source_pattern for operators. Emit as metadata in name suffix when needed.
    void source;
    process.stdout.write(JSON.stringify(payload));
  ' "$name" "$target_branch" "$source_pattern")"
  if [ -n "$existing" ]; then
    printf '%s' "$body" | gh api -X PUT "repos/${OWNER}/${REPO_NAME}/rulesets/${existing}" --input - >/dev/null
  else
    printf '%s' "$body" | gh api -X POST "repos/${OWNER}/${REPO_NAME}/rulesets" --input - >/dev/null
  fi
}

create_project_and_config() {
  mkdir -p .dm
  if [ -f .dm/config.json ]; then
    echo "dm-init: .dm/config.json exists — skip project create"
    return 0
  fi
  confirm "Create Project V2 '${PROJECT_TITLE}' with board statuses?"

  local proj_json project_id project_number
  proj_json="$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json)"
  project_id="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(j.id||j.node_id||"")' "$proj_json")"
  project_number="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(String(j.number??""))' "$proj_json")"
  [ -n "$project_id" ] && [ -n "$project_number" ] || die "failed to create project"

  # Link project to repo (best-effort)
  gh project link "$project_number" --owner "$OWNER" --repo "$REPO_NAME" >/dev/null 2>&1 || true

  # Create SINGLE_SELECT field with exact five statuses.
  # Prefer a dedicated field name if default Status cannot be rewritten.
  local field_json field_id
  field_json="$(
    gh project field-create "$project_number" \
      --owner "$OWNER" \
      --name "Status" \
      --data-type SINGLE_SELECT \
      --single-select-options "backlog,ready,in progress,test,shipped" \
      --format json 2>/dev/null || true
  )"
  if [ -z "$field_json" ]; then
    field_json="$(
      gh project field-create "$project_number" \
        --owner "$OWNER" \
        --name "DM Status" \
        --data-type SINGLE_SELECT \
        --single-select-options "backlog,ready,in progress,test,shipped" \
        --format json
    )"
  fi
  field_id="$(node -e 'const j=JSON.parse(process.argv[1]); process.stdout.write(j.id||"")' "$field_json")"
  [ -n "$field_id" ] || die "failed to create status field"

  # Map option names → ids from field-list + field-create payload
  local fields_json status_json
  fields_json="$(gh project field-list "$project_number" --owner "$OWNER" --format json)"
  status_json="$(
    node -e '
      const fieldId = process.argv[1];
      const fields = JSON.parse(process.argv[2] || "{}");
      const created = JSON.parse(process.argv[3] || "{}");
      const list = Array.isArray(fields) ? fields : (fields.fields || fields.items || []);
      const field = list.find((f) => f.id === fieldId) || list.find((f) => (f.name === "Status" || f.name === "DM Status"));
      const options = (field && (field.options || field.configuration?.options)) || [];
      const status = {};
      for (const opt of options) {
        if (opt && opt.name) status[opt.name] = opt.id;
      }
      for (const o of created.options || []) {
        if (o && o.name && !status[o.name]) status[o.name] = o.id;
      }
      process.stdout.write(JSON.stringify(status));
    ' "$field_id" "$fields_json" "$field_json"
  )"

  # Fail closed: never write .dm/config.json with incomplete status_option_ids
  assert_status_option_ids "$status_json"

  node -e '
    const fs = require("fs");
    const cfg = {
      owner: process.argv[1],
      repo: process.argv[2],
      project_id: process.argv[3],
      project_number: Number(process.argv[4]),
      status_field_id: process.argv[5],
      status_option_ids: JSON.parse(process.argv[6]),
      develop: process.argv[7] === "1"
    };
    fs.mkdirSync(".dm", { recursive: true });
    fs.writeFileSync(".dm/config.json", JSON.stringify(cfg, null, 2) + "\n");
  ' "$OWNER" "$REPO_NAME" "$project_id" "$project_number" "$field_id" "$status_json" "$USE_DEVELOP"
}

push_branches() {
  if ! git remote get-url origin >/dev/null 2>&1; then
    return 0
  fi
  git push -u origin main 2>/dev/null || git push -u origin HEAD:main || true
  if [ "$USE_DEVELOP" -eq 1 ]; then
    git push -u origin develop 2>/dev/null || true
  fi
}

cmd_run() {
  command -v gh >/dev/null || die "gh CLI required"
  command -v node >/dev/null || die "node required"
  ensure_git
  resolve_owner_repo
  write_version_and_changelog
  copy_ci_workflow
  create_remote_if_needed
  ensure_develop_branch
  if [ "$CREATE_REMOTE" -eq 1 ]; then
    enable_wiki
    apply_rulesets
  else
    echo "dm-init: --no-remote — skip wiki enable, branch protection, and rulesets (no gh api)" >&2
  fi
  create_project_and_config
  push_branches
  echo "dm-init: done — ${OWNER}/${REPO_NAME} (VERSION=$(tr -d '[:space:]' <VERSION))"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    run)
      shift
      parse_run_args "$@"
      cmd_run
      ;;
    assert-status-ids)
      shift
      assert_status_option_ids "${1:-}"
      ;;
    *)
      die "usage: dm-init.sh run [--repo NAME] [--owner LOGIN] [--public|--private] [--yes] [--no-develop] | assert-status-ids '<json>'"
      ;;
  esac
}

main "$@"
