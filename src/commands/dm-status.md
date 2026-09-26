---
description: Show the project's pipeline state — framing, board columns, next command
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
---
# dm-status — Where the project stands

Derive the state from the files and the board — never guess. Bash is for read-only git queries and `bash .dm/lib/dm-board.sh status-get`.

1. Framing: do docs/prd.md, docs/stories.md, docs/architecture.md, docs/design-system.md exist? Also grep `^Stories ready:` docs/reviews/stories.md. Show `VERSION` when present. Missing framing → that command is next (`/dm-prd`, `/dm-init`, …).
2. Stories (parent US): list ids from docs/stories.md. For each id:
   - complexity from docs/stories.md
   - board column: `bash .dm/lib/dm-board.sh status-get <id>` (or `n/a` if `.dm/config.json` missing)
   - research / design / plan (`validated: yes`?) / product doc `docs/product/<id>.md`
   - from the plan: total person-days (sum of `estimate:`) and size mix (count of XS–XL)
   - remaining: children not yet `test`/`shipped`
3. Tickets (children): for each `t*` in docs/plans/<id>.md:
   - `bash .dm/lib/dm-board.sh status-get <story-id>/<ticket-id>`
   - size, estimate
   - review: grep `^Ship allowed:` docs/reviews/<story>/<ticket>.md
   - PR/MR / ship state vs the integration branch
4. Start with one-line summary: X shipped / Y in test / Z in progress / W backlog. Compact tables: US row, then indented ticket rows. Next command is the most useful one (often "move t02 to ready" or `/dm-execute s01 t01` or `/dm-release`). When every story is `shipped` and nothing is in flight, the product is released and the useful next command is `/dm-feature <slug>` — say so rather than reporting an empty pipeline.
5. Decisions: if docs/decisions/ exists, mention ADR count and the latest one.

If docs/ doesn't exist at all, the project hasn't started. Two cases: source files exist outside `docs/` **and** the git history holds more than one commit → the project predates driven, point to /dm-continue. Otherwise the repo is empty: point to /dm-prd.

End with the single most useful next command, e.g.: "Next: /dm-docs s02-…" or "Next: move s01/t02 to ready, then /dm-execute s01 t02".
