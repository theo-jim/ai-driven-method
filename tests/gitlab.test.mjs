import { execFileSync, spawnSync } from "node:child_process";
import {
  mkdtempSync,
  writeFileSync,
  chmodSync,
  mkdirSync,
  readFileSync,
  existsSync,
  cpSync,
  symlinkSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const LIB = join(ROOT, "src/lib");
const BOARD = join(LIB, "dm-board.sh");
const INIT = join(LIB, "dm-init.sh");
const VCS = join(LIB, "dm-vcs.sh");
const WIKI = join(LIB, "dm-wiki.sh");
const GATE = join(ROOT, "src/hooks/dm-gate.sh");
const GLAB_STUB = join(ROOT, "tests/fixtures/glab-stub.sh");

const STATUS_LABELS = {
  backlog: "dm::backlog",
  ready: "dm::ready",
  "in progress": "dm::in progress",
  test: "dm::test",
  shipped: "dm::shipped",
};

const CONFIG = {
  platform: "gitlab",
  host: "gitlab.example.com",
  owner: "acme/team",
  repo: "app",
  board_id: 900,
  status_labels: STATUS_LABELS,
};

function git(cwd, ...args) {
  return execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8" });
}

function gitRepo(d) {
  git(d, "init", "-b", "main");
  git(d, "config", "user.email", "t@t");
  git(d, "config", "user.name", "t");
  writeFileSync(join(d, "README.md"), "x\n");
  git(d, "add", "README.md");
  git(d, "commit", "-m", "i");
}

// App dir with .dm/config.json, a glab stub on PATH, and its state file.
function glabApp(state = {}, config = CONFIG) {
  const d = mkdtempSync(join(tmpdir(), "gitlab-"));
  if (config) {
    mkdirSync(join(d, ".dm"), { recursive: true });
    writeFileSync(join(d, ".dm/config.json"), JSON.stringify(config, null, 2));
  }
  const statePath = join(d, "glab-state.json");
  const project = config ? `${config.owner}/${config.repo}` : "acme/app";
  writeFileSync(statePath, JSON.stringify({ issues: [], mrs: [], project, ...state }, null, 2));
  const bin = join(d, "bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(join(bin, "glab"), readFileSync(GLAB_STUB));
  chmodSync(join(bin, "glab"), 0o755);
  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    DM_GLAB_STUB_STATE: statePath,
    GITLAB_HOST: "",
  };
  delete env.GITLAB_HOST;
  return { d, statePath, bin, env };
}

const readState = (p) => JSON.parse(readFileSync(p, "utf8"));

function run(script, app, args, extra = {}) {
  return execFileSync("bash", [script, ...args], {
    cwd: app.d,
    encoding: "utf8",
    stdio: ["pipe", "pipe", "pipe"],
    env: { ...app.env, ...extra },
  });
}

function runRes(script, app, args, extra = {}) {
  return spawnSync("bash", [script, ...args], {
    cwd: app.d,
    encoding: "utf8",
    env: { ...app.env, ...extra },
  });
}

const issue = (iid, title, labels = []) => ({ iid, id: 100 + iid, title, labels, description: "" });

// --- platform detection -----------------------------------------------------

test("detect maps remote URLs to github or gitlab", () => {
  const cases = [
    ["git@github.com:acme/app.git", "github"],
    ["https://github.com/acme/app", "github"],
    ["git@gitlab.com:acme/team/app.git", "gitlab"],
    ["https://gitlab.com/acme/app.git", "gitlab"],
    ["https://gitlab.example.com/acme/app.git", "gitlab"],
    ["ssh://git@code.gitlab.acme.io:2222/acme/app.git", "gitlab"],
  ];
  for (const [url, want] of cases) {
    const out = execFileSync("bash", [VCS, "detect", url], { encoding: "utf8" }).trim();
    assert.equal(out, want, url);
  }
});

test("detect fails closed on a host it cannot place", () => {
  const res = spawnSync("bash", [VCS, "detect", "git@git.acme.io:acme/app.git"], { encoding: "utf8" });
  assert.notEqual(res.status, 0);
});

test("platform: config field wins, then origin, then github", () => {
  const withCfg = glabApp({}, { ...CONFIG });
  assert.equal(run(VCS, withCfg, ["platform"]).trim(), "gitlab");

  const fromOrigin = glabApp({}, null);
  gitRepo(fromOrigin.d);
  git(fromOrigin.d, "remote", "add", "origin", "git@gitlab.com:acme/app.git");
  assert.equal(run(VCS, fromOrigin, ["platform"]).trim(), "gitlab");
  assert.equal(run(VCS, fromOrigin, ["cli"]).trim(), "glab");

  const bare = glabApp({}, null);
  assert.equal(run(VCS, bare, ["platform"]).trim(), "github");

  const legacy = glabApp({}, { owner: "acme", repo: "app" });
  gitRepo(legacy.d);
  git(legacy.d, "remote", "add", "origin", "git@gitlab.com:acme/app.git");
  // A config without "platform" is a GitHub project that predates GitLab support.
  assert.equal(run(VCS, legacy, ["platform"]).trim(), "github");
});

test("platform refuses an unknown value in .dm/config.json", () => {
  const app = glabApp({}, { ...CONFIG, platform: "bitbucket" });
  assert.notEqual(runRes(VCS, app, ["platform"]).status, 0);
});

test("dm-config requires status_labels on gitlab", () => {
  const { status_labels, ...noLabels } = CONFIG;
  void status_labels;
  const app = glabApp({ issues: [issue(2, "[s01-x/t01-y] P", ["dm::ready"])] }, noLabels);
  const res = runRes(BOARD, app, ["status-get", "s01-x/t01-y"]);
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /status_labels required/);
});

