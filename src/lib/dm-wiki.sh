#!/usr/bin/env bash
# dm-wiki — publish product docs to the GitHub or GitLab project wiki on release.
# Usage: dm-wiki.sh publish <app-root> <version> <story-id...>
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck source=dm-config.sh
source "$SCRIPT_DIR/dm-config.sh"

die() { echo "dm-wiki: $*" >&2; exit 1; }

cmd_publish() {
  local app_root="${1:-}" version="${2:-}"
  shift 2 || true
  [ -n "$app_root" ] && [ -n "$version" ] || die "usage: publish <app-root> <version> <story-id...>"
  [ "$#" -ge 1 ] || die "publish needs at least one story-id"

  DM_APP_ROOT="$app_root"
  dm_config_load "$app_root"

  local owner="$DM_OWNER" repo="$DM_REPO"
  local wiki_url token="" home="Home.md"
  if [ "$DM_PLATFORM" = gitlab ]; then
    # GitLab serves the wiki front page from home.md and takes a token as oauth2's password.
    wiki_url="https://${DM_HOST}/${owner}/${repo}.wiki.git"
    home="home.md"
    export DM_WIKI_USER=oauth2
    if [ -n "${GITLAB_TOKEN:-}" ]; then
      token="$GITLAB_TOKEN"
    elif [ -n "${GL_TOKEN:-}" ]; then
      token="$GL_TOKEN"
    elif command -v glab >/dev/null; then
      token="$(glab config get token --host "$DM_HOST" 2>/dev/null || true)"
    fi
  else
    wiki_url="https://github.com/${owner}/${repo}.wiki.git"
    export DM_WIKI_USER=x-access-token
    if [ -n "${GH_TOKEN:-}" ]; then
      token="$GH_TOKEN"
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
      token="$GITHUB_TOKEN"
    elif command -v gh >/dev/null; then
      token="$(gh auth token 2>/dev/null || true)"
    fi
    if command -v gh >/dev/null; then
      gh auth setup-git >/dev/null 2>&1 || true
    fi
  fi
  # The token never goes into the URL: it would show up in `ps` while git runs, and
  # `git remote add` would persist it in .git/config. Feed it through a credential
  # helper that reads it from the environment instead.
  local clone_url="$wiki_url"
  local -a git_auth=()
  if [ -n "$token" ]; then
    export DM_WIKI_TOKEN="$token"
    # An empty value first RESETS the helper list: `-c credential.helper=X` only
    # appends, so without this an ambient helper (keychain, gh) would answer first.
    git_auth=(-c "credential.helper=" \
              -c "credential.helper=!f(){ echo \"username=\$DM_WIKI_USER\"; echo \"password=\$DM_WIKI_TOKEN\"; }; f")
  fi
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/dm-wiki.XXXXXX")"
  # Expanded now: the EXIT trap runs after cmd_publish returns, when the local
  # $tmp no longer exists and `set -u` would fail the whole publish.
  trap "rm -rf '$tmp'" EXIT

  # Clone or init wiki (authenticated via the platform token)
  if ! git ${git_auth[@]+"${git_auth[@]}"} clone --depth 1 "$clone_url" "$tmp/wiki" 2>/dev/null; then
    mkdir -p "$tmp/wiki"
    (
      cd "$tmp/wiki"
      git init -b master
      git remote add origin "$clone_url"
      if [ -n "${DM_WIKI_TOKEN:-}" ]; then
        git config --replace-all credential.helper ""
        git config --add credential.helper \
          '!f(){ echo "username=$DM_WIKI_USER"; echo "password=$DM_WIKI_TOKEN"; }; f'
      fi
      printf '# %s\n' "$repo" >"$home"
      git add "$home"
      git -c user.email="${GIT_AUTHOR_EMAIL:-dm-wiki@localhost}" \
          -c user.name="${GIT_AUTHOR_NAME:-dm-wiki}" \
          commit -m "chore: init wiki" || true
    )
  fi

  local id src dest
  local -a shipped=()
  for id in "$@"; do
    src="$app_root/docs/product/${id}.md"
    [ -f "$src" ] || die "missing product doc: $src"
    dest="$tmp/wiki/${id}.md"
    cp "$src" "$dest"
    shipped+=("$id")
  done

  # Rebuild Home.md: keep existing shipped pages listed + version
  node -e '
    const fs = require("fs");
    const path = require("path");
    const wikiDir = process.argv[1];
    const version = process.argv[2];
    const home = process.argv[3];
    const newly = process.argv.slice(4);
    const files = fs.readdirSync(wikiDir).filter((f) => f.endsWith(".md") && f !== home);
    const ids = files.map((f) => f.replace(/\.md$/, "")).sort();
    for (const id of newly) if (!ids.includes(id)) ids.push(id);
    ids.sort();
    let body = `# Product wiki\n\n**Version:** ${version}\n\n## Shipped stories\n\n`;
    for (const id of ids) body += `- [${id}](${id})\n`;
    fs.writeFileSync(path.join(wikiDir, home), body);
  ' "$tmp/wiki" "$version" "$home" "${shipped[@]}"

  (
    cd "$tmp/wiki"
    git add -A
    if git diff --cached --quiet; then
      echo "dm-wiki: nothing to commit"
      exit 0
    fi
    git -c user.email="${GIT_AUTHOR_EMAIL:-dm-wiki@localhost}" \
        -c user.name="${GIT_AUTHOR_NAME:-dm-wiki}" \
        commit -m "docs: publish product wiki for v${version}"
    git ${git_auth[@]+"${git_auth[@]}"} push -u origin HEAD:master 2>/dev/null \
      || git ${git_auth[@]+"${git_auth[@]}"} push -u origin HEAD:main
  )
  echo "dm-wiki: published v${version} (${#shipped[@]} stories)"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    publish) shift; cmd_publish "$@" ;;
    *) die "usage: dm-wiki.sh publish <app-root> <version> <story-id...>" ;;
  esac
}

main "$@"
