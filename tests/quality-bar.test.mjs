import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

test("quality-bar skill exists and blocks major", () => {
  const t = readFileSync("src/skills/quality-bar/SKILL.md", "utf8");
  assert.match(t, /major/);
  assert.match(t, /Ship allowed: no/);
  assert.match(t, /security/i);
  assert.match(t, /factori[sz]ation|duplicat/i);
});

test("reviewer preloads quality-bar", () => {
  const t = readFileSync("src/agents/reviewer.md", "utf8");
  assert.match(t, /quality-bar/);
});

test("reviewer judges ticket diff vs the integration branch", () => {
  const t = readFileSync("src/agents/reviewer.md", "utf8");
  assert.match(t, /git diff <integration-branch>\.\.\.feature\/<story-id>\/<ticket-id>/);
  assert.match(t, /default-integration-branch/);
  assert.match(t, /docs\/reviews\/<story-id>\/<ticket-id>\.md/);
});

test("review checklist is per ticket", () => {
  const t = readFileSync("src/templates/review-checklist.md", "utf8");
  assert.match(t, /Security/i);
  assert.match(t, /Factor/i);
  assert.match(t, /git diff <integration-branch>\.\.\.feature\/<story-id>\/<ticket-id>/);
  assert.match(t, /docs\/reviews\/<story-id>\/<ticket-id>\.md/);
});

test("implementer is ticket-scoped", () => {
  const t = readFileSync("src/agents/implementer.md", "utf8");
  assert.match(t, /\.worktrees\/<story-id>\/<ticket-id>/);
  assert.match(t, /feature\/<story-id>\/<ticket-id>/);
  assert.match(t, /one single commit for the ticket/);
  assert.doesNotMatch(t, /one single commit for the whole story/);
  assert.doesNotMatch(t, /\.worktrees\/<story-id>`/);
});

test("implementer's fix-ticket note is an explicit substitution list, not just a path summary", () => {
  const t = readFileSync("src/agents/implementer.md", "utf8");
  assert.match(t, /substitute\s+throughout\s+this\s+document/i);
  assert.match(t, /`docs\/plans\/<story-id>\.md`\s*→\s*`docs\/plans\/fix-<id>\.md`/);
  assert.match(t, /`docs\/research\/<story-id>\.md`\s*→\s*does\s+not\s+exist\s+for\s+a\s+fix/i);
  assert.match(t, /`\.worktrees\/<story-id>\/<ticket-id>`\s*→\s*`\.worktrees\/fix\/<id>`/);
  assert.match(t, /`feature\/<story-id>\/<ticket-id>`\s*→\s*`fix\/<id>`/);
  // pre-existing story/ticket tokens the rest of the file relies on must survive unchanged
  assert.match(t, /\.worktrees\/<story-id>\/<ticket-id>/);
  assert.match(t, /feature\/<story-id>\/<ticket-id>/);
  assert.match(t, /docs\/plans\/<story-id>\.md/);
});

test("reviewer's fix-ticket note is an explicit substitution list, not just a path summary", () => {
  const t = readFileSync("src/agents/reviewer.md", "utf8");
  assert.match(t, /substitute\s+throughout\s+this\s+document/i);
  assert.match(t, /`docs\/plans\/<story-id>\.md`\s*→\s*`docs\/plans\/fix-<id>\.md`/);
  assert.match(t, /`docs\/research\/<story-id>\.md`\s*→\s*does\s+not\s+exist\s+for\s+a\s+fix/i);
  assert.match(t, /`docs\/reviews\/<story-id>\/<ticket-id>\.md`\s*→\s*`docs\/reviews\/fix\/<id>\.md`/);
  // pre-existing tokens later in the file, asserted verbatim by other tests, must survive
  assert.match(t, /git diff <integration-branch>\.\.\.feature\/<story-id>\/<ticket-id>/);
  assert.match(t, /docs\/reviews\/<story-id>\/<ticket-id>\.md/);
});

test("review-checklist's fix-ticket note is an explicit substitution list, not just a path summary", () => {
  const t = readFileSync("src/templates/review-checklist.md", "utf8");
  // The note is a blockquote: continuation lines are prefixed with "> ", so
  // tolerate that marker between words in a wrapped multi-word phrase.
  assert.match(t, /substitute[\s>]+throughout[\s>]+this[\s>]+document/i);
  assert.match(t, /`feature\/<story-id>\/<ticket-id>`[\s>]*→[\s>]*`fix\/<id>`/);
  assert.match(t, /`docs\/reviews\/<story-id>\/<ticket-id>\.md`[\s>]*→[\s>]*`docs\/reviews\/fix\/<id>\.md`/);
  assert.match(t, /no[\s>]+per-ticket[\s>]+plan[\s>]+section/i);
  // pre-existing tokens asserted verbatim elsewhere must survive
  assert.match(t, /git diff <integration-branch>\.\.\.feature\/<story-id>\/<ticket-id>/);
  assert.match(t, /docs\/reviews\/<story-id>\/<ticket-id>\.md/);
});

test("tdd-skill is one commit per ticket", () => {
  const t = readFileSync("src/skills/tdd-skill/SKILL.md", "utf8");
  assert.match(t, /One commit per ticket/);
  assert.match(t, /Max two new test files per ticket/);
  assert.doesNotMatch(t, /One commit per story/);
  assert.doesNotMatch(t, /per story/);
});