// --- board ------------------------------------------------------------------

test("gitlab status-get reads the status label", () => {
  const app = glabApp({ issues: [issue(2, "[s01-x/t01-y] Persist", ["ticket", "dm::ready"])] });
  assert.equal(run(BOARD, app, ["status-get", "s01-x/t01-y"]).trim(), "ready");
  const call = readState(app.statePath).calls[0].join(" ");
  assert.match(call, /projects\/acme%2Fteam%2Fapp\/issues\?state=all/);
});

test("gitlab require-ready passes on ready / in progress, fails otherwise", () => {
  for (const [label, ok] of [
    ["dm::ready", true],
    ["dm::in progress", true],
    ["dm::backlog", false],
    ["dm::test", false],
  ]) {
    const app = glabApp({ issues: [issue(2, "[s01-x/t01-y] P", [label])] });
    const res = runRes(BOARD, app, ["require-ready", "s01-x/t01-y"]);
    assert.equal(res.status === 0, ok, label);
  }
});

test("gitlab require-ready fails closed on no status label and on two", () => {
  for (const labels of [[], ["dm::ready", "dm::test"]]) {
    const app = glabApp({ issues: [issue(2, "[s01-x/t01-y] P", labels)] });
    assert.notEqual(runRes(BOARD, app, ["require-ready", "s01-x/t01-y"]).status, 0, labels.join());
  }
});

test("gitlab status-set keeps exactly one status label and the others untouched", () => {
  const app = glabApp({
    issues: [issue(2, "[s01-x/t01-y] P", ["ticket", "dm::ready", "dm::backlog"])],
  });
  run(BOARD, app, ["status-set", "s01-x/t01-y", "in progress"]);
  const labels = readState(app.statePath).issues[0].labels;
  assert.deepEqual(labels.sort(), ["dm::in progress", "ticket"]);
});

test("gitlab status-set refuses ready on a parent", () => {
  const app = glabApp({ issues: [issue(1, "[s01-x] Parent", ["dm::backlog"])] });
  assert.notEqual(runRes(BOARD, app, ["status-set", "s01-x", "ready"]).status, 0);
});

