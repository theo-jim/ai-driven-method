import { execFileSync, execSync } from "node:child_process";
import {
  mkdtempSync,
  writeFileSync,
  mkdirSync,
  chmodSync,
  readFileSync,
  cpSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const GATE = join(ROOT, "src/hooks/dm-gate.sh");
const AGENTS = join(ROOT, "src/AGENTS.md");
const GH_STUB = join(ROOT, "tests/fixtures/gh-stub.sh");
const LIB_SRC = join(ROOT, "src/lib");

const BOARD_CONFIG = {
  owner: "acme",
  repo: "app",
  project_id: "PVT_test",
  project_number: 1,
  status_field_id: "FIELD_status",
  status_option_ids: {
    backlog: "opt1",
    ready: "opt2",
    "in progress": "opt3",
    test: "opt4",
    shipped: "opt5",
  },
};

function repo({ develop = true } = {}) {
  const d = mkdtempSync(join(tmpdir(), "dm-gate-"));
  execSync("git init -b main && git config user.email t@t && git config user.name t", {
    cwd: d,
    stdio: "pipe",
  });
  writeFileSync(join(d, "README"), "x");
  execSync("git add README && git commit -m i", { cwd: d, stdio: "pipe" });
  if (develop) {
    execSync("git branch develop", { cwd: d, stdio: "pipe" });
  }
  return d;
}

function writeDmConfig(d, fields) {
  mkdirSync(join(d, ".dm"), { recursive: true });
  writeFileSync(join(d, ".dm/config.json"), JSON.stringify(fields, null, 2));
}

function withBoard(d, issues) {
  mkdirSync(join(d, ".dm/lib"), { recursive: true });
  writeFileSync(join(d, ".dm/config.json"), JSON.stringify(BOARD_CONFIG, null, 2));
  for (const name of ["dm-board.sh", "dm-config.sh"]) {
    cpSync(join(LIB_SRC, name), join(d, ".dm/lib", name));
    chmodSync(join(d, ".dm/lib", name), 0o755);
  }
  const statePath = join(d, "gh-state.json");
  writeFileSync(
    statePath,
    JSON.stringify(
      {
        issues,
        status_option_ids: BOARD_CONFIG.status_option_ids,
        edits: [],
      },
      null,
      2,
    ),
  );
  const bin = join(d, "bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, "gh"), readFileSync(GH_STUB));
  chmodSync(join(bin, "gh"), 0o755);
  return { statePath, bin };
}

function childIssue(statusName, optionId) {
  return {
    title: "[s01-x/t01-y] Persist (M, 1.5d)",
    number: 2,
    projectItems: [{ id: "PVTI_2", status: { optionId, name: statusName } }],
  };
}

function writeValidatedPlan(d) {
  mkdirSync(join(d, "docs/plans"), { recursive: true });
  writeFileSync(join(d, "docs/plans/s01-x.md"), "---\nvalidated: yes\n---\n");
}

function stageCode(d) {
  writeFileSync(join(d, "code.js"), "1");
  execSync("git add code.js", { cwd: d, stdio: "pipe" });
}

function runGate(cwd, args, opts = {}) {
  chmodSync(GATE, 0o755);
  return execFileSync("bash", [GATE, ...args], {
    cwd,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
    input: opts.input ?? "",
    env: {
      ...process.env,
      ...(opts.env || {}),
    },
  });
}

test("plan-validated fails without file", () => {
  const d = repo();
  assert.throws(() => runGate(d, ["plan-validated", "s01-x"]));
});

test("plan-validated passes with validated: yes", () => {
  const d = repo();
  mkdirSync(join(d, "docs/plans"), { recursive: true });
  writeFileSync(join(d, "docs/plans/s01-x.md"), "---\nvalidated: yes\n---\n");
  assert.equal(runGate(d, ["plan-validated", "s01-x"]), "");
});

test("ship-allowed fails without review", () => {
  const d = repo();
  assert.throws(() => runGate(d, ["ship-allowed", "s01-x"]));
});

test("ship-allowed fails when Ship allowed: no", () => {
  const d = repo();
  mkdirSync(join(d, "docs/reviews"), { recursive: true });
  writeFileSync(
    join(d, "docs/reviews/s01-x.md"),
    "Max severity: critical\nShip allowed: no\n",
  );
  assert.throws(() => runGate(d, ["ship-allowed", "s01-x"]));
});

test("ship-allowed passes with Ship allowed: yes", () => {
  const d = repo();
  mkdirSync(join(d, "docs/reviews"), { recursive: true });
  writeFileSync(
    join(d, "docs/reviews/s01-x.md"),
    "Max severity: none\nShip allowed: yes\n",
  );
  assert.equal(runGate(d, ["ship-allowed", "s01-x"]), "");
});

test("ship-allowed accepts ticket review path", () => {
  const d = repo();
  mkdirSync(join(d, "docs/reviews/s01-x"), { recursive: true });
  writeFileSync(
    join(d, "docs/reviews/s01-x/t01-y.md"),
    "Max severity: none\nShip allowed: yes\n",
  );
  assert.equal(runGate(d, ["ship-allowed", "s01-x/t01-y"]), "");
});

test("default-integration-branch prints develop when no config", () => {
  const d = repo();
  const out = runGate(d, ["default-integration-branch"]).trim();
  assert.equal(out, "develop");
});

test("default-integration-branch prints develop when config has develop: true", () => {
  const d = repo();
  writeDmConfig(d, { develop: true });
  const out = runGate(d, ["default-integration-branch"]).trim();
  assert.equal(out, "develop");
});

test("default-integration-branch prints main when config has develop: false", () => {
  const d = repo({ develop: false });
  writeDmConfig(d, { develop: false });
  const out = runGate(d, ["default-integration-branch"]).trim();
  assert.equal(out, "main");
});

test("pre-push refuses non-develop push into main", () => {
  const d = repo();
  execSync("git checkout -b feature/s01-x/t01-y", { cwd: d, stdio: "pipe" });
  writeFileSync(join(d, "code.js"), "1");
  execSync("git add code.js && git commit -m feat", { cwd: d, stdio: "pipe" });
  const sha = execSync("git rev-parse HEAD", { cwd: d, encoding: "utf8" }).trim();
  const zero = "0000000000000000000000000000000000000000";
  const input = `refs/heads/feature/s01-x/t01-y ${sha} refs/heads/main ${zero}\n`;
  assert.throws(() => runGate(d, ["pre-push"], { input }));
});

test("pre-push allows develop into main", () => {
  const d = repo();
  execSync("git checkout develop", { cwd: d, stdio: "pipe" });
  writeFileSync(join(d, "release.txt"), "1");
  execSync("git add release.txt && git commit -m release", { cwd: d, stdio: "pipe" });
  const sha = execSync("git rev-parse HEAD", { cwd: d, encoding: "utf8" }).trim();
  const zero = "0000000000000000000000000000000000000000";
  const input = `refs/heads/develop ${sha} refs/heads/main ${zero}\n`;
  assert.equal(runGate(d, ["pre-push"], { input }), "");
});

test("pre-push allows framing feature branch into develop without review", () => {
  const d = repo();
  execSync("git checkout -b feature/s01-x develop", { cwd: d, stdio: "pipe" });
  mkdirSync(join(d, "docs/research"), { recursive: true });
  writeFileSync(join(d, "docs/research/s01-x.md"), "research");
  execSync("git add docs && git commit -m research", { cwd: d, stdio: "pipe" });
  const sha = execSync("git rev-parse HEAD", { cwd: d, encoding: "utf8" }).trim();
  const zero = "0000000000000000000000000000000000000000";
  const input = `refs/heads/feature/s01-x ${sha} refs/heads/develop ${zero}\n`;
  assert.equal(runGate(d, ["pre-push"], { input }), "");
});

test("pre-push refuses ticket feature branch into develop without Ship allowed", () => {
  const d = repo();
  execSync("git checkout -b feature/s01-x/t01-y develop", { cwd: d, stdio: "pipe" });
  writeFileSync(join(d, "code.js"), "1");
  execSync("git add code.js && git commit -m feat", { cwd: d, stdio: "pipe" });
  const sha = execSync("git rev-parse HEAD", { cwd: d, encoding: "utf8" }).trim();
  const zero = "0000000000000000000000000000000000000000";
  const input = `refs/heads/feature/s01-x/t01-y ${sha} refs/heads/develop ${zero}\n`;
  assert.throws(() => runGate(d, ["pre-push"], { input }));
});

test("pre-push allows ticket feature branch into develop with Ship allowed", () => {
  const d = repo();
  mkdirSync(join(d, "docs/reviews/s01-x"), { recursive: true });
  writeFileSync(
    join(d, "docs/reviews/s01-x/t01-y.md"),
    "Max severity: none\nShip allowed: yes\n",
  );
  execSync("git checkout -b feature/s01-x/t01-y develop", { cwd: d, stdio: "pipe" });
  writeFileSync(join(d, "code.js"), "1");
  execSync("git add code.js docs && git commit -m feat", { cwd: d, stdio: "pipe" });
  const sha = execSync("git rev-parse HEAD", { cwd: d, encoding: "utf8" }).trim();
  const zero = "0000000000000000000000000000000000000000";
  const input = `refs/heads/feature/s01-x/t01-y ${sha} refs/heads/develop ${zero}\n`;
  assert.equal(runGate(d, ["pre-push"], { input }), "");
});

test("without develop, feature branch ships straight to main with the same Ship allowed gate", () => {
  const d = repo({ develop: false });
  writeDmConfig(d, { develop: false });
  execSync("git checkout -b feature/s01-x/t01-y main", { cwd: d, stdio: "pipe" });
  writeFileSync(join(d, "code.js"), "1");
  execSync("git add code.js && git commit -m feat", { cwd: d, stdio: "pipe" });
  const sha = execSync("git rev-parse HEAD", { cwd: d, encoding: "utf8" }).trim();
  const zero = "0000000000000000000000000000000000000000";
  const input = `refs/heads/feature/s01-x/t01-y ${sha} refs/heads/main ${zero}\n`;

  assert.throws(() => runGate(d, ["pre-push"], { input }));

  mkdirSync(join(d, "docs/reviews/s01-x"), { recursive: true });
  writeFileSync(
    join(d, "docs/reviews/s01-x/t01-y.md"),
    "Max severity: none\nShip allowed: yes\n",
  );
  execSync("git add docs && git commit -m review", { cwd: d, stdio: "pipe" });
  const sha2 = execSync("git rev-parse HEAD", { cwd: d, encoding: "utf8" }).trim();
  const input2 = `refs/heads/feature/s01-x/t01-y ${sha2} refs/heads/main ${zero}\n`;
  assert.equal(runGate(d, ["pre-push"], { input: input2 }), "");
});

test("AGENTS.md names develop as the optional integration branch and Quick Fix on it", () => {
  const t = readFileSync(AGENTS, "utf8");
  assert.match(t, /\bdevelop\b[\s\S]*integration|integration[\s\S]*\bdevelop\b/i);
  assert.match(t, /"develop"/);
  assert.match(t, /Quick Fix[\s\S]*integration branch/i);
  assert.doesNotMatch(t, /Quick Fix work happens only[\s\S]*on branch\s*`dev`/);
  assert.match(t, /critical or major|critical\s*\*\*or\*\*\s*major/i);
});

test("AGENTS.md lists init docs release, hybrid PRD, child ready, orchestrator modes", () => {
  const t = readFileSync(AGENTS, "utf8");
  assert.match(t, /\/dm-init/);
  assert.match(t, /\/dm-docs/);
  assert.match(t, /\/dm-release/);
  assert.match(t, /PRD → Init → Stories/);
  assert.match(t, /greenfield/i);
  assert.match(t, /Not kill-only/);
  assert.match(t, /child-only|only on child tickets/i);
  assert.match(t, /two modes/);
  assert.match(t, /remaining person-days/);
  assert.match(t, /<< IP Mike/);
});

test("dm-gate.yml resolves the integration branch and gates ticket/framing/release", () => {
  const t = readFileSync(join(ROOT, "src/workflows/dm-gate.yml"), "utf8");
  assert.match(t, /cfg\.develop === false/);
  assert.match(t, /github.head_ref != 'develop'/);
  assert.match(t, /PRs into main must come from develop/);
  assert.match(t, /steps\.cfg\.outputs\.integ/);
  assert.match(t, /Ship allowed: yes/);
  assert.match(t, /docs\/product\//);
  assert.match(t, /docs-only/);
  assert.match(t, /CHANGELOG\.md/);
});

test("dm-gate.yml never interpolates ${{ }} inside a run: block", () => {
  // GitHub substitutes ${{ }} into the script text before bash parses it, so an
  // attacker-controlled branch name like `feature/x$(id)` would execute. Values must
  // reach the shell as env data instead.
  const lines = readFileSync(join(ROOT, "src/workflows/dm-gate.yml"), "utf8").split("\n");
  const offenders = [];
  let inRun = false;
  let runIndent = 0;
  for (const [i, line] of lines.entries()) {
    if (line.trim() === "") continue;
    const indent = line.length - line.trimStart().length;
    if (inRun && indent <= runIndent) inRun = false;
    if (inRun && line.includes("${{")) offenders.push(`${i + 1}: ${line.trim()}`);
    if (/^\s*run:\s*\|/.test(line)) {
      inRun = true;
      runIndent = indent;
    }
  }
  assert.deepEqual(offenders, []);
});

test("dm-gate.yml passes refs to the shell as env vars", () => {
  const t = readFileSync(join(ROOT, "src/workflows/dm-gate.yml"), "utf8");
  assert.match(t, /HEAD_REF: \$\{\{ github\.head_ref \}\}/);
  assert.match(t, /BASE_REF: \$\{\{ github\.base_ref \}\}/);
  assert.match(t, /BASE_SHA: \$\{\{ github\.event\.pull_request\.base\.sha \}\}/);
});

test("ready-ok passes when .dm/config.json is missing", () => {
  const d = repo();
  assert.equal(runGate(d, ["ready-ok", "s01-x/t01-y"]), "");
});

test("ready-ok fails for backlog when config exists", () => {
  const d = repo();
  const { statePath, bin } = withBoard(d, [childIssue("backlog", "opt1")]);
  assert.throws(() =>
    runGate(d, ["ready-ok", "s01-x/t01-y"], {
      env: { PATH: `${bin}:${process.env.PATH}`, DM_GH_STUB_STATE: statePath },
    }),
  );
});

test("ready-ok passes for ready and in progress", () => {
  for (const [name, opt] of [
    ["ready", "opt2"],
    ["in progress", "opt3"],
  ]) {
    const d = repo();
    const { statePath, bin } = withBoard(d, [childIssue(name, opt)]);
    assert.equal(
      runGate(d, ["ready-ok", "s01-x/t01-y"], {
        env: { PATH: `${bin}:${process.env.PATH}`, DM_GH_STUB_STATE: statePath },
      }),
      "",
    );
  }
});

test("pre-commit blocks code on ticket branch when board status is backlog", () => {
  const d = repo();
  const { statePath, bin } = withBoard(d, [childIssue("backlog", "opt1")]);
  writeValidatedPlan(d);
  execSync("git checkout -b feature/s01-x/t01-y develop", { cwd: d, stdio: "pipe" });
  stageCode(d);
  assert.throws(() =>
    runGate(d, ["pre-commit"], {
      env: { PATH: `${bin}:${process.env.PATH}`, DM_GH_STUB_STATE: statePath },
    }),
  );
});

test("pre-commit allows code on ticket branch when board status is ready", () => {
  const d = repo();
  const { statePath, bin } = withBoard(d, [childIssue("ready", "opt2")]);
  writeValidatedPlan(d);
  execSync("git checkout -b feature/s01-x/t01-y develop", { cwd: d, stdio: "pipe" });
  stageCode(d);
  assert.equal(
    runGate(d, ["pre-commit"], {
      env: { PATH: `${bin}:${process.env.PATH}`, DM_GH_STUB_STATE: statePath },
    }),
    "",
  );
});

test("pre-commit allows docs-only even when board status is backlog", () => {
  const d = repo();
  const { statePath, bin } = withBoard(d, [childIssue("backlog", "opt1")]);
  execSync("git checkout -b feature/s01-x/t01-y develop", { cwd: d, stdio: "pipe" });
  mkdirSync(join(d, "docs/notes"), { recursive: true });
  writeFileSync(join(d, "docs/notes/x.md"), "note");
  execSync("git add docs", { cwd: d, stdio: "pipe" });
  assert.equal(
    runGate(d, ["pre-commit"], {
      env: { PATH: `${bin}:${process.env.PATH}`, DM_GH_STUB_STATE: statePath },
    }),
    "",
  );
});

test("pre-commit allows code without config (board not initialized) when plan validated", () => {
  const d = repo();
  writeValidatedPlan(d);
  execSync("git checkout -b feature/s01-x/t01-y develop", { cwd: d, stdio: "pipe" });
  stageCode(d);
  assert.equal(runGate(d, ["pre-commit"]), "");
});

test("pre-commit refuses code on story framing branch", () => {
  const d = repo();
  writeValidatedPlan(d);
  execSync("git checkout -b feature/s01-x develop", { cwd: d, stdio: "pipe" });
  stageCode(d);
  assert.throws(() => runGate(d, ["pre-commit"]));
});
