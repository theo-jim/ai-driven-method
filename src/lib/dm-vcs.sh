#!/usr/bin/env bash
# dm-vcs — code-hosting platform layer: GitHub (gh) or GitLab (glab).
# Platform = .dm/config.json "platform" (github when absent), else detected from
# origin before /dm-init, else github.
# Sourced by the libs; also a CLI so commands never hardcode gh or glab:
#
#   platform                              github | gitlab
#   detect <remote-url>                   github | gitlab (exit 1 when unknown)
#   cli                                   gh | glab
#   auth-check                            exit 0 when the platform CLI is authenticated
#   pr-create <base> <head> <title> <body-file>   prints the PR/MR URL
#   pr-state <ref>                        OPEN | MERGED | CLOSED (ref = branch, number or URL)
#   pr-merge <ref>                        squash-merge now, keep the source branch
#   pr-open-heads <base>                  one "<head-branch>\t<url>" line per open PR/MR into base
#   issue-list <open|closed>              JSON [{number,title,labels:[name]}]
#   issue-body-set <number> <body-file>
set -euo pipefail

dm_vcs_die() { echo "dm-vcs: $*" >&2; return 1; }

dm_vcs_root() {
  if [ -n "${DM_APP_ROOT:-}" ]; then
    printf '%s' "$DM_APP_ROOT"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

# Tolerant read of one top-level string field of .dm/config.json (empty when absent).
dm_vcs_config_field() {
  local cfg
  cfg="$(dm_vcs_root)/.dm/config.json"
  [ -f "$cfg" ] || return 0
  node -e '
    try {
      const cfg = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      const v = cfg[process.argv[2]];
      if (v !== undefined && v !== null) process.stdout.write(String(v));
    } catch (e) {}
  ' "$cfg" "$1"
}

# <remote-url> → three lines: host, owner (namespace, may contain /), repo.
dm_vcs_parse_remote() {
  node -e '
    const u = process.argv[1].trim();
    let host = "", path = "";
    let m = u.match(/^[a-z+]+:\/\/(?:[^@/]+@)?([^/:]+)(?::\d+)?\/(.+)$/i);
    if (m) { host = m[1]; path = m[2]; }
    else if ((m = u.match(/^(?:[^@]+@)?([^:/]+):(.+)$/))) { host = m[1]; path = m[2]; }
    path = path.replace(/\.git$/, "").replace(/\/+$/, "");
    const parts = path.split("/").filter(Boolean);
    if (!host || parts.length < 2) process.exit(1);
    console.log(host.toLowerCase());
    console.log(parts.slice(0, -1).join("/"));
    console.log(parts[parts.length - 1]);
  ' "$1"
}

dm_vcs_detect() {
  local host
  host="$(dm_vcs_parse_remote "$1" 2>/dev/null | sed -n 1p)" || true
  case "$host" in
    github.com|*.github.com) printf 'github' ;;
    gitlab.com|*gitlab*) printf 'gitlab' ;;
    *) return 1 ;;
  esac
}

# A .dm/config.json without "platform" predates GitLab support: github.
dm_vcs_platform() {
  local p url
  if [ -f "$(dm_vcs_root)/.dm/config.json" ]; then
    p="$(dm_vcs_config_field platform)"
    p="${p:-github}"
  elif url="$(git remote get-url origin 2>/dev/null)"; then
    p="$(dm_vcs_detect "$url" || true)"
  fi
  case "${p:-github}" in
    github|gitlab) printf '%s' "${p:-github}" ;;
    *) dm_vcs_die "unknown platform '$p' in .dm/config.json (github|gitlab)" ;;
  esac
}

dm_vcs_cli() {
  case "$(dm_vcs_platform)" in
    gitlab) printf 'glab' ;;
    *) printf 'gh' ;;
  esac
}

# GitLab host: config "host", else origin's host, else gitlab.com.
dm_vcs_gitlab_host() {
  local h url
  h="$(dm_vcs_config_field host)"
  if [ -z "$h" ] && url="$(git remote get-url origin 2>/dev/null)"; then
    h="$(dm_vcs_parse_remote "$url" 2>/dev/null | sed -n 1p || true)"
  fi
  printf '%s' "${h:-gitlab.com}"
}

# glab reads GITLAB_HOST for every command; point it at the project's instance.
dm_glab() {
  GITLAB_HOST="${GITLAB_HOST:-$(dm_vcs_gitlab_host)}" glab "$@"
}

# owner/repo from config, else from origin.
dm_vcs_project_path() {
  local o r url parsed
  o="$(dm_vcs_config_field owner)"
  r="$(dm_vcs_config_field repo)"
  if [ -z "$o" ] || [ -z "$r" ]; then
    url="$(git remote get-url origin 2>/dev/null)" || dm_vcs_die "no .dm/config.json owner/repo and no origin remote" || return 1
    parsed="$(dm_vcs_parse_remote "$url")" || dm_vcs_die "cannot parse origin $url" || return 1
    o="$(printf '%s\n' "$parsed" | sed -n 2p)"
    r="$(printf '%s\n' "$parsed" | sed -n 3p)"
  fi
  printf '%s/%s' "$o" "$r"
}

dm_vcs_urlencode() {
  node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$1"
}

# "projects/<url-encoded owner/repo>" — the GitLab REST prefix for this project.
dm_vcs_gitlab_project() {
  local p
  p="$(dm_vcs_project_path)" || return 1
  printf 'projects/%s' "$(dm_vcs_urlencode "$p")"
}