test("gitlab parent-sync derives the parent label from its children", () => {
  const app = glabApp({
    issues: [
      issue(1, "[s01-x] Parent", ["dm::in progress"]),
      issue(2, "[s01-x/t01-a] A", ["dm::test"]),
      issue(3, "[s01-x/t02-b] B", ["dm::shipped"]),
    ],
  });
  assert.equal(run(BOARD, app, ["parent-sync", "s01-x"]).trim(), "test");
  const parent = readState(app.statePath).issues.find((i) => i.iid === 1);
  assert.deepEqual(parent.labels, ["dm::test"]);
});

test("gitlab issue-create-us creates the Issue in backlog and prints its number", () => {
  const app = glabApp();
  const body = join(app.d, "body.md");
  writeFileSync(body, "us body\n");
  const out = run(BOARD, app, ["issue-create-us", "s01-x", "Submit", body]).trim();
  assert.equal(out, "1");
  const created = readState(app.statePath).issues[0];
  assert.equal(created.title, "[s01-x] Submit");
  assert.match(created.description, /us body/);
  assert.deepEqual(created.labels, ["dm::backlog"]);
});

test("gitlab issue-create-ticket links the child to its parent", () => {
  const app = glabApp({ issues: [issue(1, "[s01-x] Parent", ["dm::backlog"])] });
  const body = join(app.d, "body.md");
  writeFileSync(body, "ticket body\n");
  assert.equal(run(BOARD, app, ["issue-create-ticket", "s01-x", "t01-y", "Persist", body]).trim(), "2");
  const s = readState(app.statePath);
  assert.deepEqual(s.links, [{ parent: 1, child: 2, target_project_id: "acme/team/app" }]);
  assert.doesNotMatch(s.issues[1].description, /Parent: #1/);
});

test("gitlab issue-create-ticket falls back to Parent: #n + ticket label when linking fails", () => {
  const app = glabApp({ issues: [issue(1, "[s01-x] Parent", ["dm::backlog"])], fail: ["/links"] });
  const body = join(app.d, "body.md");
  writeFileSync(body, "ticket body\n");
  const res = runRes(BOARD, app, ["issue-create-ticket", "s01-x", "t01-y", "Persist", body]);
  assert.equal(res.status, 0, res.stderr);
  assert.match(res.stderr, /WARNING: sub-issue link failed/);
  const child = readState(app.statePath).issues.find((i) => i.iid === 2);
  assert.match(child.description, /Parent: #1/);
  assert.ok(child.labels.includes("ticket"));
  assert.ok(child.labels.includes("dm::backlog"));
});

test("gitlab issue-adopt renames a hand-written Issue and boards it", () => {
  const app = glabApp({ issues: [issue(7, "Export CSV", ["bug"])] });
  run(BOARD, app, ["issue-adopt", "s03-export-csv", "7", "Export CSV"]);
  const adopted = readState(app.statePath).issues[0];
  assert.equal(adopted.title, "[s03-export-csv] Export CSV");
  assert.deepEqual(adopted.labels.sort(), ["bug", "dm::backlog"]);
});

test("gitlab board talks to the configured self-hosted instance", () => {
  const app = glabApp({ issues: [issue(2, "[s01-x/t01-y] P", ["dm::ready"])] });
  const bin = app.bin;
  writeFileSync(
    join(bin, "glab"),
    `#!/bin/sh\necho "$GITLAB_HOST" >> "${join(app.d, "hosts.txt")}"\nexec "${join(bin, "glab-real")}" "$@"\n`,
  );
  writeFileSync(join(bin, "glab-real"), readFileSync(GLAB_STUB));
  chmodSync(join(bin, "glab"), 0o755);
  chmodSync(join(bin, "glab-real"), 0o755);
  run(BOARD, app, ["status-get", "s01-x/t01-y"]);
  assert.match(readFileSync(join(app.d, "hosts.txt"), "utf8"), /^gitlab\.example\.com$/m);
});

test("dm-board fails closed when dm-board-gitlab.sh is missing", () => {
  const app = glabApp({ issues: [issue(2, "[s01-x/t01-y] P", ["dm::ready"])] });
  mkdirSync(join(app.d, "lib"));
  for (const n of ["dm-board.sh", "dm-config.sh"]) cpSync(join(LIB, n), join(app.d, "lib", n));
  const res = runRes(join(app.d, "lib/dm-board.sh"), app, ["require-ready", "s01-x/t01-y"]);
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /dm-board-gitlab\.sh is missing/);
});

test("pre-commit ready gate reads the GitLab board", () => {
  for (const [label, ok] of [["dm::ready", true], ["dm::backlog", false]]) {
    const app = glabApp({ issues: [issue(2, "[s01-x/t01-y] P", [label])] });
    gitRepo(app.d);
    mkdirSync(join(app.d, ".dm/lib"), { recursive: true });
    cpSync(LIB, join(app.d, ".dm/lib"), { recursive: true });
    mkdirSync(join(app.d, "docs/plans"), { recursive: true });
    writeFileSync(join(app.d, "docs/plans/s01-x.md"), "---\nvalidated: yes\n---\n");
    git(app.d, "checkout", "-b", "feature/s01-x/t01-y");
    writeFileSync(join(app.d, "code.js"), "1");
    git(app.d, "add", "code.js");
    const res = runRes(GATE, app, ["pre-commit"]);
    assert.equal(res.status === 0, ok, `${label}: ${res.stderr}`);
  }
});

// --- merge requests -------------------------------------------------------

test("gitlab pr-create opens a merge request and prints its URL", () => {
  const app = glabApp();
  const body = join(app.d, "mr.md");
  writeFileSync(body, "what / why / how to test\n");
  const url = run(VCS, app, ["pr-create", "develop", "feature/s01-x/t01-y", "s01-x/t01-y: Persist", body]).trim();
  assert.equal(url, "https://gitlab.example.com/acme/team/app/-/merge_requests/1");
  const mr = readState(app.statePath).mrs[0];
  assert.equal(mr.target_branch, "develop");
  assert.equal(mr.source_branch, "feature/s01-x/t01-y");
  assert.match(mr.description, /how to test/);
});

test("gitlab pr-state normalizes to OPEN / MERGED / CLOSED", () => {
  const app = glabApp({
    mrs: [
      { iid: 1, source_branch: "feature/a/t1", target_branch: "develop", state: "opened" },
      { iid: 2, source_branch: "feature/a/t2", target_branch: "develop", state: "merged" },
      { iid: 3, source_branch: "feature/a/t3", target_branch: "develop", state: "closed" },
    ],
  });
  assert.equal(run(VCS, app, ["pr-state", "feature/a/t1"]).trim(), "OPEN");
  assert.equal(run(VCS, app, ["pr-state", "feature/a/t2"]).trim(), "MERGED");
  assert.equal(run(VCS, app, ["pr-state", "3"]).trim(), "CLOSED");
  assert.notEqual(runRes(VCS, app, ["pr-state", "feature/none"]).status, 0);
});

test("gitlab pr-merge squashes now and keeps the source branch despite a delete-by-default project", () => {
  const app = glabApp({
    mrs: [{ iid: 4, source_branch: "feature/a/t1", target_branch: "develop", state: "opened", force_remove_source_branch: true }],
    branches: ["feature/a/t1"],
  });
  run(VCS, app, ["pr-merge", "feature/a/t1"]);
  const s = readState(app.statePath);
  assert.equal(s.mrs[0].state, "merged");
  assert.equal(s.mrs[0].force_remove_source_branch, false);
  assert.equal(s.mrs[0].merge_fields.squash, "true");
  assert.equal(s.mrs[0].merge_fields.should_remove_source_branch, "false");
  assert.deepEqual(s.branches, ["feature/a/t1"]);
  assert.doesNotMatch(s.calls.map((c) => c.join(" ")).join("\n"), /merge_when_pipeline_succeeds|auto-merge/);
});

test("gitlab pr-merge fails loudly when the source branch is gone after the merge", () => {
  const app = glabApp({
    mrs: [{ iid: 4, source_branch: "feature/a/t1", target_branch: "develop", state: "opened" }],
    branches: ["feature/a/t1"],
    delete_on_merge_anyway: true,
  });
  const res = runRes(VCS, app, ["pr-merge", "4"]);
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /merged but source branch 'feature\/a\/t1' is gone/);
});

