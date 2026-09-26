#!/usr/bin/env bash
set -euo pipefail

# driven installer
#
# Usage :
#   ./install.sh                       Projet (défaut), cible Claude Code
#   ./install.sh --target codex        Projet, cible Codex (.codex/skills + AGENTS.md)
#   ./install.sh --target grok         Projet, cible Grok (.grok/commands + skills + agents)
#   ./install.sh --target all          Projet, Claude + Codex + Grok
#   ./install.sh --global              Global Claude (~/.claude) — commandes dans tous les repos
#   ./install.sh --global --target codex   Global Codex (~/.codex/skills)
#   ./install.sh --global --target grok    Global Grok (~/.grok)
#   ./install.sh --global --target all      Global Claude + Codex + Grok
#   ./install.sh init [--target …]     Pose templates + rules dans le projet (après un global)
#   ./install.sh update [--target …]   Met à jour le tooling + templates (préserve tes modifs)
#   ./install.sh uninstall [--target …]  Retire ce que l'install a posé (manifeste), rien d'autre
#   --profile full|framing|delivery    Sous-ensemble de commandes (défaut : full)
#   --dry-run                          Avec uninstall : liste sans supprimer
#   --hooks                            Pose les git hooks d'enforcement (opt-in, réversible)
#   --force                            Écrase aussi les templates modifiés localement
#
# Sans argument sur un terminal, l'installeur demande cible et profil. Avec des
# flags, ou hors terminal (CI, curl | bash redirigé), il ne demande rien.
#
# Deux portées, pour chaque cible : projet (dans le repo courant) ou global (--global).
#
# curl -fsSL https://raw.githubusercontent.com/BarthGve/ai-driven-method/main/install.sh | bash

REPO="https://github.com/BarthGve/ai-driven-method.git"

# --- Résolution du payload (src/) : fichiers locaux, sinon clone (cas curl|bash) ---
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "${SELF_DIR:-}" ] && [ -f "$SELF_DIR/src/commands/dm-prd.md" ]; then
  SRC="$SELF_DIR/src"
  PAYLOAD_ROOT="$SELF_DIR"
else
  TMP="$(mktemp -d)"
  echo "→ Récupération de driven…"
  git clone --depth 1 "$REPO" "$TMP" >/dev/null 2>&1
  SRC="$TMP/src"
  PAYLOAD_ROOT="$TMP"
fi

# Version sémantique du payload. Le SHA ne reste qu'en secours : il ne dit à personne
# s'il est en retard, et un rapport de bug qui cite « 8836bc0 » ne situe rien.
if [ -f "$PAYLOAD_ROOT/VERSION" ]; then
  VERSION="$(tr -d '[:space:]' < "$PAYLOAD_ROOT/VERSION")"
else
  VERSION="$(git -C "$PAYLOAD_ROOT" rev-parse --short HEAD 2>/dev/null || date +%Y-%m-%d)"
fi
CACHE="$HOME/.claude/ai-driven-method"
ORIG="./.driven/templates.orig"   # baseline templates (tool-neutral), for local-edit detection

# --- Arguments : mode + --target + --hooks + --force ---
FORCE=0; HOOKS=0; TARGET="claude"; MODE=""; PROFILE="full"; DRY_RUN=0; EXPLICIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force)   FORCE=1 ;;
    --hooks)      HOOKS=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    --yes|-y)     EXPLICIT=1 ;;
    --target)     TARGET="${2:-}"; EXPLICIT=1; shift ;;
    --target=*)   TARGET="${1#--target=}"; EXPLICIT=1 ;;
    --profile)    PROFILE="${2:-}"; EXPLICIT=1; shift ;;
    --profile=*)  PROFILE="${1#--profile=}"; EXPLICIT=1 ;;
    *)            MODE="$1" ;;
  esac
  shift
done