dm_vcs_auth_check() {
  case "$(dm_vcs_platform)" in
    gitlab) dm_glab auth status >/dev/null 2>&1 ;;
    *) gh auth status >/dev/null 2>&1 ;;
  esac
}

dm_vcs_pr_create() {
  local base="$1" head="$2" title="$3" body="$4" out url
  [ -f "$body" ] || dm_vcs_die "body file missing: $body" || return 1
  case "$(dm_vcs_platform)" in
    gitlab)
      out="$(dm_glab mr create --target-branch "$base" --source-branch "$head" \
        --title "$title" --description-file "$body" --yes)"
      url="$(printf '%s\n' "$out" | grep -Eo 'https?://[^[:space:]]+/-/merge_requests/[0-9]+' | tail -1 || true)"
      [ -n "$url" ] || dm_vcs_die "glab mr create printed no merge request URL" || return 1
      printf '%s\n' "$url"
      ;;
    *) gh pr create --base "$base" --head "$head" --title "$title" --body-file "$body" ;;
  esac
}

dm_vcs_pr_state() {
  local ref="$1"
  case "$(dm_vcs_platform)" in
    gitlab)
      dm_glab mr view "$ref" -F json | node -e '
        const mr = JSON.parse(require("fs").readFileSync(0, "utf8"));
        const s = { opened: "OPEN", merged: "MERGED", closed: "CLOSED", locked: "CLOSED" }[mr.state];
        if (!s) { console.error("dm-vcs: unknown merge request state " + JSON.stringify(mr.state)); process.exit(1); }
        console.log(s);
      '
      ;;
    *) gh pr view "$ref" --json state --jq .state ;;
  esac
}

dm_vcs_pr_merge() {
  local ref="$1"
  case "$(dm_vcs_platform)" in
    # --auto-merge defaults to true in glab: it would only schedule the merge.
    gitlab) dm_glab mr merge "$ref" --squash --auto-merge=false --yes ;;
    *) gh pr merge "$ref" --squash --delete-branch=false ;;
  esac
}

dm_vcs_pr_open_heads() {
  local base="$1"
  case "$(dm_vcs_platform)" in
    gitlab)
      dm_glab mr list --target-branch "$base" -P 100 -F json | node -e '
        for (const mr of JSON.parse(require("fs").readFileSync(0, "utf8") || "[]"))
          console.log(mr.source_branch + "\t" + mr.web_url);
      '
      ;;
    *) gh pr list --base "$base" --state open --json url,headRefName --jq '.[] | "\(.headRefName)\t\(.url)"' ;;
  esac
}

dm_vcs_issue_list() {
  local state="$1"
  case "$state" in open|closed) ;; *) dm_vcs_die "issue-list needs open|closed" || return 1 ;; esac
  case "$(dm_vcs_platform)" in
    gitlab)
      local gstate=opened proj
      [ "$state" = closed ] && gstate=closed
      proj="$(dm_vcs_gitlab_project)" || return 1
      dm_glab api "${proj}/issues?state=${gstate}&per_page=100" --paginate --output ndjson | node -e '
        const out = require("fs").readFileSync(0, "utf8").split("\n").filter(Boolean)
          .map((l) => JSON.parse(l))
          .map((i) => ({ number: i.iid, title: i.title, labels: i.labels || [] }));
        process.stdout.write(JSON.stringify(out));
      '
      ;;
    *)
      gh issue list --state "$state" --limit 200 --json number,title,labels | node -e '
        const out = JSON.parse(require("fs").readFileSync(0, "utf8"))
          .map((i) => ({ number: i.number, title: i.title, labels: (i.labels || []).map((l) => l.name) }));
        process.stdout.write(JSON.stringify(out));
      '
      ;;
  esac
}

dm_vcs_issue_body_set() {
  local number="$1" body="$2"
  [ -f "$body" ] || dm_vcs_die "body file missing: $body" || return 1
  case "$(dm_vcs_platform)" in
    gitlab) dm_glab issue update "$number" --description-file "$body" >/dev/null ;;
    *) gh issue edit "$number" --body-file "$body" >/dev/null ;;
  esac
}

dm_vcs_main() {
  local cmd="${1:-}"
  [ $# -eq 0 ] || shift
  case "$cmd" in
    platform) dm_vcs_platform; printf '\n' ;;
    detect) dm_vcs_detect "${1:?remote url required}"; printf '\n' ;;
    cli) dm_vcs_cli; printf '\n' ;;
    auth-check) dm_vcs_auth_check ;;
    pr-create)
      [ $# -eq 4 ] || dm_vcs_die "usage: pr-create <base> <head> <title> <body-file>" || return 1
      dm_vcs_pr_create "$@"
      ;;
    pr-state) dm_vcs_pr_state "${1:?ref required}" ;;
    pr-merge) dm_vcs_pr_merge "${1:?ref required}" ;;
    pr-open-heads) dm_vcs_pr_open_heads "${1:?base branch required}" ;;
    issue-list) dm_vcs_issue_list "${1:?open|closed required}" ;;
    issue-body-set)
      [ $# -eq 2 ] || dm_vcs_die "usage: issue-body-set <number> <body-file>" || return 1
      dm_vcs_issue_body_set "$@"
      ;;
    *)
      echo "usage: dm-vcs.sh platform|detect|cli|auth-check|pr-create|pr-state|pr-merge|pr-open-heads|issue-list|issue-body-set ..." >&2
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]:-}" = "$0" ]; then
  dm_vcs_main "$@"
fi