test("gitlab pr-merge does not merge when it cannot clear delete-source-branch", () => {
  const app = glabApp({
    mrs: [{ iid: 4, source_branch: "feature/a/t1", target_branch: "develop", state: "opened" }],
    branches: ["feature/a/t1"],
    fail: ["merge_requests/4 -F remove_source_branch"],
  });
  assert.notEqual(runRes(VCS, app, ["pr-merge", "4"]).status, 0);
  assert.equal(readState(app.statePath).mrs[0].state, "opened");
});

test("gitlab pr-open-heads lists open merge requests into a base", () => {
  const app = glabApp({
    mrs: [
      { iid: 1, source_branch: "release/v1.2.0", target_branch: "main", state: "opened" },
      { iid: 2, source_branch: "develop", target_branch: "main", state: "merged" },
      { iid: 3, source_branch: "feature/a/t1", target_branch: "develop", state: "opened" },
    ],
  });
  const out = run(VCS, app, ["pr-open-heads", "main"]).trim();
  assert.equal(out, "release/v1.2.0\thttps://gitlab.example.com/acme/team/app/-/merge_requests/1");
});

test("gitlab issue-list and issue-body-set", () => {
  const app = glabApp({ issues: [issue(3, "Export CSV", ["bug"])] });
  const list = JSON.parse(run(VCS, app, ["issue-list", "open"]));
  assert.deepEqual(list, [{ number: 3, title: "Export CSV", labels: ["bug"] }]);
  const body = join(app.d, "b.md");
  writeFileSync(body, "Estimate: 3d\n");
  run(VCS, app, ["issue-body-set", "3", body]);
  assert.match(readState(app.statePath).issues[0].description, /Estimate: 3d/);
});