# --- Profils : table plate lue sans parser (le chemin Claude reste sans Node) ---
PROFILE_CMDS="*"
load_profile() {
  local want="$1" line
  [ -f "$SRC/profiles.txt" ] || { PROFILE_CMDS="*"; return 0; }
  while IFS= read -r line; do
    case "$line" in
      \#*|"") continue ;;
      "$want":*) PROFILE_CMDS="${line#*:}"; return 0 ;;
    esac
  done < "$SRC/profiles.txt"
  echo "Profil inconnu : $want" >&2
  echo "Disponibles : $(grep -v '^#' "$SRC/profiles.txt" | grep -v '^$' | cut -d: -f1 | tr '\n' ' ')" >&2
  exit 1
}
load_profile "$PROFILE"

# Vrai si la commande <basename sans .md> fait partie du profil courant.
in_profile() {
  [ "$PROFILE_CMDS" = "*" ] && return 0
  case " $PROFILE_CMDS " in *" $1 "*) return 0 ;; esac
  return 1
}

# --- Interactif : seulement sur un terminal, et seulement sans flags explicites.
# stdin porte le script sous `curl | bash`, donc on lit sur /dev/tty, jamais sur stdin.
ask() {
  local prompt="$1" default="$2" answer=""
  printf '%s [%s] ' "$prompt" "$default" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  printf '%s' "${answer:-$default}"
}
maybe_interactive() {
  [ "$EXPLICIT" = 1 ] && return 0          # l'utilisateur a déjà choisi
  [ -t 1 ] || return 0                      # pas un terminal : CI, pipe, curl redirigé
  [ -r /dev/tty ] || return 0
  case "$MODE" in uninstall) return 0 ;; esac
  echo "→ driven install — Entrée pour accepter le défaut."
  TARGET="$(ask "Cible ? claude / codex / grok / all" "$TARGET")"
  PROFILE="$(ask "Profil ? full / framing / delivery" "$PROFILE")"
  load_profile "$PROFILE"
}
maybe_interactive

# Supprime les fichiers posés par une install précédente (listés dans .dm-manifest) — jamais rien d'autre.
clean_tooling() {
  local dest="$1" line
  [ -f "$dest/.dm-manifest" ] || return 0
  while IFS= read -r line; do
    case "$line" in
      commands/*|skills/*|agents/*|prompts/*) rm -rf "$dest/$line" ;;
    esac
  done < "$dest/.dm-manifest"
}

# Copie les commandes retenues par le profil. Skills et agents ne sont jamais filtrés :
# les commandes les référencent par nom, une skill absente casse la commande qui la précharge.
copy_commands_in_profile() {
  local from="$1" to="$2" f
  mkdir -p "$to"
  for f in "$from/"*.md; do
    [ -e "$f" ] || continue
    in_profile "$(basename "$f" .md)" || continue
    cp "$f" "$to/"
  done
}

# Claude : copie verbatim (pas de build, pas de Node — chemin quotidien).
copy_tooling_claude() {
  local dest="$1" f
  clean_tooling "$dest"
  mkdir -p "$dest/commands" "$dest/skills" "$dest/agents"
  copy_commands_in_profile "$SRC/commands" "$dest/commands"
  cp -R "$SRC/skills/."   "$dest/skills/"
  cp -R "$SRC/agents/."   "$dest/agents/"
  : > "$dest/.dm-manifest"
  for f in "$SRC/commands/"*.md; do
    in_profile "$(basename "$f" .md)" || continue
    echo "commands/$(basename "$f")" >> "$dest/.dm-manifest"
  done
  for f in "$SRC/skills/"*/;     do echo "skills/$(basename "$f")"   >> "$dest/.dm-manifest"; done
  for f in "$SRC/agents/"*.md;   do echo "agents/$(basename "$f")"   >> "$dest/.dm-manifest"; done
  echo "$VERSION" > "$dest/.dm-version"
}

