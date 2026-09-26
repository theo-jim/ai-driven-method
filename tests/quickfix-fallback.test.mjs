import { execFileSync, execSync } from "node:child_process";
import {
  chmodSync,
  cpSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const GATE = join(ROOT, "src/hooks/dm-gate.sh");
const AGENTS = join(ROOT, "src/AGENTS.md");
const GH_STUB = join(ROOT, "tests/fixtures/gh-stub.sh");

function repo({ develop = true, protectIntegration = false, mergeMode = "manual" } = {}) {
  const d = mkdtempSync(join(tmpdir(), "dm-quickfix-"));
  const integration = develop ? "develop" : "main";
  const origin = mkdtempSync(join(tmpdir(), "dm-quickfix-origin-"));

  execSync("git init -b main", { cwd: d, stdio: "pipe" });
  execSync("git config user.email t@t", { cwd: d, stdio: "pipe" });
  execSync("git config user.name t", { cwd: d, stdio: "pipe" });
  writeFileSync(join(d, "README"), "x");
  execSync("git add README", { cwd: d, stdio: "pipe" });
  execSync("git commit -m initial", { cwd: d, stdio: "pipe" });
  if (develop) execSync("git branch develop", { cwd: d, stdio: "pipe" });

  mkdirSync(join(d, ".dm"), { recursive: true });
  writeFileSync(join(d, ".dm/config.json"), JSON.stringify({ develop }));
  const agents = readFileSync(AGENTS, "utf8").replace(
    "Merge mode: manual",
    `Merge mode: ${mergeMode}`,
  );
  writeFileSync(join(d, "AGENTS.md"), agents);

  execSync(`git init --bare ${origin}`, { stdio: "pipe" });
  execSync(`git remote add origin ${origin}`, { cwd: d, stdio: "pipe" });
  execSync("git push -u origin main", { cwd: d, stdio: "pipe" });
  if (develop) execSync("git push origin develop", { cwd: d, stdio: "pipe" });
  execSync(`git checkout ${integration}`, { cwd: d, stdio: "pipe" });

  if (protectIntegration) {
    const hook = join(origin, "hooks/pre-receive");
    writeFileSync(
      hook,
      `#!/bin/sh\nwhile read old new ref; do\n  if [ "$ref" = "refs/heads/${integration}" ]; then\n    echo "protected ${integration}" >&2\n    exit 1\n  fi\ndone\n`,
    );
    chmodSync(hook, 0o755);
  }

  const statePath = join(d, "gh-state.json");
  writeFileSync(statePath, JSON.stringify({ prs: [] }, null, 2));
  const bin = join(d, "bin");
  mkdirSync(bin, { recursive: true });
  cpSync(GH_STUB, join(bin, "gh"));
  chmodSync(join(bin, "gh"), 0o755);

  return { d, integration, statePath, bin };
}

function commitQuickfix(d) {
  writeFileSync(join(d, "quickfix.txt"), "fixed\n");
  execSync("git add quickfix.txt", { cwd: d, stdio: "pipe" });
  execSync("git commit -m quickfix", { cwd: d, stdio: "pipe" });
}

function runQuickfix({ d, bin, statePath }) {
  return execFileSync("bash", [GATE, "quickfix-push"], {
    cwd: d,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      DM_GH_STUB_STATE: statePath,
    },
  });
}

function remoteHead(d, branch) {
  return execSync(`git ls-remote --heads origin ${branch}`, {
    cwd: d,
    encoding: "utf8",
    stdio: "pipe",
  }).trim();
}

test("quickfix-push sends an unprotected integration branch directly without creating a PR", () => {
  const r = repo();
  commitQuickfix(r.d);

  runQuickfix(r);

  assert.equal(remoteHead(r.d, r.integration).split(/\s+/)[0], execSync("git rev-parse HEAD", {
    cwd: r.d,
    encoding: "utf8",
  }).trim());
  assert.deepEqual(JSON.parse(readFileSync(r.statePath, "utf8")).prs, []);
  assert.equal(execSync("git branch --list 'quickfix/*'", { cwd: r.d, encoding: "utf8" }).trim(), "");
});

for (const develop of [true, false]) {
  const integration = develop ? "develop" : "main";
  test(`quickfix-push opens but does not merge a fallback PR to protected ${integration} in manual mode`, () => {
    const r = repo({ develop, protectIntegration: true });
    commitQuickfix(r.d);

    runQuickfix(r);

    const state = JSON.parse(readFileSync(r.statePath, "utf8"));
    assert.equal(state.prs.length, 1);
    assert.equal(state.prs[0].base, integration);
    assert.match(state.prs[0].head, /^quickfix\//);
    assert.equal(state.prs[0].state, "OPEN");
    assert.equal(state.merge_calls ?? 0, 0);
    assert.match(remoteHead(r.d, state.prs[0].head), /refs\/heads\/quickfix\//);
    assert.match(execSync(`git branch --list ${state.prs[0].head}`, { cwd: r.d, encoding: "utf8" }), /quickfix\//);
  });
}

for (const develop of [true, false]) {
  const integration = develop ? "develop" : "main";
  test(`quickfix-push proves and cleans up an auto-merged fallback PR to protected ${integration}`, () => {
    const r = repo({ develop, protectIntegration: true, mergeMode: "auto" });
    commitQuickfix(r.d);

    runQuickfix(r);

    const state = JSON.parse(readFileSync(r.statePath, "utf8"));
    assert.equal(state.prs.length, 1);
    assert.equal(state.prs[0].base, integration);
    assert.equal(state.prs[0].state, "MERGED");
    assert.notEqual(state.prs[0].mergedAt, null);
    assert.equal(state.merge_calls, 1);
    assert.ok(state.view_calls >= 1);
    assert.equal(remoteHead(r.d, state.prs[0].head), "");
    assert.equal(execSync(`git branch --list ${state.prs[0].head}`, { cwd: r.d, encoding: "utf8" }).trim(), "");
  });
}