test("github pr-* keep the gh commands", () => {
  const d = mkdtempSync(join(tmpdir(), "vcs-gh-"));
  const bin = join(d, "bin");
  mkdirSync(bin);
  const log = join(d, "gh.log");
  writeFileSync(
    join(bin, "gh"),
    `#!/bin/sh\necho "$@" >> "${log}"\ncase "$*" in *"pr view"*) echo MERGED ;; *"pr create"*) echo https://github.com/acme/app/pull/9 ;; esac\n`,
  );
  chmodSync(join(bin, "gh"), 0o755);
  writeFileSync(join(d, "b.md"), "x");
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH}` };
  const opts = { cwd: d, encoding: "utf8", env };
  assert.equal(
    execFileSync("bash", [VCS, "pr-create", "develop", "feature/a/t1", "T", "b.md"], opts).trim(),
    "https://github.com/acme/app/pull/9",
  );
  assert.equal(execFileSync("bash", [VCS, "pr-state", "feature/a/t1"], opts).trim(), "MERGED");
  execFileSync("bash", [VCS, "pr-merge", "feature/a/t1"], opts);
  const logged = readFileSync(log, "utf8");
  assert.match(logged, /^pr create --base develop --head feature\/a\/t1 --title T --body-file b\.md$/m);
  assert.match(logged, /^pr view feature\/a\/t1 --json state --jq \.state$/m);
  assert.match(logged, /^pr merge feature\/a\/t1 --squash --delete-branch=false$/m);
});

// --- init -----------------------------------------------------------------

// Redirect origin pushes to a local bare repo so no test touches the network.
function initApp(state = {}, origin = "git@gitlab.com:acme/app.git") {
  const app = glabApp({ user: "acme", ...state }, null);
  gitRepo(app.d);
  if (origin) git(app.d, "remote", "add", "origin", origin);
  const bare = join(app.d, "remote");
  for (const ns of ["acme", "acme-org"]) {
    mkdirSync(join(bare, ns), { recursive: true });
    git(join(bare, ns), "init", "--bare", "app.git");
    // Model GitLab's receive side: "push: No one" (push_access_level 0) refuses the push.
    const hook = join(bare, ns, "app.git/hooks/pre-receive");
    writeFileSync(
      hook,
      `#!/bin/sh
while read old new ref; do
  node -e '
    const s = JSON.parse(require("fs").readFileSync(process.env.DM_GLAB_STUB_STATE, "utf8"));
    const p = (s.protections || {})[process.argv[1]];
    if (s.reject_pushes || (p && String(p.push_access_level) === "0")) process.exit(1);
  ' "\${ref#refs/heads/}" || { echo "GitLab: You are not allowed to push code to protected branches on this project." >&2; exit 1; }
done
`,
    );
    chmodSync(hook, 0o755);
  }
  const prefixes = ["git@gitlab.com:", "https://gitlab.com/", "git@git.acme.io:"];
  app.env = { ...app.env, GIT_CONFIG_COUNT: String(prefixes.length) };
  prefixes.forEach((p, i) => {
    app.env[`GIT_CONFIG_KEY_${i}`] = `url.file://${bare}/.pushInsteadOf`;
    app.env[`GIT_CONFIG_VALUE_${i}`] = p;
  });
  return app;
}

