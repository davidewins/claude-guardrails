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

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