# Codex : transforme via le build Node → .codex/skills.
copy_tooling_codex() {
  local dest="$1" stg d
  command -v node >/dev/null 2>&1 || { echo "✗ Node requis pour la cible codex (build md→skills)." >&2; return 1; }
  stg="$(mktemp -d)"
  node "$PAYLOAD_ROOT/bin/dm-build.mjs" --target codex --src "$SRC" --out "$stg" >/dev/null
  clean_tooling "$dest"
  mkdir -p "$dest"
  cp -R "$stg/." "$dest/"
  # Les commandes deviennent des skills dm-* : on retire celles hors profil après build.
  for d in "$dest/skills/"dm-*/; do
    [ -e "$d" ] || continue
    in_profile "$(basename "$d")" || rm -rf "$d"
  done
  : > "$dest/.dm-manifest"
  for d in "$dest/skills/"*/; do echo "skills/$(basename "$d")" >> "$dest/.dm-manifest"; done
  echo "$VERSION" > "$dest/.dm-version"
  rm -rf "$stg"
}

# Grok : même arbre que Claude (commands + skills + agents) via le build Node → .grok/.
copy_tooling_grok() {
  local dest="$1" stg
  command -v node >/dev/null 2>&1 || { echo "✗ Node required for grok target." >&2; return 1; }
  stg="$(mktemp -d)"
  node "$PAYLOAD_ROOT/bin/dm-build.mjs" --target grok --src "$SRC" --out "$stg" >/dev/null
  clean_tooling "$dest"
  mkdir -p "$dest/commands" "$dest/skills" "$dest/agents"
  copy_commands_in_profile "$stg/commands" "$dest/commands"
  cp -R "$stg/skills/."   "$dest/skills/"
  cp -R "$stg/agents/."   "$dest/agents/"
  : > "$dest/.dm-manifest"
  for f in "$dest/commands/"*.md; do echo "commands/$(basename "$f")" >> "$dest/.dm-manifest"; done
  for f in "$dest/skills/"*/;     do echo "skills/$(basename "$f")"   >> "$dest/.dm-manifest"; done
  for f in "$dest/agents/"*.md;   do echo "agents/$(basename "$f")"   >> "$dest/.dm-manifest"; done
  echo "$VERSION" > "$dest/.dm-version"
  rm -rf "$stg"
}

# Copie un template seulement s'il est absent ou non modifié localement (baseline : $ORIG).
sync_templates() {
  local payload="$1" f name
  mkdir -p ./templates "$ORIG"
  for f in "$payload/templates/"*; do
    name="$(basename "$f")"
    if [ ! -f "./templates/$name" ]; then
      cp "$f" "./templates/$name"; cp "$f" "$ORIG/$name"
    elif [ -f "$ORIG/$name" ] && cmp -s "./templates/$name" "$ORIG/$name"; then
      cp "$f" "./templates/$name"; cp "$f" "$ORIG/$name"
    elif cmp -s "./templates/$name" "$f"; then
      cp "$f" "$ORIG/$name"
    elif [ "$FORCE" = 1 ]; then
      cp "$f" "./templates/$name"; cp "$f" "$ORIG/$name"
      echo "↻  templates/$name écrasé (--force)."
    else
      echo "⚠  templates/$name modifié localement — non écrasé (relance avec --force pour l'écraser)."
    fi
  done
}

