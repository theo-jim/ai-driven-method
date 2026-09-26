#!/bin/sh
# Canned gh for board-parse tests. Reads DM_GH_STUB_STATE (JSON file).
# state shape:
# {
#   "issues": [
#     {"title":"[s01-x/t01-y] Foo","number":2,"id":"I_child",
#      "projectItems":[{"id":"PVTI_child","status":{"optionId":"opt2","name":"ready"}}]},
#     {"title":"[s01-x] Parent","number":1,"id":"I_parent",
#      "projectItems":[{"id":"PVTI_parent","status":{"optionId":"opt1","name":"backlog"}}]}
#   ]
# }
set -eu
STATE="${DM_GH_STUB_STATE:-}"
if [ -z "$STATE" ] || [ ! -f "$STATE" ]; then
  echo "gh-stub: DM_GH_STUB_STATE missing" >&2
  exit 99
fi

# Flatten args for matching
args="$*"

case "$args" in
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