test("dm-init on a gitlab origin protects branches, labels the board and writes a gitlab config", () => {
  const app = initApp({ protected: ["main"] });
  const res = runRes(INIT, app, ["run", "--yes"]);
  assert.equal(res.status, 0, res.stderr);
  const s = readState(app.statePath);
  assert.deepEqual(s.protected.sort(), ["develop", "main"]);
  assert.equal(s.protections.main.merge_access_level, "40");
  assert.equal(s.protections.main.push_access_level, "0");
  assert.equal(s.protections.develop.merge_access_level, "30");
  assert.equal(s.project_settings.wiki_access_level, "enabled");
  assert.deepEqual(s.labels.map((l) => l.name), Object.values(STATUS_LABELS));
  assert.equal(s.boards[0].lists.length, 5);
  const cfg = JSON.parse(readFileSync(join(app.d, ".dm/config.json"), "utf8"));
  assert.equal(cfg.platform, "gitlab");
  assert.equal(cfg.host, "gitlab.com");
  assert.equal(cfg.owner, "acme");
  assert.equal(cfg.repo, "app");
  assert.deepEqual(cfg.status_labels, STATUS_LABELS);
  assert.equal(cfg.develop, true);
  assert.ok(existsSync(join(app.d, ".gitlab/ci/dm-gate.yml")));
  assert.match(readFileSync(join(app.d, ".gitlab-ci.yml"), "utf8"), /local: \.gitlab\/ci\/dm-gate\.yml/);
  assert.ok(!existsSync(join(app.d, ".github/workflows/dm-gate.yml")));
  const calls = s.calls.map((c) => c.join(" ")).join("\n");
  assert.doesNotMatch(calls, /repo create/);
});

