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

# The real path of $1 after following symlinks, so a link into a protected folder is
# matched as that folder. The file may not exist yet: this resolves the deepest part
# that does and puts the rest back on the end.
realpath_of() {
  local p="$1" rest="" target dir hops=0
  while :; do
    if [ -L "$p" ] && [ "$hops" -lt 40 ]; then
      hops=$((hops + 1))
      target="$(readlink "$p")" || break
      case "$target" in /*) p="$target" ;; *) p="$(dirname "$p")/$target" ;; esac
      continue
    fi
    if [ -d "$p" ] && dir="$(cd -P -- "$p" 2>/dev/null && pwd -P)"; then
      printf '%s%s' "${dir%/}" "$rest"
      return
    fi
    case "$p" in / | . | "") break ;; esac
    rest="/$(basename "$p")$rest"
    p="$(dirname "$p")"
  done
  printf '%s' "$1"
}

real=""
case "$input" in *'"file_path"'*)
  raw="$(printf '%s' "$input" | jq -r '(.tool_input.file_path // "") as $f
    | if $f == "" or ($f | startswith("/")) or (.cwd // "") == "" then $f else .cwd + "/" + $f end' 2>/dev/null)"
  [ -n "$raw" ] && real="$(realpath_of "$raw")"
  ;;
esac

# Fail closed: a broken config or bad regex blocks the call (exit 2) instead of letting it through.
printf '%s' "$input" | jq -c --slurpfile cfg "$config" --arg real "$real" '
  # Glob to anchored regex. * and ? match across /, like a bash case pattern.
  # Case is ignored: on a Mac or Windows disk docs/plan.md and Docs/PLAN.md are the same file.
  def glob2re: "^" + (gsub("(?<c>[.+^${}()|\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*"; ".*") | gsub("\\?"; ".")) + "$";
  def anyglob($s): any(.[]; . as $g | $s | test($g | glob2re; "i"));
  # Resolve ., .. and repeated slashes so a/_archive/../plan.md cannot slip past an except glob.
  # Relative paths are resolved against the hook cwd; a leading .. that is left over is kept.
  def normpath:
    (if startswith("/") then "/" else "" end) as $root
    | $root + (reduce (split("/")[] | select(. != "" and . != ".")) as $p ([];
        if $p != ".." then . + [$p]
        elif length > 0 and .[-1] != ".." then .[:-1]
        elif $root == "" then . + [".."]
        else . end) | join("/"));

  . as $in
  | ($in.tool_input.command // "") as $cmd
  | ($in.tool_input.file_path // "") as $raw
  | (if $raw == "" or ($raw | startswith("/")) or ($in.cwd // "") == "" then $raw else $in.cwd + "/" + $raw end | normpath) as $file
  # The path as written and the path the symlinks lead to. A path rule applies if either one
  # matches and is not excepted.
  | ([$file, (if $real == "" then $file else ($real | normpath) end)] | unique) as $files
  | [ $cfg[0].rules[]
      | select((.event // "PreToolUse") == $in.hook_event_name)
      | select(.tools == null or any(.tools[]; . == $in.tool_name))
      | select(.command == null or all(.command[]; . as $re | $cmd | test($re)))
      | select(.path == null or (. as $rule | any($files[]; . as $f
          | ($rule.path | anyglob($f)) and (($rule.except // []) | anyglob($f) | not))))
    ]
  | first // empty
  | if .context then
      {hookSpecificOutput: {hookEventName: $in.hook_event_name, additionalContext: .context}}
    else
      {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: .decision, permissionDecisionReason: .reason}}
    end
' || { echo "claude-guardrails: could not evaluate $config (bad JSON or regex), blocking." >&2; exit 2; }
