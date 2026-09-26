#!/bin/sh
# Canned gh for board-parse tests. Reads DM_GH_STUB_STATE (JSON file).
# state shape:
# {
#   "issues": [
#     {"title":"[s01-x/t01-y] Foo","number":2,"id":"I_child",
#      "projectItems":[{"id":"PVTI_child","status":{"optionId":"opt2","name":"ready"}}]},
#     {"title":"[s01-x] Parent","number":1,"id":"I_parent",
#      "projectItems":[{"id":"PVTI_parent","status":{"optionId":"opt1","name":"backlog"}}]}
#   ],
#   "repos": [],
#   "protections": [],
#   "rulesets": []
# }
set -eu
STATE="${DM_GH_STUB_STATE:-}"
if [ -z "$STATE" ] || [ ! -f "$STATE" ]; then
  echo "gh-stub: DM_GH_STUB_STATE missing" >&2
  exit 99
fi

# Flatten args for matching
args="$*"

# Single source of truth for the Status field options, shared by
# field-create and field-list so they can't drift apart.
STATUS_OPTIONS='[{"name":"backlog","id":"opt1"},{"name":"ready","id":"opt2"},{"name":"in progress","id":"opt3"},{"name":"test","id":"opt4"},{"name":"shipped","id":"opt5"}]'

