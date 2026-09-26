import { existsSync, readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

const required = [
  "dm-prd", "dm-init", "dm-stories", "dm-stories-review", "dm-architect",
  "dm-design-system", "dm-research", "dm-design", "dm-plan", "dm-docs",
  "dm-execute", "dm-review", "dm-ship", "dm-release", "dm-orchestrator",
  "dm-status", "dm-help", "dm-continue", "dm-feature", "dm-fix",
];

test("all dv commands exist", () => {
  for (const n of required) {
    assert.ok(existsSync(`src/commands/${n}.md`), n);
  }
});

test("stories creates parent US only", () => {
  assert.match(readFileSync("src/commands/dm-stories.md", "utf8"), /issue-create-us/);
});

test("plan creates child tickets with size and person-day estimates", () => {
  const t = readFileSync("src/commands/dm-plan.md", "utf8");
  assert.match(t, /issue-create-ticket/);
  assert.match(t, /estimate/i);
  assert.match(t, /size/i);
  assert.match(t, /XS|S|M|L|XL/);
  assert.match(t, /0\.5/);
});

test("research does not require ready", () => {
  assert.doesNotMatch(readFileSync("src/commands/dm-research.md", "utf8"), /require-ready/);
});

test("execute requires child ready", () => {
  assert.match(readFileSync("src/commands/dm-execute.md", "utf8"), /require-ready/);
});

test("review and ship require child ready", () => {
  assert.match(readFileSync("src/commands/dm-review.md", "utf8"), /require-ready/);
  assert.match(readFileSync("src/commands/dm-ship.md", "utf8"), /require-ready/);
});

test("prd next step is dm-init", () => {
  const t = readFileSync("src/commands/dm-prd.md", "utf8");
  assert.match(t, /Next step: \/dm-init/);
  assert.doesNotMatch(t, /Next step: \/dm-stories/);
});

test("release tags main SHA, refuses double bump, documents squash-merge", () => {
  const t = readFileSync("src/commands/dm-release.md", "utf8");
  assert.match(t, /git fetch origin main/);
  assert.match(t, /git rev-parse origin\/main/);
  assert.match(t, /git tag "v\$\{ver\}" "\$main_sha"/);
  assert.match(t, /already in flight/);
  assert.match(t, /squash-merge|pr merge --squash/i);
});

test("ship sets test status", () => {
  assert.match(readFileSync("src/commands/dm-ship.md", "utf8"), /status-set .*test/);
});

test("release bumps version and wiki", () => {
  const t = readFileSync("src/commands/dm-release.md", "utf8");
  assert.match(t, /dm-version\.sh bump/);
  assert.match(t, /dm-wiki\.sh publish/);
});

test("continue is read-only on the board and writes onboarding.md", () => {
  const t = readFileSync("src/commands/dm-continue.md", "utf8");
  assert.match(t, /docs\/onboarding\.md/);
  assert.doesNotMatch(t, /require-ready/);
  assert.doesNotMatch(t, /issue-create-us|issue-create-ticket|status-set/);
});

test("continue is fail-closed on an empty repo and on an already-framed project", () => {
  const t = readFileSync("src/commands/dm-continue.md", "utf8");
  assert.match(t, /STOP/);
  assert.match(t, /docs\/prd\.md/);
});

test("continue hands off to dm-prd", () => {
  assert.match(readFileSync("src/commands/dm-continue.md", "utf8"), /Next step: \/dm-prd/);
});

test("prd offers a brownfield mode fed by onboarding.md", () => {
  const t = readFileSync("src/commands/dm-prd.md", "utf8");
  assert.match(t, /brownfield/i);
  assert.match(t, /docs\/onboarding\.md/);
});

test("stories adopts an issue mapped by onboarding.md, with confirmation", () => {
  const t = readFileSync("src/commands/dm-stories.md", "utf8");
  assert.match(t, /docs\/onboarding\.md/);
  assert.match(t, /issue-create-us/);
  assert.match(t, /issue-adopt/);
  assert.match(t, /confirm/i);
});

test("status and help route an existing project to dm-continue", () => {
  assert.match(readFileSync("src/commands/dm-status.md", "utf8"), /\/dm-continue/);
  assert.match(readFileSync("src/commands/dm-help.md", "utf8"), /\/dm-continue/);
});

test("design offers the native /design canvas path and keeps the file gate", () => {
  const t = readFileSync("src/commands/dm-design.md", "utf8");
  // Claude Code ships /design; on Claude the canvas is drafted in session instead
  // of the manual brief round-trip.
  assert.match(t, /\/design\b/);
  assert.match(t, /\.dc\.html/);
  // The published Artifact is never the deliverable: the pipeline gate reads files.
  assert.match(t, /docs\/designs\/<id>\.md/);
  assert.match(t, /Artifact/);
  // Tokens are injected, never guessed, on every path.
  assert.match(t, /docs\/design-system\.md/);
  // Codex and Grok have no /design: they keep the brief.
  assert.match(t, /Codex|Grok/);
});

test("doc records that the native design canvas is Claude-only", () => {
  const t = readFileSync("DOC.md", "utf8");
  assert.match(t, /\/design/);
  assert.match(t, /canvas/i);
});

test("orchestrator routes a project that predates driven to dm-continue", () => {
  const t = readFileSync("src/commands/dm-orchestrator.md", "utf8");
  assert.match(t, /\/dm-continue/);
  assert.match(t, /\/dm-prd/);
});

test("stories-review judges a feature against the shipped product", () => {
  const t = readFileSync("src/skills/stories-review/SKILL.md", "utf8");
  assert.match(t, /shipped/i);
  assert.match(t, /duplicat/i);
  // the closing contract lives in the agent, not the skill — it must not move
  assert.match(readFileSync("src/agents/stories-reviewer.md", "utf8"), /Stories ready/);
});

test("feature amends the PRD and appends stories without rewriting them", () => {
  const t = readFileSync("src/commands/dm-feature.md", "utf8");
  assert.match(t, /## Amendements/);
  assert.match(t, /append/i);
  assert.doesNotMatch(t, /rewrite docs\/stories\.md/i);
  assert.match(t, /issue-create-us/);
});

test("feature gates architecture on an explicit enumeration", () => {
  const t = readFileSync("src/commands/dm-feature.md", "utf8");
  for (const trigger of [/runtime dependency/i, /provider/i, /migration/i, /authorization/i, /queue/i]) {
    assert.match(t, trigger);
  }
  assert.match(t, /\/dm-architect/);
  assert.match(t, /\/dm-research/);
});

test("feature review does not clobber the framing review signal", () => {
  const t = readFileSync("src/commands/dm-feature.md", "utf8");
  assert.match(t, /docs\/reviews\/features\//);
  assert.match(t, /stories-reviewer/);
  assert.doesNotMatch(t, /write .*docs\/reviews\/stories\.md/i);
});

test("feature is fail-closed without a PRD or a breakdown", () => {
  const t = readFileSync("src/commands/dm-feature.md", "utf8");
  assert.match(t, /STOP/);
  assert.match(t, /docs\/prd\.md/);
  assert.match(t, /docs\/stories\.md/);
});

test("status and help route a fully shipped product to dm-feature", () => {
  assert.match(readFileSync("src/commands/dm-status.md", "utf8"), /\/dm-feature/);
  assert.match(readFileSync("src/commands/dm-help.md", "utf8"), /\/dm-feature/);
});

test("fix frames a standalone ticket and creates its board issue under the fix key", () => {
  const t = readFileSync("src/commands/dm-fix.md", "utf8");
  assert.match(t, /issue-create-ticket fix <id>/);
  assert.match(t, /fix\/<id>/);
  assert.match(t, /docs\/plans\/fix-/);
  assert.match(t, /validated/);
  assert.match(t, /size/i);
  assert.match(t, /estimate/i);
  assert.match(t, /AskUserQuestion/i);
});

test("fix plan template is scoped to a single fix, not a multi-ticket breakdown", () => {
  const t = readFileSync("src/templates/fix-plan.md", "utf8");
  assert.match(t, /validated: no/);
  assert.match(t, /size/i);
  assert.match(t, /estimate/i);
  assert.doesNotMatch(t, /Tickets \(ordered\)/);
});

test("execute, review and ship are fix-aware without disturbing the story/ticket contract", () => {
  for (const n of ["dm-execute", "dm-review", "dm-ship"]) {
    const t = readFileSync(`src/commands/${n}.md`, "utf8");
    assert.match(t, /fix\/<id>/, `${n} should mention fix/<id>`);
    assert.match(t, /docs\/plans\/fix-/, `${n} should mention docs/plans/fix-`);
  }
  const review = readFileSync("src/commands/dm-review.md", "utf8");
  assert.match(review, /docs\/reviews\/fix\//);
});

test("ship still requires the story product doc, and documents skipping it for a fix", () => {
  const t = readFileSync("src/commands/dm-ship.md", "utf8");
  assert.match(t, /docs\/product\/<story-id>\.md/);
  assert.match(t, /skip the .*docs\/product\/<story-id>\.md.* requirement/);
});

test("ship's fix-ticket note drops parent-sync from cleanup", () => {
  const t = readFileSync("src/commands/dm-ship.md", "utf8");
  assert.match(t, /no[\s\S]*`parent-sync`[\s\S]*call/);
});

test("fix declares the Agent tool, invokes worktree-manager for its own worktree, and commits the validated plan there", () => {
  const t = readFileSync("src/commands/dm-fix.md", "utf8");
  const frontmatter = t.split("---")[1];
  // Without Agent in allowed-tools, the command physically cannot invoke worktree-manager.
  assert.match(frontmatter, /^\s*-\s*Agent\s*$/m);
  // Must actually invoke the subagent for its own dedicated worktree, from the integration branch.
  assert.match(t, /invoke.*worktree-manager|worktree-manager.*invoke/is);
  assert.match(t, /\.worktrees\/fix\/<id>/);
  assert.match(t, /branch\s*`?fix\/<id>`?/);
  assert.match(t, /default-integration-branch/);
  // Every subsequent read/write must happen inside that worktree, never the repo base directory.
  assert.match(t, /never[\s\S]{0,40}repository\s+base\s+directory|repository\s+base\s+directory[\s\S]{0,10}never/i);
  // The validated plan must be committed on fix/<id> so /dm-execute can see it.
  assert.match(t, /git commit/);
  assert.match(t, /docs\/plans\/fix-<id>\.md/);
});

test("fix's worktree-manager step precedes writing the plan file", () => {
  const t = readFileSync("src/commands/dm-fix.md", "utf8");
  const wtIdx = t.search(/worktree-manager/);
  const writeIdx = t.search(/write `docs\/plans\/fix-<id>\.md`/i);
  assert.ok(wtIdx >= 0, "worktree-manager step must exist");
  assert.ok(writeIdx >= 0, "plan write step must exist");
  assert.ok(wtIdx < writeIdx, "worktree-manager must run before the plan is written");
});
