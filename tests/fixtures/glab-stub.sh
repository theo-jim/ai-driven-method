#!/bin/sh
# Canned glab for GitLab tests. Reads and rewrites DM_GLAB_STUB_STATE (JSON file).
# Every call is appended to state.calls (argv array) for assertions.
# state shape:
# {
#   "user": "acme",
#   "project": "acme/app",          // path used in URLs of calls that name no project
#   "issues": [{"iid":1,"id":101,"title":"[s01-x] Parent","labels":["dm::backlog"],"description":""}],
#   "mrs": [{"iid":3,"source_branch":"feature/s01-x/t01-y","target_branch":"develop","state":"opened"}],
#   "protected": ["main"],          // branches already protected
#   "fail": ["links", "protected_branches", "mr merge", ...]  // substrings of calls to fail
# }
set -eu
if [ -z "${DM_GLAB_STUB_STATE:-}" ] || [ ! -f "$DM_GLAB_STUB_STATE" ]; then
  echo "glab-stub: DM_GLAB_STUB_STATE missing" >&2
  exit 99
fi
exec node -e '
const fs = require("fs");
const file = process.env.DM_GLAB_STUB_STATE;
const s = JSON.parse(fs.readFileSync(file, "utf8"));
const argv = process.argv.slice(1);
s.calls = s.calls || [];
s.calls.push(argv);
s.issues = s.issues || [];
s.mrs = s.mrs || [];
const save = () => fs.writeFileSync(file, JSON.stringify(s, null, 2));
const flag = (...names) => { for (const n of names) { const i = argv.indexOf(n); if (i >= 0) return argv[i + 1]; } return null; };
const fields = () => {
  const out = {};
  argv.forEach((a, i) => {
    if ((a === "-f" || a === "-F" || a === "--raw-field" || a === "--field") && argv[i + 1] !== undefined) {
      const kv = argv[i + 1]; const eq = kv.indexOf("=");
      out[kv.slice(0, eq)] = kv.slice(eq + 1);
    }
  });
  return out;
};
const joined = argv.join(" ");
const fail = (s.fail || []).find((f) => joined.includes(f));
if (fail) { save(); console.error("glab-stub: forced failure on " + fail); process.exit(1); }
const host = process.env.GITLAB_HOST || "gitlab.com";
const proj = decodeURIComponent((joined.match(/projects\/([^/?\s]+)/) || [])[1] || s.project || "acme/app");
const issueOut = (i) => ({ ...i, web_url: "https://" + host + "/" + proj + "/-/issues/" + i.iid });
const mrUrl = (m) => "https://" + host + "/" + proj + "/-/merge_requests/" + m.iid;
const findMr = (ref) => s.mrs.find((m) => String(m.iid) === String(ref) || m.source_branch === ref || mrUrl(m) === ref || (ref || "").endsWith("/merge_requests/" + m.iid));
const out = (v) => process.stdout.write(typeof v === "string" ? v : JSON.stringify(v));