case "$args" in
  *"repo create"*)
    node -e '
      const cp=require("child_process");
      const fs=require("fs");
      const path=require("path");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const argv=process.argv.slice(1);
      const i=argv.indexOf("create");
      const remote=path.join(path.dirname(process.env.DM_GH_STUB_STATE),"remote.git");
      if (!fs.existsSync(remote)) cp.execFileSync("git",["init","--bare",remote],{stdio:"ignore"});
      cp.execFileSync("git",["remote","add","origin",remote],{stdio:"ignore"});
      s.repos=s.repos||[];
      s.repos.push({name:argv[i+1]||"",remote});
      fs.writeFileSync(process.env.DM_GH_STUB_STATE,JSON.stringify(s,null,2));
    ' "$@"
    echo '{"name":"app"}'
    ;;
  *"project create"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      s.projects=s.projects||[];
      s.projects.push({id:"PVT_test",number:1});
      fs.writeFileSync(process.env.DM_GH_STUB_STATE,JSON.stringify(s,null,2));
    '
    echo '{"id":"PVT_test","number":1}'
    ;;
  *"project link"*)
    echo '{"ok":true}'
    ;;
  *"project field-create"*)
    echo "{\"id\":\"FIELD_status\",\"options\":${STATUS_OPTIONS}}"
    ;;
  *"project field-list"*)
    echo "[{\"id\":\"FIELD_status\",\"name\":\"Status\",\"options\":${STATUS_OPTIONS}}]"
    ;;
  *"branches/"*"/protection"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const argv=process.argv.slice(1);
      const endpoint=argv.find((arg)=>arg.includes("/branches/")&&arg.endsWith("/protection"));
      const branch=endpoint.match(/\/branches\/([^/]+)\/protection$/)[1];
      s.protections=s.protections||[];
      s.protections.push({branch,body:JSON.parse(fs.readFileSync(0,"utf8"))});
      fs.writeFileSync(process.env.DM_GH_STUB_STATE,JSON.stringify(s,null,2));
    ' "$@"
    echo '{}'
    ;;
  *"rulesets"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const argv=process.argv.slice(1);
      const get=(flag)=>{const i=argv.indexOf(flag); return i>=0?argv[i+1]:null;};
      const method=get("-X")||"GET";
      const endpoint=argv.find((arg)=>arg.includes("/rulesets"));
      s.rulesets=s.rulesets||[];
      if (method==="GET") {
        const query=get("-q")||"";
        const match=query.match(/\.name=="([^"]+)/);
        const ruleset=s.rulesets.find((item)=>item.name===(match&&match[1]));
        if (ruleset) process.stdout.write(String(ruleset.id));
      } else {
        const body=JSON.parse(fs.readFileSync(0,"utf8"));
        const idMatch=endpoint.match(/\/rulesets\/(.+)$/);
        const id=idMatch?idMatch[1]:`RS_${s.rulesets.length+1}`;
        const index=s.rulesets.findIndex((item)=>String(item.id)===id);
        const ruleset={id,...body};
        if (index>=0) s.rulesets[index]=ruleset;
        else s.rulesets.push(ruleset);
        process.stdout.write(JSON.stringify(ruleset));
      }
      fs.writeFileSync(process.env.DM_GH_STUB_STATE,JSON.stringify(s,null,2));
    ' "$@"
    ;;
  *"-q .node_id"*)
    echo 'REPO_NODE'
    ;;
  *"has_wiki"*)
    echo '{}'
    ;;
  *"pr create"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const argv=process.argv.slice(1);
      const get=flag=>{const i=argv.indexOf(flag); return i>=0?argv[i+1]:null;};
      s.prs=s.prs||[];
      const number=s.prs.length+1;
      const pr={
        number,
        url:"https://github.com/acme/app/pull/"+number,
        base:get("--base"),
        head:get("--head"),
        title:get("--title"),
        body:get("--body"),
        state:"OPEN",
        mergedAt:null
      };
      s.prs.push(pr);
      fs.writeFileSync(process.env.DM_GH_STUB_STATE,JSON.stringify(s,null,2));
      process.stdout.write(pr.url+"\n");
    ' "$@"
    ;;
  *"pr merge"*)
    node -e '
      const fs=require("fs");
      const { execFileSync }=require("child_process");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const target=process.argv.slice(3).find(a=>!a.startsWith("-"));
      const pr=(s.prs||[]).find(p=>p.url===target||p.head===target);
      if (!pr) process.exit(1);
      s.merge_calls=(s.merge_calls||0)+1;
      if (s.merge_fail_remaining>0) {
        s.merge_fail_remaining--;
        fs.writeFileSync(process.env.DM_GH_STUB_STATE,JSON.stringify(s,null,2));
        process.exit(1);
      }
      pr.state="MERGED";
      pr.mergedAt="2026-01-01T00:00:00Z";
      if (s.originPath) {
        const git=(args)=>execFileSync("git",["--git-dir",s.originPath,...args],{
          env:{...process.env,GIT_AUTHOR_NAME:"gh-stub",GIT_AUTHOR_EMAIL:"gh-stub@test",GIT_COMMITTER_NAME:"gh-stub",GIT_COMMITTER_EMAIL:"gh-stub@test"}
        }).toString().trim();
        try {
          // Real squash-merge: a *new* commit on the base branch carrying the
          // head branch tree, parented on base (not on head) — same content,
          // different SHA, exactly like GitHub-side squash produces.
          const headSha=git(["rev-parse","refs/heads/"+pr.head]);
          const baseSha=git(["rev-parse","refs/heads/"+pr.base]);
          const tree=git(["rev-parse",headSha+"^{tree}"]);
          const squashSha=git(["commit-tree",tree,"-p",baseSha,"-m",pr.title||"squash merge"]);
          git(["update-ref","refs/heads/"+pr.base,squashSha]);
          // Simulate the GitHub "automatically delete head branches" repo
          // setting, which removes the head ref server-side regardless of
          // --delete-branch.
          if (s.auto_delete_head) git(["update-ref","-d","refs/heads/"+pr.head]);
        } catch (e) { /* best-effort simulation */ }
      }
      fs.writeFileSync(process.env.DM_GH_STUB_STATE,JSON.stringify(s,null,2));
    ' "$@"
    ;;
  *"pr view"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const argv=process.argv.slice(3);
      const target=argv.find(a=>!a.startsWith("-"));
      const pr=(s.prs||[]).find(p=>p.url===target||p.head===target);
      if (!pr) process.exit(1);
      s.view_calls=(s.view_calls||0)+1;
      fs.writeFileSync(process.env.DM_GH_STUB_STATE,JSON.stringify(s,null,2));
      if (argv.includes("--jq")) process.stdout.write(pr.state+"\n");
      else process.stdout.write(JSON.stringify({state:pr.state,mergedAt:pr.mergedAt}));
    ' "$@"
    ;;
  *"issue list"*)
    node -e '
      const s=JSON.parse(require("fs").readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const issues=(s.issues||[]).map(i=>({
        title:i.title, number:i.number, id:i.id||("I_"+i.number),
        projectItems:i.projectItems||[]
      }));
      process.stdout.write(JSON.stringify(issues));
    '
    ;;
  *"project item-edit"*)
    # Record last edit into state.edits[]
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const argv=process.argv.slice(1);
      const get=flag=>{const i=argv.indexOf(flag); return i>=0?argv[i+1]:null;};
      s.edits=s.edits||[];
      s.edits.push({
        id:get("--id"),
        projectId:get("--project-id"),
        fieldId:get("--field-id"),
        optionId:get("--single-select-option-id")
      });
      // Update matching projectItems status name from option map
      const opt=get("--single-select-option-id");
      const map=s.status_option_ids||s.config_status||{};
      let name=null;
      for (const [k,v] of Object.entries(map)) if (v===opt) name=k;
      for (const issue of s.issues||[]) {
        for (const pi of issue.projectItems||[]) {
          if (pi.id===get("--id") && name) {
            pi.status={optionId:opt, name};
          }
        }
      }
      fs.writeFileSync(process.env.DM_GH_STUB_STATE, JSON.stringify(s,null,2));
    ' "$@"
    echo '{"ok":true}'
    ;;
  *"issue create"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const argv=process.argv.slice(1);
      const get=flag=>{const i=argv.indexOf(flag); return i>=0?argv[i+1]:null;};
      const title=get("-t")||get("--title")||"untitled";
      const bodyFile=get("-F")||get("--body-file");
      let body="";
      if (bodyFile) body=fs.readFileSync(bodyFile,"utf8");
      const n=(s.issues||[]).reduce((m,i)=>Math.max(m,i.number||0),0)+1;
      const issue={
        title,
        number:n,
        id:"I_"+n,
        body,
        labels:[],
        projectItems:[{id:"PVTI_"+n, status:{optionId:"opt1", name:"backlog"}}]
      };
      s.issues=s.issues||[];
      s.issues.push(issue);
      fs.writeFileSync(process.env.DM_GH_STUB_STATE, JSON.stringify(s,null,2));
      process.stdout.write("https://github.com/acme/app/issues/"+n+"\n");
    ' "$@"
    ;;
  *"project item-add"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      s.item_add_calls=(s.item_add_calls||0)+1;
      const n=s.item_add_fail_remaining||0;
      if (n>0) {
        s.item_add_fail_remaining=n-1;
        fs.writeFileSync(process.env.DM_GH_STUB_STATE, JSON.stringify(s,null,2));
        process.exit(1);
      }
      fs.writeFileSync(process.env.DM_GH_STUB_STATE, JSON.stringify(s,null,2));
    '
    echo '{"id":"PVTI_added"}'
    ;;
  *"api graphql"*|*"api graphql"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      s.graphql_calls=(s.graphql_calls||0)+1;
      fs.writeFileSync(process.env.DM_GH_STUB_STATE, JSON.stringify(s,null,2));
      if (s.subissue_fail) process.exit(1);
      process.stdout.write("{}");
    '
    ;;
  *"label create"*)
    echo '{"name":"ticket"}'
    ;;
  *"issue edit"*)
    node -e '
      const fs=require("fs");
      const s=JSON.parse(fs.readFileSync(process.env.DM_GH_STUB_STATE,"utf8"));
      const argv=process.argv.slice(1);
      const get=flag=>{const i=argv.indexOf(flag); return i>=0?argv[i+1]:null;};
      const num=argv.find((a)=>/^\d+$/.test(a));
      const issue=(s.issues||[]).find((i)=>String(i.number)===String(num));
      if (!issue) process.exit(1);
      const bf=get("--body-file");
      if (bf) issue.body=fs.readFileSync(bf,"utf8");
      const ti=get("--title")||get("-t");
      if (ti) issue.title=ti;
      const lab=get("--add-label")||get("-l");
      if (lab) {
        issue.labels=issue.labels||[];
        if (!issue.labels.includes(lab)) issue.labels.push(lab);
      }
      s.edits=s.edits||[];
      s.edits.push({kind:"issue-edit", number:Number(num), title:issue.title, labels:issue.labels||[], body:issue.body||""});
      fs.writeFileSync(process.env.DM_GH_STUB_STATE, JSON.stringify(s,null,2));
    ' "$@"
    echo '{"ok":true}'
    ;;
  *"auth token"*|*"auth setup-git"*)
    echo "stub-token"
    ;;
  *)
    echo "gh-stub: unhandled: $args" >&2
    exit 98
    ;;
esac
