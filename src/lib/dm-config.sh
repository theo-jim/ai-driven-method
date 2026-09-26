#!/usr/bin/env bash
# dm-config — load .dm/config.json (app repo) into shell variables.
# Keys (snake_case locked): platform (github|gitlab, default github), owner, repo.
# github: project_id, project_number, status_field_id,
#         status_option_ids{backlog,ready,in progress,test,shipped}.
# gitlab: host, board_id, status_labels{backlog,ready,in progress,test,shipped}.
# Also accepts camelCase aliases from older drafts (projectId, statusFieldId, status).
set -euo pipefail

dm_config_path() {
  local root="${DM_APP_ROOT:-${1:-.}}"
  printf '%s' "$root/.dm/config.json"
}

dm_config_load() {
  local root="${1:-${DM_APP_ROOT:-.}}"
  local cfg
  cfg="$(dm_config_path "$root")"
  if [ ! -f "$cfg" ]; then
    echo "dm-config: missing $cfg — run /dm-init first." >&2
    return 1
  fi
  # Export DM_PLATFORM DM_HOST DM_OWNER DM_REPO DM_PROJECT_ID DM_PROJECT_NUMBER
  # DM_STATUS_FIELD_ID DM_BOARD_ID and DM_STATUS_<slug> for each status (spaces →
  # underscores): a Project V2 option id on github, a label name on gitlab.
  eval "$(node -e '
    const fs = require("fs");
    const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const platform = cfg.platform || "github";
    const owner = cfg.owner;
    const repo = cfg.repo;
    const projectId = cfg.project_id || cfg.projectId || "";
    const projectNumber = cfg.project_number || cfg.projectNumber || "";
    const fieldId = cfg.status_field_id || cfg.statusFieldId || "";
    const q = (s) => JSON.stringify(String(s ?? ""));
    let status;
    if (platform === "gitlab") {
      status = cfg.status_labels || {};
      if (!owner || !repo || !Object.keys(status).length) {
        console.error("dm-config: owner, repo, status_labels required (platform gitlab)");
        process.exit(1);
      }
    } else if (platform === "github") {
      status = cfg.status_option_ids || cfg.status || {};
      if (!owner || !repo || !projectId || !fieldId) {
        console.error("dm-config: owner, repo, project_id, status_field_id required");
        process.exit(1);
      }
    } else {
      console.error("dm-config: unknown platform "+JSON.stringify(platform)+" (github|gitlab)");
      process.exit(1);
    }
    console.log("export DM_PLATFORM="+q(platform));
    console.log("export DM_HOST="+q(cfg.host || (platform === "gitlab" ? "gitlab.com" : "github.com")));
    console.log("export DM_BOARD_ID="+q(cfg.board_id || ""));
    console.log("export DM_OWNER="+q(owner));
    console.log("export DM_REPO="+q(repo));
    console.log("export DM_PROJECT_ID="+q(projectId));
    console.log("export DM_PROJECT_NUMBER="+q(projectNumber));
    console.log("export DM_STATUS_FIELD_ID="+q(fieldId));
    for (const [k, v] of Object.entries(status)) {
      const slug = k.replace(/[^a-zA-Z0-9]+/g, "_").replace(/^_|_$/g, "").toUpperCase();
      console.log("export DM_STATUS_"+slug+"="+q(v));
    }
    console.log("export DM_STATUS_JSON="+q(JSON.stringify(status)));
  ' "$cfg")"
}

dm_config_status_option_id() {
  local status="$1"
  node -e '
    const map = JSON.parse(process.env.DM_STATUS_JSON || "{}");
    const s = process.argv[1];
    if (!(s in map)) {
      console.error("dm-config: unknown status "+JSON.stringify(s));
      process.exit(1);
    }
    process.stdout.write(map[s]);
  ' "$status"
}

dm_config_repo() {
  printf '%s/%s' "${DM_OWNER:?}" "${DM_REPO:?}"
}
