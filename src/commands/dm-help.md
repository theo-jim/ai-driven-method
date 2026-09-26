---
description: Affiche le pipeline driven — l'ordre des phases, US vs tickets
disable-model-invocation: true
---
# driven — Pipeline

Règle unique : interdit de coder en direct. Chaque feature passe par le pipeline.

## Projet existant (code déjà là)
0. /dm-continue          — baseline produit `docs/onboarding.md` + mapping des Issues déjà écrites, sans rien muter. Puis on reprend en 1.

## Une fois par projet
1. /dm-prd <cible>       — cadre le produit : clone ou greenfield, périmètre, QUOI + POURQUOI
2. /dm-init              — repo GitHub, branches `main` (+ `develop` optionnelle), Project, wiki, VERSION, CI
3. /dm-stories           — découpe en **user stories** (Issues parent, colonne `backlog`)
4. /dm-stories-review    — relit le découpage vs le PRD (contexte vierge)
5. /dm-architect         — stack, conventions, rules
6. /dm-design-system     — design system global (tokens, composants)

## Par user story (framing — branche `feature/<story-id>`)
7. /dm-research <story>  — contexte réel (pas de gate `ready`)
8. /dm-design <story>    — écran depuis le design system si UI (pas de `ready`)
9. /dm-plan <story>      — **tickets enfants** `tNN-…` avec `size` (XS–XL) et `estimate` (par pas de 0,5 j : 0,5 / 1 / 1,5…)
10. /dm-docs <story>     — page produit `docs/product/<story>.md` (pas de push wiki)

## Par ticket (livraison — branche `feature/<story>/<ticket>`)
La colonne **`ready` n'existe que sur les tickets enfants**, jamais sur l'US parent.
11. /dm-execute <story> <ticket>  — `require-ready` puis code en TDD (subagent)
12. /dm-review <story> <ticket>   — review + gate `Ship allowed`
13. /dm-ship <story> <ticket>     — PR vers **la branche d'intégration** (`develop`, sinon `main`) ; après merge → enfant `test` + `parent-sync`

## Release (production)
14. /dm-release           — US parent en `test` ; bump VERSION ; PR intégration → `main` (sautée si pas de `develop`) ; wiki ; `shipped`

## Après la v1 (produit livré)
15. /dm-feature <slug>   — cadre une feature, amende le PRD (section `## Amendements`), ajoute les stories au backlog. Puis pipeline normal : `/dm-architect` si la feature touche l'architecture, sinon `/dm-research <story>`.

## US vs tickets (à retenir)
| | User story (parent) | Ticket (enfant) |
| --- | --- | --- |
| Id | `s01-…` | `s01-…/t01-…` |
| Board | backlog → in progress → test → shipped (**pas** `ready`) | backlog → **ready** → in progress → test → shipped |
| Branche | `feature/<story>` (docs only) | `feature/<story>/<ticket>` (code) |
| Création Issue | `/dm-stories` (`issue-create-us`) | `/dm-plan` Validate (`issue-create-ticket`) |

## Fix ponctuel (hors story)
`/dm-fix <description>` crée un ticket autonome sans story parente, avec la
même rigueur qu'un ticket normal (worktree, TDD, sous-agents). Branche
`fix/<id>`, puis `/dm-execute fix/<id>` → `/dm-review fix/<id>` →
`/dm-ship fix/<id>`.

## Orchestrateur
- `/dm-orchestrator <story>` — research → design → plan (checkpoint) → docs, puis liste les tickets en backlog
- `/dm-orchestrator <story> <ticket>` — execute → review → ship (checkpoint)

État du projet : `/dm-status`
