#!/usr/bin/env bash
# claude-guardrails: one Claude Code hook, every rule in a JSON config.
#
# Wire it to PreToolUse and PostToolUse in settings.json. On each call it reads
# the hook input from stdin, finds the first rule that matches, and prints the
# hook output for it (deny / ask / allow, or extra context). No match: no output.
#
# Config: $GUARDRAILS_CONFIG, else ~/.claude/guardrails.json.

set -u

config="${GUARDRAILS_CONFIG:-$HOME/.claude/guardrails.json}"
[ -f "$config" ] || exit 0

input="$(cat)"

# Fail closed: a broken config or bad regex blocks the call (exit 2) instead of letting it through.
printf '%s' "$input" | jq -c --slurpfile cfg "$config" '
  # Glob to anchored regex. * and ? match across /, like a bash case pattern.
  def glob2re: "^" + (gsub("(?<c>[.+^${}()|\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*"; ".*") | gsub("\\?"; ".")) + "$";
  def anyglob($s): any(.[]; . as $g | $s | test($g | glob2re));
  # Resolve ., .. and repeated slashes so a/_archive/../plan.md cannot slip past an except glob.
  def normpath:
    (if startswith("/") then "/" else "" end) as $root
    | $root + (reduce (split("/")[] | select(. != "" and . != ".")) as $p ([];
        if $p == ".." then .[:-1] else . + [$p] end) | join("/"));

  . as $in
  | ($in.tool_input.command // "") as $cmd
  | ($in.tool_input.file_path // "" | normpath) as $file
  | [ $cfg[0].rules[]
      | select((.event // "PreToolUse") == $in.hook_event_name)
      | select(.tools == null or any(.tools[]; . == $in.tool_name))
      | select(.command == null or all(.command[]; . as $re | $cmd | test($re)))
      | select(.path == null or ((.path | anyglob($file)) and ((.except // []) | anyglob($file) | not)))
    ]
  | first // empty
  | if .context then
      {hookSpecificOutput: {hookEventName: $in.hook_event_name, additionalContext: .context}}
    else
      {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: .decision, permissionDecisionReason: .reason}}
    end
' || { echo "claude-guardrails: could not evaluate $config (bad JSON or regex), blocking." >&2; exit 2; }
