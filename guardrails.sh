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

jq -c --slurpfile cfg "$config" '
  # Glob to anchored regex. * and ? match across /, like a bash case pattern.
  def glob2re: "^" + (gsub("(?<c>[.+^${}()|\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*"; ".*") | gsub("\\?"; ".")) + "$";
  def anyglob($s): any(.[]; . as $g | $s | test($g | glob2re));

  . as $in
  | ($in.tool_input.command // "") as $cmd
  | ($in.tool_input.file_path // "") as $file
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
'
