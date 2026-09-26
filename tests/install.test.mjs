import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const INSTALL = join(ROOT, "install.sh");

function project() {
  return mkdtempSync(join(tmpdir(), "dm-install-"));
}

function run(cwd, args) {
  return execFileSync("bash", [INSTALL, ...args], { cwd, encoding: "utf8" });
}

test("install lays down commands and records them in the manifest", () => {
  const d = project();
  run(d, ["--target", "claude"]);
  assert.ok(existsSync(join(d, ".claude/commands/dm-prd.md")));
  assert.ok(existsSync(join(d, ".claude/commands/dm-ship.md")));
  assert.ok(existsSync(join(d, ".dm/lib/dm-gate.sh")));
  const manifest = readFileSync(join(d, ".claude/.dm-manifest"), "utf8");
  assert.match(manifest, /commands\/dm-prd\.md/);
});

test("uninstall removes what the manifest lists and nothing else", () => {
  const d = project();
  run(d, ["--target", "claude"]);
  // a command the user wrote themselves, never in the manifest
  writeFileSync(join(d, ".claude/commands/my-own.md"), "mine\n");
  mkdirSync(join(d, ".claude/skills/my-skill"), { recursive: true });
  writeFileSync(join(d, ".claude/skills/my-skill/SKILL.md"), "mine\n");

  run(d, ["uninstall", "--target", "claude"]);

  assert.equal(existsSync(join(d, ".claude/commands/dm-prd.md")), false);
  assert.equal(existsSync(join(d, ".claude/commands/dm-ship.md")), false);
  assert.ok(existsSync(join(d, ".claude/commands/my-own.md")), "user command must survive");
  assert.ok(existsSync(join(d, ".claude/skills/my-skill/SKILL.md")), "user skill must survive");
});

test("uninstall --dry-run lists without deleting", () => {
  const d = project();
  run(d, ["--target", "claude"]);
  const out = run(d, ["uninstall", "--target", "claude", "--dry-run"]);
  assert.match(out, /dm-prd\.md/);
  assert.ok(existsSync(join(d, ".claude/commands/dm-prd.md")), "dry-run must delete nothing");
});

test("profile framing installs the framing commands and not the delivery ones", () => {
  const d = project();
  run(d, ["--target", "claude", "--profile", "framing"]);
  assert.ok(existsSync(join(d, ".claude/commands/dm-prd.md")));
  assert.ok(existsSync(join(d, ".claude/commands/dm-stories.md")));
  assert.equal(existsSync(join(d, ".claude/commands/dm-ship.md")), false);
  assert.equal(existsSync(join(d, ".claude/commands/dm-execute.md")), false);
});

test("profile delivery installs the delivery commands and not the framing ones", () => {
  const d = project();
  run(d, ["--target", "claude", "--profile", "delivery"]);
  assert.ok(existsSync(join(d, ".claude/commands/dm-execute.md")));
  assert.ok(existsSync(join(d, ".claude/commands/dm-ship.md")));
  assert.equal(existsSync(join(d, ".claude/commands/dm-prd.md")), false);
});

test("an unknown profile fails loudly instead of installing everything", () => {
  const d = project();
  assert.throws(() => run(d, ["--target", "claude", "--profile", "nope"]));
  assert.equal(existsSync(join(d, ".claude/commands/dm-prd.md")), false);
});

test("skills and agents are never filtered by a profile", () => {
  const d = project();
  run(d, ["--target", "claude", "--profile", "framing"]);
  // commands reference skills and agents by name; filtering them would break the chain
  assert.ok(existsSync(join(d, ".claude/skills/quality-bar/SKILL.md")));
  assert.ok(existsSync(join(d, ".claude/agents/reviewer.md")));
});

test("non-interactive stdin never prompts", () => {
  const d = project();
  const out = execFileSync("bash", [INSTALL, "--target", "claude"], {
    cwd: d,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
  });
  assert.match(out, /driven install/i);
  assert.ok(existsSync(join(d, ".claude/commands/dm-prd.md")));
});

test("the installer stamps a semver, not a git sha", () => {
  const d = project();
  run(d, ["--target", "claude"]);
  const stamped = readFileSync(join(d, ".claude/.dm-version"), "utf8").trim();
  assert.match(stamped, /^\d+\.\d+\.\d+$/, `expected semver, got ${stamped}`);
  assert.equal(stamped, readFileSync(join(ROOT, "VERSION"), "utf8").trim());
});
