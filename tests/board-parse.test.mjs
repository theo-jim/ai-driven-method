import { execFileSync, spawnSync } from "node:child_process";
import {
  mkdtempSync,
  writeFileSync,
  chmodSync,
  mkdirSync,
  readFileSync,
  existsSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BOARD = join(ROOT, "src/lib/dm-board.sh");
const INIT = join(ROOT, "src/lib/dm-init.sh");
const GH_STUB = join(ROOT, "tests/fixtures/gh-stub.sh");

const CONFIG = {
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

function appDir(issues) {
  const d = mkdtempSync(join(tmpdir(), "board-"));
  mkdirSync(join(d, ".dm"), { recursive: true });
  writeFileSync(join(d, ".dm/config.json"), JSON.stringify(CONFIG, null, 2));
  const statePath = join(d, "gh-state.json");
  writeFileSync(
    statePath,
    JSON.stringify(
      {
        issues,
        status_option_ids: CONFIG.status_option_ids,
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
  chmodSync(BOARD, 0o755);
  return { d, statePath, bin };
}

function runBoard(d, bin, statePath, args) {
  return execFileSync("bash", [BOARD, ...args], {
    cwd: d,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      DM_GH_STUB_STATE: statePath,
    },
  });
}

test("status-get returns ready for child issue", () => {
  const { d, statePath, bin } = appDir([
    {
      title: "[s01-x/t01-y] Persist (M, 1.5d)",
      number: 2,
      projectItems: [
        { id: "PVTI_2", status: { optionId: "opt2", name: "ready" } },
      ],
    },
  ]);
  const out = runBoard(d, bin, statePath, ["status-get", "s01-x/t01-y"]).trim();
  assert.equal(out, "ready");
});

test("require-ready succeeds for ready", () => {
  const { d, statePath, bin } = appDir([
    {
      title: "[s01-x/t01-y] Persist (M, 1.5d)",
      number: 2,
      projectItems: [
        { id: "PVTI_2", status: { optionId: "opt2", name: "ready" } },
      ],
    },
  ]);
  assert.equal(
    runBoard(d, bin, statePath, ["require-ready", "s01-x/t01-y"]).trim(),
    "",
  );
});

test("require-ready succeeds for in progress", () => {
  const { d, statePath, bin } = appDir([
    {
      title: "[s01-x/t01-y] Persist (M, 1.5d)",
      number: 2,
      projectItems: [
        { id: "PVTI_2", status: { optionId: "opt3", name: "in progress" } },
      ],
    },
  ]);
  assert.equal(
    runBoard(d, bin, statePath, ["require-ready", "s01-x/t01-y"]).trim(),
    "",
  );
});

test("require-ready fails for backlog", () => {
  const { d, statePath, bin } = appDir([
    {
      title: "[s01-x/t01-y] Persist (M, 1.5d)",
      number: 2,
      projectItems: [
        { id: "PVTI_2", status: { optionId: "opt1", name: "backlog" } },
      ],
    },
  ]);
  assert.throws(() =>
    runBoard(d, bin, statePath, ["require-ready", "s01-x/t01-y"]),
  );
});

test("require-ready fails when issue missing", () => {
  const { d, statePath, bin } = appDir([]);
  assert.throws(() =>
    runBoard(d, bin, statePath, ["require-ready", "s01-x/t01-y"]),
  );
});

test("require-ready rejects parent-only key", () => {
  const { d, statePath, bin } = appDir([
    {
      title: "[s01-x] Parent",
      number: 1,
      projectItems: [
        { id: "PVTI_1", status: { optionId: "opt2", name: "ready" } },
      ],
    },
  ]);
  assert.throws(() => runBoard(d, bin, statePath, ["require-ready", "s01-x"]));
});

test("parent-sync sets test when all children test/shipped", () => {
  const { d, statePath, bin } = appDir([
    {
      title: "[s01-x] Parent US",
      number: 1,
      projectItems: [
        { id: "PVTI_1", status: { optionId: "opt3", name: "in progress" } },
      ],
    },
    {
      title: "[s01-x/t01-a] A (S, 1d)",
      number: 2,
      projectItems: [
        { id: "PVTI_2", status: { optionId: "opt4", name: "test" } },
      ],
    },
    {
      title: "[s01-x/t02-b] B (M, 1.5d)",
      number: 3,
      projectItems: [
        { id: "PVTI_3", status: { optionId: "opt5", name: "shipped" } },
      ],
    },
  ]);
  runBoard(d, bin, statePath, ["parent-sync", "s01-x"]);
  const state = JSON.parse(readFileSync(statePath, "utf8"));
  const parent = state.issues.find((i) => i.number === 1);
  assert.equal(parent.projectItems[0].status.name, "test");
});

test("init assert-status-ids passes when all five present", () => {
  chmodSync(INIT, 0o755);
  const json = JSON.stringify({
    backlog: "opt1",
    ready: "opt2",
    "in progress": "opt3",
    test: "opt4",
    shipped: "opt5",
  });
  assert.equal(
    execFileSync("bash", [INIT, "assert-status-ids", json], {
      encoding: "utf8",
    }).trim(),
    "",
  );
});

test("init assert-status-ids fails when any status id missing", () => {
  chmodSync(INIT, 0o755);
  const incomplete = JSON.stringify({
    backlog: "opt1",
    ready: "opt2",
    test: "opt4",
    shipped: "opt5",
  });
  assert.throws(() =>
    execFileSync("bash", [INIT, "assert-status-ids", incomplete], {
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    }),
  );
});

test("issue-create-ticket writes Parent and ticket label when sub-issue fails", () => {
  const { d, statePath, bin } = appDir([
    {
      title: "[s01-x] Parent US",
      number: 1,
      id: "I_parent",
      projectItems: [
        { id: "PVTI_1", status: { optionId: "opt1", name: "backlog" } },
      ],
    },
  ]);
  const state = JSON.parse(readFileSync(statePath, "utf8"));
  state.subissue_fail = true;
  writeFileSync(statePath, JSON.stringify(state, null, 2));
  const body = join(d, "body.md");
  writeFileSync(body, "ticket body\n");
  runBoard(d, bin, statePath, [
    "issue-create-ticket",
    "s01-x",
    "t01-y",
    "Persist",
    body,
  ]);
  const after = JSON.parse(readFileSync(statePath, "utf8"));
  const child = after.issues.find((i) =>
    (i.title || "").startsWith("[s01-x/t01-y]"),
  );
  assert.ok(child, "child issue created");
  assert.match(child.body || "", /Parent: #1/);
  assert.ok((child.labels || []).includes("ticket"));
});

test("issue-create-ticket with story_id 'fix' creates a standalone item and skips parent-linking", () => {
  const { d, statePath, bin } = appDir([]);
  const body = join(d, "body.md");
  writeFileSync(body, "fix body\n");
  runBoard(d, bin, statePath, [
    "issue-create-ticket",
    "fix",
    "null-cart-crash",
    "Null cart crash",
    body,
  ]);
  const after = JSON.parse(readFileSync(statePath, "utf8"));
  const issue = after.issues.find((i) =>
    (i.title || "").startsWith("[fix/null-cart-crash]"),
  );
  assert.ok(issue, "fix issue created");
  assert.equal(issue.title, "[fix/null-cart-crash] Null cart crash");
  assert.doesNotMatch(issue.body || "", /Parent:/);
  assert.ok(!(issue.labels || []).includes("ticket"));
});

test("issue-create-ticket with story_id 'fix' stays standalone even when an issue titled exactly '[fix]' exists", () => {
  const { d, statePath, bin } = appDir([
    { title: "[fix]", number: 5, id: "I_fix_exact", projectItems: [] },
  ]);
  const body = join(d, "body.md");
  writeFileSync(body, "fix body\n");
  runBoard(d, bin, statePath, [
    "issue-create-ticket",
    "fix",
    "null-cart-crash",
    "Null cart crash",
    body,
  ]);
  const after = JSON.parse(readFileSync(statePath, "utf8"));
  const issue = after.issues.find((i) =>
    (i.title || "").startsWith("[fix/null-cart-crash]"),
  );
  assert.ok(issue, "fix issue created");
  assert.equal(issue.title, "[fix/null-cart-crash] Null cart crash");
  assert.doesNotMatch(issue.body || "", /Parent:/);
  assert.ok(!(issue.labels || []).includes("ticket"));
  assert.equal(after.graphql_calls || 0, 0, "addSubIssue must never be called for a fix ticket");
});

test("issue-create-ticket with story_id 'fix' stays standalone even when an issue titled '[fix] Legacy tracking' exists", () => {
  const { d, statePath, bin } = appDir([
    { title: "[fix] Legacy tracking", number: 6, id: "I_fix_legacy", projectItems: [] },
  ]);
  const body = join(d, "body.md");
  writeFileSync(body, "fix body\n");
  runBoard(d, bin, statePath, [
    "issue-create-ticket",
    "fix",
    "null-cart-crash",
    "Null cart crash",
    body,
  ]);
  const after = JSON.parse(readFileSync(statePath, "utf8"));
  const issue = after.issues.find((i) =>
    (i.title || "").startsWith("[fix/null-cart-crash]"),
  );
  assert.ok(issue, "fix issue created");
  assert.equal(issue.title, "[fix/null-cart-crash] Null cart crash");
  assert.doesNotMatch(issue.body || "", /Parent:/);
  assert.ok(!(issue.labels || []).includes("ticket"));
  assert.equal(after.graphql_calls || 0, 0, "addSubIssue must never be called for a fix ticket");
});

test("item-add is retried once", () => {
  const { d, statePath, bin } = appDir([]);
  const state = JSON.parse(readFileSync(statePath, "utf8"));
  state.item_add_fail_remaining = 1;
  writeFileSync(statePath, JSON.stringify(state, null, 2));
  const body = join(d, "body.md");
  writeFileSync(body, "us body\n");
  runBoard(d, bin, statePath, ["issue-create-us", "s01-x", "Parent", body]);
  const after = JSON.parse(readFileSync(statePath, "utf8"));
  assert.equal(after.item_add_calls, 2);
  assert.equal(after.item_add_fail_remaining, 0);
});

function gitInitRepo(d) {
  execFileSync("git", ["init", "-b", "main"], { cwd: d, stdio: "pipe" });
  execFileSync("git", ["config", "user.email", "t@t"], { cwd: d, stdio: "pipe" });
  execFileSync("git", ["config", "user.name", "t"], { cwd: d, stdio: "pipe" });
  writeFileSync(join(d, "README.md"), "x\n");
  execFileSync("git", ["add", "README.md"], { cwd: d, stdio: "pipe" });
  execFileSync("git", ["commit", "-m", "i"], { cwd: d, stdio: "pipe" });
}

test("dm-init --no-remote does not call gh api for wiki or rulesets", () => {
  const d = mkdtempSync(join(tmpdir(), "init-noremote-"));
  gitInitRepo(d);
  mkdirSync(join(d, ".dm"), { recursive: true });
  writeFileSync(join(d, ".dm/config.json"), JSON.stringify(CONFIG, null, 2));
  const log = join(d, "gh-log.txt");
  const bin = join(d, "bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(
    join(bin, "gh"),
    `#!/bin/sh
echo "$@" >> "${log}"
case "$*" in
  *"has_wiki"*|*"branches/"*"/protection"*|*"rulesets"*)
    echo "dm-init --no-remote must not call wiki/ruleset gh api: $*" >&2
    exit 7
    ;;
esac
exit 0
`,
  );
  chmodSync(join(bin, "gh"), 0o755);
  chmodSync(INIT, 0o755);
  execFileSync(
    "bash",
    [INIT, "run", "--yes", "--no-remote", "--owner", "acme", "--repo", "app"],
    {
      cwd: d,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
    },
  );
  const logged = existsSync(log) ? readFileSync(log, "utf8") : "";
  assert.doesNotMatch(logged, /has_wiki|protection|rulesets/);
});

test("dm-init warns when branch protection fails", () => {
  const d = mkdtempSync(join(tmpdir(), "init-prot-"));
  gitInitRepo(d);
  execFileSync("git", ["remote", "add", "origin", "git@github.com:acme/app.git"], {
    cwd: d,
    stdio: "pipe",
  });
  mkdirSync(join(d, ".dm"), { recursive: true });
  writeFileSync(join(d, ".dm/config.json"), JSON.stringify(CONFIG, null, 2));
  const log = join(d, "gh-log.txt");
  const bin = join(d, "bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(
    join(bin, "gh"),
    `#!/bin/sh
echo "$@" >> "${log}"
case "$*" in
  *"branches/"*"/protection"*)
    echo '{"message":"not allowed"}' >&2
    exit 1
    ;;
  *"rulesets"*)
    echo "[]" >&2
    exit 1
    ;;
  *"-q .node_id"*)
    echo "REPO_NODE"
    exit 0
    ;;
  *"has_wiki"*)
    exit 0
    ;;
esac
exit 0
`,
  );
  chmodSync(join(bin, "gh"), 0o755);
  chmodSync(INIT, 0o755);
  const res = spawnSync(
    "bash",
    [INIT, "run", "--yes", "--owner", "acme", "--repo", "app"],
    {
      cwd: d,
      encoding: "utf8",
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
    },
  );
  assert.equal(res.status, 0, res.stderr);
  assert.match(res.stderr, /WARNING:.*NOT protected/i);
});

test("dm-wiki clones with gh credentials", () => {
  const t = readFileSync(join(ROOT, "src/lib/dm-wiki.sh"), "utf8");
  assert.match(t, /gh auth token/);
  assert.match(t, /GH_TOKEN/);
  assert.match(t, /gh auth setup-git/);
  assert.match(t, /x-access-token/);
});

test("dm-wiki keeps the token out of argv and of .git/config", () => {
  // A token embedded in the clone URL is visible in `ps` to any local user, and
  // `git remote add` writes it to disk. Pass it through a credential helper env var.
  const t = readFileSync(join(ROOT, "src/lib/dm-wiki.sh"), "utf8");
  assert.doesNotMatch(t, /https:\/\/x-access-token:\$\{?token/);
  assert.match(t, /credential\.helper/);
  assert.match(t, /DM_WIKI_TOKEN/);
  // `-c credential.helper=X` appends to the helper list; an empty value first is
  // what resets it, so an ambient helper (keychain, gh) cannot answer instead.
  assert.match(t, /credential\.helper=" \\/);
  assert.match(t, /--replace-all credential\.helper ""/);
});

test("issue-adopt renames a hand-written issue and puts it on the board", () => {
  const { d, statePath, bin } = appDir([
    { title: "Export CSV", number: 7, id: "I_7", projectItems: [] },
  ]);
  runBoard(d, bin, statePath, ["issue-adopt", "s03-export-csv", "7", "Export CSV"]);
  const s = JSON.parse(readFileSync(statePath, "utf8"));
  const issue = s.issues.find((i) => i.number === 7);
  assert.equal(issue.title, "[s03-export-csv] Export CSV");
  assert.equal(s.item_add_calls, 1);
});
