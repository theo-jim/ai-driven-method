import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const INIT = join(ROOT, "src/lib/dm-init.sh");
const GH_STUB = join(ROOT, "tests/fixtures/gh-stub.sh");

function initRepo() {
  const d = mkdtempSync(join(tmpdir(), "dm-init-"));
  execFileSync("git", ["init", "-b", "main"], { cwd: d, stdio: "pipe" });
  execFileSync("git", ["config", "user.email", "test@example.com"], {
    cwd: d,
    stdio: "pipe",
  });
  execFileSync("git", ["config", "user.name", "Test User"], {
    cwd: d,
    stdio: "pipe",
  });
  writeFileSync(join(d, "README.md"), "# app\n");
  execFileSync("git", ["add", "README.md"], { cwd: d, stdio: "pipe" });
  execFileSync("git", ["commit", "-m", "initial"], { cwd: d, stdio: "pipe" });

  const statePath = join(d, "gh-state.json");
  writeFileSync(statePath, "{}\n");
  const bin = join(d, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "gh"), readFileSync(GH_STUB));
  chmodSync(join(bin, "gh"), 0o755);
  chmodSync(INIT, 0o755);
  return { d, statePath, bin };
}

function runInit({ d, statePath, bin }, args = []) {
  execFileSync(
    "bash",
    [INIT, "run", "--yes", "--owner", "acme", "--repo", "app", ...args],
    {
      cwd: d,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}:${process.env.PATH}`,
        DM_GH_STUB_STATE: statePath,
      },
    },
  );
}

function branchExists(d, branch) {
  return (
    spawnSync("git", ["show-ref", "--verify", "--quiet", `refs/heads/${branch}`], {
      cwd: d,
    }).status === 0
  );
}

function rulesetTargets(state) {
  return (state.rulesets || []).map((ruleset) => ({
    name: ruleset.name,
    target: ruleset.conditions.ref_name.include[0],
  }));
}

test("dm-init --no-develop creates no develop branch and only protects main", () => {
  const fixture = initRepo();

  runInit(fixture, ["--no-develop"]);

  const config = JSON.parse(readFileSync(join(fixture.d, ".dm/config.json"), "utf8"));
  const state = JSON.parse(readFileSync(fixture.statePath, "utf8"));
  assert.equal(branchExists(fixture.d, "develop"), false);
  assert.equal(config.develop, false);
  assert.deepEqual(state.protections.map((protection) => protection.branch), ["main"]);
  assert.deepEqual(rulesetTargets(state), [
    { name: "driven-main", target: "refs/heads/main" },
  ]);
});

test("dm-init defaults to develop and creates protections and rulesets for both branches", () => {
  const fixture = initRepo();

  runInit(fixture);

  const config = JSON.parse(readFileSync(join(fixture.d, ".dm/config.json"), "utf8"));
  const state = JSON.parse(readFileSync(fixture.statePath, "utf8"));
  assert.equal(branchExists(fixture.d, "develop"), true);
  assert.equal(config.develop, true);
  assert.deepEqual(state.protections.map((protection) => protection.branch), [
    "main",
    "develop",
  ]);
  assert.deepEqual(rulesetTargets(state), [
    { name: "driven-main", target: "refs/heads/main" },
    { name: "driven-develop", target: "refs/heads/develop" },
  ]);
});