test("dm-init on gitlab pushes main and develop before locking pushes", () => {
  const app = initApp();
  const res = runRes(INIT, app, ["run", "--yes"]);
  assert.equal(res.status, 0, res.stderr);
  const bare = join(app.d, "remote/acme/app.git");
  const heads = git(bare, "for-each-ref", "--format=%(refname:short)", "refs/heads").trim().split("\n").sort();
  assert.deepEqual(heads, ["develop", "main"]);
  assert.equal(readState(app.statePath).protections.main.push_access_level, "0");
});

test("dm-init on gitlab fails, and never reports done, when the first push is refused", () => {
  const app = initApp({ reject_pushes: true });
  const res = runRes(INIT, app, ["run", "--yes"]);
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /push of main to origin failed — init incomplete/);
  assert.doesNotMatch(res.stdout + res.stderr, /dm-init: done/);
  assert.equal(readState(app.statePath).protections, undefined);
});

test("dm-init --no-develop on gitlab protects main only, mergeable by developers", () => {
  const app = initApp();
  const res = runRes(INIT, app, ["run", "--yes", "--no-develop"]);
  assert.equal(res.status, 0, res.stderr);
  const s = readState(app.statePath);
  assert.deepEqual(s.protected, ["main"]);
  assert.equal(s.protections.main.merge_access_level, "30");
  assert.equal(JSON.parse(readFileSync(join(app.d, ".dm/config.json"), "utf8")).develop, false);
});

test("dm-init on gitlab warns loudly when branch protection fails", () => {
  const app = initApp({ fail: ["protected_branches"] });
  const res = runRes(INIT, app, ["run", "--yes"]);
  assert.equal(res.status, 0, res.stderr);
  assert.match(res.stderr, /WARNING:.*'main' FAILED — main is NOT protected/);
});

test("dm-init creates the GitLab project when there is no origin", () => {
  const app = initApp({}, null);
  const res = runRes(INIT, app, ["run", "--yes", "--platform", "gitlab", "--owner", "acme-org", "--repo", "app", "--public"]);
  assert.equal(res.status, 0, res.stderr);
  const s = readState(app.statePath);
  assert.deepEqual(s.repo_created, ["app", "--public", "--defaultBranch", "main", "--remoteName", "origin", "--group", "acme-org"]);
  assert.equal(git(app.d, "remote", "get-url", "origin").trim(), "https://gitlab.com/acme-org/app.git");
});

test("dm-init refuses to guess the platform of an unknown origin host", () => {
  const app = initApp({}, "git@git.acme.io:acme/app.git");
  const res = runRes(INIT, app, ["run", "--yes"]);
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /pass --platform github\|gitlab/);
  assert.ok(!existsSync(join(app.d, ".dm/config.json")));
});

test("dm-init --platform gitlab --host takes a self-hosted instance", () => {
  const app = initApp({}, "git@git.acme.io:acme/app.git");
  const res = runRes(INIT, app, ["run", "--yes", "--platform", "gitlab", "--host", "git.acme.io"]);
  assert.equal(res.status, 0, res.stderr);
  const cfg = JSON.parse(readFileSync(join(app.d, ".dm/config.json"), "utf8"));
  assert.equal(cfg.host, "git.acme.io");
});

test("dm-init --no-remote on gitlab makes no protection or wiki call", () => {
  const app = initApp({}, null);
  const res = runRes(INIT, app, ["run", "--yes", "--no-remote", "--platform", "gitlab", "--owner", "acme", "--repo", "app"]);
  assert.equal(res.status, 0, res.stderr);
  const calls = readState(app.statePath).calls.map((c) => c.join(" ")).join("\n");
  assert.doesNotMatch(calls, /protected_branches|wiki_access_level|repo create/);
});

test("dm-init requires glab on gitlab", () => {
  const app = initApp();
  const nodeOnly = join(app.d, "node-only");
  mkdirSync(nodeOnly);
  symlinkSync(process.execPath, join(nodeOnly, "node"));
  const res = runRes(INIT, app, ["run", "--yes"], { PATH: `${nodeOnly}:/usr/bin:/bin` });
  assert.notEqual(res.status, 0);
  assert.match(res.stderr, /glab CLI required/);
});