# Tooling bash helpers + CI workflow template — always overwrite on install/update.
sync_lib() {
  local payload="${1:-$SRC}"
  mkdir -p ./.dm/lib
  cp -R "$payload/lib/." ./.dm/lib/
  cp "$payload/hooks/dm-gate.sh" ./.dm/lib/dm-gate.sh
  chmod +x ./.dm/lib/*.sh 2>/dev/null || true
  if [ -d "$payload/workflows" ]; then
    mkdir -p ./.dm/workflows
    cp -R "$payload/workflows/." ./.dm/workflows/
  fi
}

# AGENTS.md est la source de règles partagée (native pour Codex, importée par CLAUDE.md pour Claude).
drop_agents_md() {
  local payload="$1"
  if [ -f ./AGENTS.md ]; then
    echo "⚠  ./AGENTS.md existe déjà — non écrasé. Fusionne les rules driven à la main si besoin."
  else
    cp "$payload/AGENTS.md" ./AGENTS.md
  fi
}
wire_claude_md() {
  if [ -f ./CLAUDE.md ]; then
    grep -qxF '@AGENTS.md' ./CLAUDE.md || printf '\n@AGENTS.md\n' >> ./CLAUDE.md
  else
    printf '@AGENTS.md\n' > ./CLAUDE.md
  fi
}

# Enforcement repo-level : hooks git (opt-in, réversible). Indépendant de l'outil.
install_hooks() {
  command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "⚠  Pas un repo git — hooks non posés. (git init puis ./install.sh --hooks)"; return 0; }
  mkdir -p ./.dm-hooks
  cp "$SRC/hooks/dm-gate.sh" "$SRC/hooks/pre-commit" "$SRC/hooks/pre-push" ./.dm-hooks/
  chmod +x ./.dm-hooks/dm-gate.sh ./.dm-hooks/pre-commit ./.dm-hooks/pre-push
  git config core.hooksPath .dm-hooks
  echo "✅ Git hooks posés (core.hooksPath=.dm-hooks). Gates : pas de code sans plan validé, pas de ship sans review."
  echo "   Désactiver : git config --unset core.hooksPath"
}

# Désinstalle : retire exactement ce que le manifeste liste, jamais autre chose.
# Les fichiers que l'utilisateur a écrits lui-même n'y sont pas, donc ils survivent.
uninstall_one() {
  local dest="$1" line
  if [ ! -f "$dest/.dm-manifest" ]; then
    echo "→ Rien à retirer dans $dest (pas de .dm-manifest)."
    return 0
  fi
  while IFS= read -r line; do
    case "$line" in
      commands/*|skills/*|agents/*|prompts/*) ;;
      *) continue ;;
    esac
    [ -e "$dest/$line" ] || continue
    if [ "$DRY_RUN" = 1 ]; then
      echo "   [dry-run] $dest/$line"
    else
      rm -rf "$dest/$line"
      echo "   retiré $dest/$line"
    fi
  done < "$dest/.dm-manifest"
  if [ "$DRY_RUN" = 0 ]; then
    rm -f "$dest/.dm-manifest" "$dest/.dm-version"
    rmdir "$dest/commands" "$dest/skills" "$dest/agents" 2>/dev/null || true
  fi
}

uninstall_target() {
  case "$1" in
    claude) uninstall_one "./.claude" ;;
    codex)  uninstall_one "./.codex" ;;
    grok)   uninstall_one "./.grok" ;;
    all)    uninstall_one "./.claude"; uninstall_one "./.codex"; uninstall_one "./.grok" ;;
    *)      echo "Cible inconnue : $1 (claude|codex|grok|all)" >&2; exit 1 ;;
  esac
}

install_target() {
  case "$1" in
    claude)
      copy_tooling_claude "./.claude"
      sync_templates "$SRC"; sync_lib "$SRC"; drop_agents_md "$SRC"; wire_claude_md
      echo "✅ driven installé (Claude, projet, version $VERSION). Commandes : /dm-prd … /dm-ship" ;;
    codex)
      copy_tooling_codex "./.codex"
      sync_templates "$SRC"; sync_lib "$SRC"; drop_agents_md "$SRC"   # AGENTS.md natif Codex, pas de CLAUDE.md
      echo "✅ driven installé (Codex, projet, version $VERSION). Skills : dm-prd … dm-ship dans .codex/skills." ;;
    grok)
      copy_tooling_grok "./.grok"
      sync_templates "$SRC"; sync_lib "$SRC"; drop_agents_md "$SRC"   # AGENTS.md partagé, pas de CLAUDE.md requis
      echo "✅ driven installé (Grok, projet, version $VERSION). Commandes : dm-prd … dm-ship dans .grok/commands." ;;
    all)
      install_target claude
      install_target codex
      install_target grok ;;
    *)
      echo "Cible inconnue : $1 (claude|codex|grok|all)" >&2; exit 1 ;;
  esac
}

case "$MODE" in
  ""|--project)
    install_target "$TARGET"
    if [ "$HOOKS" = 1 ]; then install_hooks; fi
    ;;

  -g|--global)
    # Cache partagé (templates + AGENTS.md + installeur) pour `init` par projet.
    seed_cache() {
      mkdir -p "$CACHE"
      cp -R "$SRC/templates" "$CACHE/"
      cp -R "$SRC/lib" "$CACHE/"
      [ -d "$SRC/workflows" ] && cp -R "$SRC/workflows" "$CACHE/"
      cp "$SRC/AGENTS.md" "$CACHE/"
      cp "$PAYLOAD_ROOT/install.sh" "$CACHE/install.sh" 2>/dev/null \
        || cp "${BASH_SOURCE[0]:-$0}" "$CACHE/install.sh" 2>/dev/null || true
    }
    case "$TARGET" in
      claude)
        copy_tooling_claude "$HOME/.claude"; seed_cache
        echo "✅ Tooling installé (global Claude, version $VERSION). Commandes dans tous tes repos." ;;
      codex)
        copy_tooling_codex "$HOME/.codex"; seed_cache
        echo "✅ Tooling installé (global Codex, version $VERSION). Skills dans ~/.codex/skills." ;;
      grok)
        copy_tooling_grok "$HOME/.grok"; seed_cache
        echo "✅ Tooling installé (global Grok, version $VERSION). Commandes dans ~/.grok." ;;
      all)
        copy_tooling_claude "$HOME/.claude"; copy_tooling_codex "$HOME/.codex"; copy_tooling_grok "$HOME/.grok"; seed_cache
        echo "✅ Tooling installé (global Claude + Codex + Grok, version $VERSION)." ;;
      *) echo "Cible inconnue : $TARGET (claude|codex|grok|all)" >&2; exit 1 ;;
    esac
    echo "→ Dans chaque projet : ~/.claude/ai-driven-method/install.sh init [--target codex|grok] [--hooks]"
    ;;

  init)
    local_src="$SRC"; [ -d "$local_src/templates" ] || local_src="$CACHE"
    sync_templates "$local_src"; sync_lib "$local_src"; drop_agents_md "$local_src"
    case "$TARGET" in claude|all) wire_claude_md ;; esac   # CLAUDE.md seulement si Claude est cible
    echo "✅ templates + rules + .dm/lib ajoutés à $(pwd) (cible $TARGET)"
    if [ "$HOOKS" = 1 ]; then install_hooks; fi
    ;;

  uninstall)
    if [ "$DRY_RUN" = 1 ]; then echo "→ driven uninstall — dry-run, rien ne sera supprimé."; fi
    uninstall_target "$TARGET"
    if [ "$DRY_RUN" = 0 ]; then
      echo "✅ driven retiré ($TARGET). Templates, docs/, .dm/ et AGENTS.md sont laissés en place — à toi de voir."
      echo "   Hooks git : git config --unset core.hooksPath"
    fi
    ;;

  update)
    install_target "$TARGET"
    echo "✅ driven mis à jour ($TARGET, version $VERSION). AGENTS.md jamais touché — fusionne à la main si les rules ont évolué."
    if [ "$HOOKS" = 1 ]; then install_hooks; fi
    ;;

  *)
    echo "Option inconnue : $MODE" >&2
    echo "Usage : ./install.sh [--target claude|codex|grok|all] [--profile full|framing|delivery] [--hooks] [--global | init | update | uninstall] [--force] [--dry-run] [--yes]" >&2
    exit 1
    ;;
esac
