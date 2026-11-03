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

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
