#!/usr/bin/env bash
# Runs every line of test/cases.jsonl through guardrails.sh with the example config.
# Each line: {"expect": "deny" | "ask" | "allow" | "context" | "none", "input": <hook input>}

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
export GUARDRAILS_CONFIG="$root/examples/guardrails.json"
pass=0; fail=0

while IFS= read -r line; do
  [ -z "$line" ] && continue
  expect="$(printf '%s' "$line" | jq -r '.expect')"
  out="$(printf '%s' "$line" | jq -c '.input' | bash "$root/guardrails.sh")"
  got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput | if .additionalContext then "context" else .permissionDecision end' 2>/dev/null)"
  [ -z "$got" ] && got="none"
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: expected $expect, got $got: $(printf '%s' "$line" | jq -c '.input.tool_input')"
  fi
done < "$root/test/cases.jsonl"

# A broken config must block (exit 2), not allow.
bad="$(mktemp)"; echo '{"rules":[{"tools":["Bash"],"command":["("],"decision":"deny"}]}' > "$bad"
if echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' | GUARDRAILS_CONFIG="$bad" bash "$root/guardrails.sh" 2>/dev/null; [ $? -eq 2 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL: bad config did not exit 2"
fi
rm -f "$bad"

# Symlinks: a write through a link is checked against the real path too.
# check <expect> <file_path>
check() {
  local out got
  out="$(jq -cn --arg f "$2" '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f}}' | bash "$root/guardrails.sh")"
  got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)"
  [ -z "$got" ] && got="none"
  if [ "$got" = "$1" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); echo "FAIL: expected $1, got $got: ${2#"$tmp"}"
  fi
}
tmp="$(mktemp -d)"
mkdir -p "$tmp/projects/app/docs/blog" "$tmp/scratch"
touch "$tmp/projects/app/PLAN.md"
ln -s "$tmp/projects/app" "$tmp/scratch/dirlink"
ln -s "$tmp/projects/app/PLAN.md" "$tmp/scratch/notes.txt"
ln -s "../projects/app" "$tmp/scratch/rellink"
ln -s "$tmp/scratch/loop" "$tmp/scratch/loop"
check deny "$tmp/scratch/dirlink/NEW.md"          # folder link into a protected folder
check deny "$tmp/scratch/notes.txt"               # file link to a protected file
check deny "$tmp/scratch/rellink/sub/NEW.md"      # relative link, target folder does not exist yet
check deny "$tmp/scratch/dirlink/docs/blog/../NEW.md"
check none "$tmp/scratch/dirlink/docs/blog/post.md"  # real path is excepted
check none "$tmp/scratch/dirlink/README.md"
check none "$tmp/scratch/plain.md"                # no link, not protected
check none "$tmp/scratch/loop/x.md"               # a link loop must not hang or block
rm -rf "$tmp"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