const [cmd, sub] = argv;
if (cmd === "api") {
  const path = argv.find((a, i) => i > 0 && !a.startsWith("-") && !["-X", "-f", "-F", "--method", "--output", "-H", "--hostname"].includes(argv[i - 1]));
  const method = (flag("-X", "--method") || (Object.keys(fields()).length ? "POST" : "GET")).toUpperCase();
  const f = fields();
  let m;
  if (path === "user") { save(); out({ username: s.user || "acme", id: 7 }); process.exit(0); }
  if ((m = path.match(/^namespaces\/(.+)$/))) { save(); out({ id: 42, full_path: decodeURIComponent(m[1]) }); process.exit(0); }
  if ((m = path.match(/^projects\/[^/]+\/issues(\?.*)?$/)) && method === "GET") {
    save();
    process.stdout.write(s.issues.map((i) => JSON.stringify(issueOut(i))).join("\n") + (s.issues.length ? "\n" : ""));
    process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/issues$/)) && method === "POST") {
    const iid = s.issues.reduce((n, i) => Math.max(n, i.iid || 0), 0) + 1;
    const issue = { iid, id: 100 + iid, title: f.title || "untitled", description: f.description || "", labels: f.labels ? f.labels.split(",") : [] };
    s.issues.push(issue); save(); out(issueOut(issue)); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/issues\/(\d+)$/)) && method === "PUT") {
    const issue = s.issues.find((i) => String(i.iid) === m[1]);
    if (!issue) { save(); console.error("404 issue"); process.exit(1); }
    if (f.title !== undefined) issue.title = f.title;
    if (f.description !== undefined) issue.description = f.description;
    const rm = (f.remove_labels || "").split(",").filter(Boolean);
    issue.labels = (issue.labels || []).filter((l) => !rm.includes(l));
    for (const l of (f.add_labels || "").split(",").filter(Boolean)) if (!issue.labels.includes(l)) issue.labels.push(l);
    save(); out(issueOut(issue)); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/issues\/(\d+)\/links$/))) {
    s.links = s.links || []; s.links.push({ parent: Number(m[1]), child: Number(f.target_issue_iid), target_project_id: f.target_project_id });
    save(); out({}); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/labels$/)) && method === "POST") {
    s.labels = s.labels || [];
    if (s.labels.some((l) => l.name === f.name)) { save(); console.error("409 Label already exists"); process.exit(1); }
    const label = { id: 500 + s.labels.length, name: f.name, color: f.color };
    s.labels.push(label); save(); out(label); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/labels\/(.+)$/))) {
    const name = decodeURIComponent(m[1]);
    const label = (s.labels || []).find((l) => l.name === name);
    save(); if (!label) { console.error("404"); process.exit(1); } out(label); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/boards$/))) {
    s.boards = s.boards || [];
    if (method === "POST") { const b = { id: 900 + s.boards.length, name: f.name, lists: [] }; s.boards.push(b); save(); out(b); process.exit(0); }
    save(); out(s.boards); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/boards\/(\d+)\/lists$/))) {
    const b = (s.boards || []).find((x) => String(x.id) === m[1]);
    if (!b) { save(); console.error("404 board"); process.exit(1); }
    if (b.lists.includes(Number(f.label_id))) { save(); console.error("400 list exists"); process.exit(1); }
    b.lists.push(Number(f.label_id)); save(); out({ id: 1 }); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/protected_branches\/(.+)$/))) {
    const name = decodeURIComponent(m[1]);
    s.protected = s.protected || [];
    if (method === "DELETE") { s.protected = s.protected.filter((b) => b !== name); save(); process.exit(0); }
    save(); if (!s.protected.includes(name)) { console.error("404"); process.exit(1); } out({ name }); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+\/protected_branches$/)) && method === "POST") {
    s.protected = s.protected || [];
    if (s.protected.includes(f.name)) { save(); console.error("409 Protected branch already exists"); process.exit(1); }
    s.protected.push(f.name);
    s.protections = s.protections || {}; s.protections[f.name] = f;
    save(); out({ name: f.name }); process.exit(0);
  }
  if ((m = path.match(/^projects\/[^/]+$/)) && method === "PUT") {
    s.project_settings = { ...(s.project_settings || {}), ...f }; save(); out({}); process.exit(0);
  }
  save(); console.error("glab-stub: unhandled api " + method + " " + path); process.exit(98);
}
if (cmd === "mr" && sub === "create") {
  const iid = s.mrs.reduce((n, x) => Math.max(n, x.iid || 0), 0) + 1;
  const mr = { iid, source_branch: flag("--source-branch", "-s"), target_branch: flag("--target-branch", "-b"), title: flag("--title", "-t"), description: fs.readFileSync(flag("--description-file"), "utf8"), state: "opened" };
  s.mrs.push(mr); save();
  out("\nCreating merge request for " + mr.source_branch + " into " + mr.target_branch + " in " + proj + "\n\n!" + iid + " " + mr.title + " (" + mr.source_branch + ")\n " + mrUrl(mr) + "\n\n");
  process.exit(0);
}
if (cmd === "mr" && sub === "view") {
  const mr = findMr(argv[2]); save();
  if (!mr) { console.error("no merge request found"); process.exit(1); }
  out({ iid: mr.iid, state: mr.state, source_branch: mr.source_branch, web_url: mrUrl(mr) }); process.exit(0);
}
if (cmd === "mr" && sub === "merge") {
  const mr = findMr(argv[2]);
  if (!mr) { save(); console.error("no merge request found"); process.exit(1); }
  mr.state = "merged"; mr.merge_args = argv.slice(3); save();
  out("Merged!\n"); process.exit(0);
}
if (cmd === "mr" && sub === "list") {
  const target = flag("--target-branch", "-t"); save();
  out(s.mrs.filter((m) => m.state === "opened" && (!target || m.target_branch === target)).map((m) => ({ ...m, web_url: mrUrl(m) })));
  process.exit(0);
}
if (cmd === "issue" && sub === "update") {
  const issue = s.issues.find((i) => String(i.iid) === argv[2]);
  if (!issue) { save(); console.error("404"); process.exit(1); }
  const df = flag("--description-file"); if (df) issue.description = fs.readFileSync(df, "utf8");
  save(); process.exit(0);
}
if (cmd === "repo" && sub === "create") {
  s.repo_created = argv.slice(2); save(); out("Created repository\n"); process.exit(0);
}
if (cmd === "auth" && sub === "status") { save(); process.exit(s.unauthenticated ? 1 : 0); }
if (cmd === "config" && sub === "get") { save(); out("stub-glab-token\n"); process.exit(0); }
save();
console.error("glab-stub: unhandled: " + joined);
process.exit(98);
' -- "$@"
