# Design: `next` → `develop`, branche optionnelle

Date: 2026-09-26

## Contexte

Le pipeline nommait sa branche d'intégration `next`. Deux changements demandés :
1. La renommer `develop`.
2. Rendre son existence optionnelle par projet (certains projets n'ont que `main`).

En creusant, un problème connexe est apparu mais reste **hors périmètre ici** : le
mode "Quick Fix" commit directement sur la branche d'intégration ; si cette branche
est protégée (`main` en mode sans `develop`, ou `develop` protégée manuellement), le
push direct échoue. Ce diff ne fait que renommer `next` → `develop` dans la prose de
Quick Fix (même comportement, même limite connue) ; le vrai correctif (fallback
push→PR ou autre) est différé et traité avec le futur système `fix` ci-dessous.

## Hors périmètre (différé, chantiers séparés)

- Vrai support GitLab (glab/API, rulesets, board, wiki) — un autre worker `/herd`. Seul
  le vocabulaire générique ("pull/merge request") est gardé où c'est gratuit.
- Le comportement de Quick Fix quand le push direct sur l'intégration est refusé
  (branche protégée) — connu, non corrigé dans ce diff.
- Un nouveau système `fix` : ticket de plein droit (worktree, TDD, sous-agents,
  commande `/dm-fix`, Issue autonome sur le board avec les statuts ticket) pour un
  correctif qui n'est lié à aucune story. Ce système **remplacera** Quick Fix à terme
  (et réglera au passage le point ci-dessus), mais c'est un chantier à part, spécifié
  séparément, pas mélangé à ce diff. Le nom `fix/*` est **réservé** pour lui.

## Décisions

### 1. Config et nommage
- `.dm/config.json` gagne `"develop": true|false`. Absent = `true` (comportement
  actuel préservé). Décidé à `/dm-init` (flag `--no-develop`, pas de prompt interactif
  requis — cohérent avec `--no-remote`/`--public`/`--private`).
- Pas de nom de branche personnalisable : c'est `develop`, un booléen suffit (YAGNI).
- Source de vérité unique côté scripts : `dm-gate.sh` → `integration_branch()` lit
  `.dm/config.json` directement (tolérant : fichier/champ absent → `develop`), sans
  dépendre de `dm-config.sh` (qui exige owner/repo/project, inutiles ici).

### 2. Collapse naturel en mode sans `develop`
- `pre_push()` compare déjà `integration_branch()` à `production_branch()`. Si les deux
  valent `main` (pas de `develop`), les mêmes règles s'appliquent à `main` sans code
  spécifique : PR de `feature/*` directement vers `main`, gate `Ship allowed: yes`
  inchangé.

### 3. Quick Fix : pas de changement de comportement
- Renommage textuel uniquement (`next` → `develop`/"the integration branch" dans sa
  description). Le comportement (commit direct sur l'intégration) et sa limite
  connue (push refusé si protégée) restent tels quels — voir "Hors périmètre".

### 4. `/dm-init` et CI
- `--no-develop` sur `dm-init.sh run`. Sans lui : crée/protège/route `develop` comme
  aujourd'hui. Avec lui : seul `main` protégé, ruleset `driven-main` routé sur
  `feature/*` directement.
- `dm-gate.yml` (template CI) : `on.pull_request.branches: [develop, main]` toujours ;
  une step résout l'intégration depuis `.dm/config.json` et l'expose en output ; les
  steps suivantes comparent `base_ref`/`head_ref` à cet output au lieu d'un nom en dur.

### 5. Docs et prose des agents
- Terme unique **"the integration branch"** défini une fois dans `src/AGENTS.md`
  ("`develop` si `.dm/config.json.develop === true`, sinon `main` — résolu via
  `dm-gate.sh default-integration-branch`"), puis utilisé partout où `next` était en
  dur (commandes, agents, template de review).
- `README.md`/`DOC.md` (doc du repo lui-même) : `main`/`develop`, `develop` notée
  optionnelle.
- Exclus : `docs/superpowers/plans/*` et `docs/superpowers/specs/*` (archives
  immuables, même logique que les ADR — on ne réécrit pas l'historique).

## Fichiers impactés

Scripts : `src/hooks/dm-gate.sh`, `src/lib/dm-init.sh`, `src/workflows/dm-gate.yml`.
Docs/prose : `src/AGENTS.md`, `src/commands/*.md` (dm-init, dm-execute, dm-ship,
dm-release, dm-orchestrator, dm-research, dm-status, dm-stories, dm-help, dm-continue,
dm-feature), `src/agents/{implementer,worktree-manager,reviewer}.md`,
`src/templates/review-checklist.md`, `README.md`, `DOC.md`.
Tests : `tests/gate.test.mjs`, `tests/quality-bar.test.mjs` (+ nouveaux cas
`develop: false` et `--no-develop`).
