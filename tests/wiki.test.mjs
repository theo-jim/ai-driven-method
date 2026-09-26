import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, chmodSync, mkdirSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const WIKI = join(ROOT, "src/lib/dm-wiki.sh");

// GitHub app with a product doc; the wiki remote is rewritten to a local bare repo.
function githubApp() {
  const d = mkdtempSync(join(tmpdir(), "wiki-gh-"));
  mkdirSync(join(d, ".dm"), { recursive: true });
  writeFileSync(
    join(d, ".dm/config.json"),
    JSON.stringify({ owner: "acme", repo: "app", project_id: "P", status_field_id: "F", status_option_ids: {} }),
  );
  mkdirSync(join(d, "docs/product"), { recursive: true });
  writeFileSync(join(d, "docs/product/s01-x.md"), "# Submit\n");
  const bare = join(d, "wiki.git");
  execFileSync("git", ["init", "--bare", "-b", "master", bare]);
  const bin = join(d, "bin");
  mkdirSync(bin);
  writeFileSync(join(bin, "gh"), "#!/bin/sh\ncase \"$*\" in *\"auth token\"*) echo stub-token ;; esac\nexit 0\n");
  chmodSync(join(bin, "gh"), 0o755);
  const env = {
    ...process.env,
    PATH: `${bin}:${process.env.PATH}`,
    GIT_CONFIG_COUNT: "1",
    GIT_CONFIG_KEY_0: `url.file://${bare}.insteadOf`,
    GIT_CONFIG_VALUE_0: "https://github.com/acme/app.wiki.git",
  };
  delete env.GH_TOKEN;
  delete env.GITHUB_TOKEN;
  return { d, bare, env };
}

const publish = (app, env = {}) =>
  spawnSync("bash", [WIKI, "publish", app.d, "1.2.0", "s01-x"], {
    cwd: app.d,
    encoding: "utf8",
    env: { ...app.env, ...env },
  });

test("dm-wiki cleans its temp dir even when TMPDIR contains a quote", () => {
  const app = githubApp();
  const tmp = join(app.d, "it's tmp");
  mkdirSync(tmp);
  const res = publish(app, { TMPDIR: tmp });
  assert.equal(res.status, 0, res.stderr);
  assert.deepEqual(readdirSync(tmp), []);
});

// Regression for e33a10e: the EXIT trap used to fail `set -u` after a successful push.
test("dm-wiki publish on GitHub exits 0 after a successful push", () => {
  const app = githubApp();
  const res = publish(app);
  assert.equal(res.status, 0, res.stderr);
  assert.match(res.stdout, /published v1\.2\.0 \(1 stories\)/);
  const ls = execFileSync("git", ["--git-dir", app.bare, "ls-tree", "--name-only", "-r", "master"], { encoding: "utf8" });
  assert.deepEqual(ls.trim().split("\n").sort(), ["Home.md", "s01-x.md"]);
});