// --- wiki -----------------------------------------------------------------

test("dm-wiki publishes to the GitLab wiki with home.md as the front page", () => {
  const app = glabApp();
  mkdirSync(join(app.d, "docs/product"), { recursive: true });
  writeFileSync(join(app.d, "docs/product/s01-x.md"), "# Submit\n");
  const bare = join(app.d, "wiki.git");
  execFileSync("git", ["init", "--bare", "-b", "main", bare]);
  const res = runRes(WIKI, app, ["publish", app.d, "1.2.0", "s01-x"], {
    GITLAB_TOKEN: "t0ken",
    GIT_CONFIG_COUNT: "1",
    GIT_CONFIG_KEY_0: `url.file://${bare}.insteadOf`,
    GIT_CONFIG_VALUE_0: "https://gitlab.example.com/acme/team/app.wiki.git",
  });
  assert.equal(res.status, 0, res.stderr);
  const ls = execFileSync("git", ["--git-dir", bare, "ls-tree", "--name-only", "-r", "master"], { encoding: "utf8" });
  assert.deepEqual(ls.trim().split("\n").sort(), ["home.md", "s01-x.md"]);
  const home = execFileSync("git", ["--git-dir", bare, "show", "master:home.md"], { encoding: "utf8" });
  assert.match(home, /\*\*Version:\*\* 1\.2\.0/);
  assert.match(home, /\[s01-x\]\(s01-x\)/);
});

test("dm-wiki authenticates to GitLab as oauth2 without putting the token in argv", () => {
  const t = readFileSync(WIKI, "utf8");
  assert.match(t, /GITLAB_TOKEN/);
  assert.match(t, /glab config get token/);
  assert.match(t, /DM_WIKI_USER=oauth2/);
  assert.doesNotMatch(t, /https:\/\/oauth2:/);
});

// --- CI -------------------------------------------------------------------

test("dm-gate.gitlab-ci.yml mirrors the GitHub gate on merge requests", () => {
  const t = readFileSync(join(ROOT, "src/workflows/dm-gate.gitlab-ci.yml"), "utf8");
  assert.match(t, /merge_request_event/);
  assert.match(t, /cfg\.develop === false/);
  assert.match(t, /must come from develop/);
  assert.match(t, /Ship allowed: yes/);
  assert.match(t, /docs\/product\//);
  assert.match(t, /docs-only/);
  assert.match(t, /CHANGELOG\.md/);
  assert.match(t, /head="\$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"/);
});

// --- commands -------------------------------------------------------------

test("commands route pull/merge requests through dm-vcs, never a raw gh pr / glab mr", () => {
  for (const name of ["dm-ship", "dm-release", "dm-continue", "dm-plan", "dm-orchestrator"]) {
    const t = readFileSync(join(ROOT, `src/commands/${name}.md`), "utf8");
    assert.doesNotMatch(t, /`gh (pr|issue) |`glab (mr|issue) |^\s*gh (pr|issue) /m, name);
  }
  const ship = readFileSync(join(ROOT, "src/commands/dm-ship.md"), "utf8");
  assert.match(ship, /dm-vcs\.sh pr-create "\$INTEG"/);
  assert.match(ship, /dm-vcs\.sh pr-state feature\/<story-id>\/<ticket-id>` must print exactly `MERGED`/);
  assert.match(ship, /dm-vcs\.sh pr-merge/);
  const release = readFileSync(join(ROOT, "src/commands/dm-release.md"), "utf8");
  assert.match(release, /dm-vcs\.sh pr-open-heads main/);
  assert.match(release, /dm-vcs\.sh pr-create main/);
  const init = readFileSync(join(ROOT, "src/commands/dm-init.md"), "utf8");
  assert.match(init, /--platform github\|gitlab/);
  assert.match(init, /glab auth login/);
});
