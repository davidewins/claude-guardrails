# claude-guardrails

One [Claude Code hook](https://docs.claude.com/en/docs/claude-code/hooks) with all your rules in a JSON file. It blocks commands, asks before risky ones, keeps files out of folders and adds reminders after edits. It needs only bash and `jq`, and takes around 10 to 20 milliseconds per tool call.

```json
{
  "tools": ["Bash"],
  "command": ["eas(-cli)?[[:space:]]+build", "(--profile|-e)[= ]+production"],
  "decision": "ask",
  "reason": "Production EAS build: needs the user's explicit go-ahead."
}
```

## Install

```bash
git clone https://github.com/davidewins/claude-guardrails ~/.claude/claude-guardrails
cp ~/.claude/claude-guardrails/examples/guardrails.json ~/.claude/guardrails.json
```

Add the hook to `~/.claude/settings.json` (or a project's `.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash|Write|Edit", "hooks": [{ "type": "command", "command": "~/.claude/claude-guardrails/guardrails.sh", "timeout": 5 }] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "~/.claude/claude-guardrails/guardrails.sh", "timeout": 5 }] }
    ]
  }
}
```

The config is read from `$GUARDRAILS_CONFIG`, or `~/.claude/guardrails.json` if that is not set. If the file is missing, the hook does nothing.

## Rules

`rules` is a list. On each tool call the first rule that matches wins. If no rule matches, the hook prints nothing and Claude Code carries on as normal.

| Field | Meaning |
| -- | -- |
| `event` | `PreToolUse` (default) or `PostToolUse` |
| `tools` | Tool names the rule applies to, such as `["Bash"]` or `["Write", "Edit"]`. Leave it out to match every tool. |
| `command` | Regexes tested against a Bash command. All of them must match. |
| `path` | Globs tested against `file_path`. One of them must match. `*` matches across `/`. Case is ignored. |
| `except` | Globs that cancel a `path` match. |
| `decision` | `deny`, `ask` or `allow` (PreToolUse) |
| `reason` | Shown to Claude (deny) or to you (ask) |
| `context` | Text added to Claude's context instead of a decision. Use it for reminders on PostToolUse. |

Regexes use jq's Oniguruma syntax, so POSIX classes like `[[:space:]]` work. Matching is on the raw command text, so `ssh host 'bun install'` is caught too.

Before matching, `file_path` is cleaned up: `.`, `..` and doubled slashes are resolved, so `docs/blog/../PLAN.md` cannot slip past an `except` glob. Symlinks are followed too: a path rule is checked against the path as written and against the real path, and it applies if either one matches and is not excepted. Globs ignore case, because on a Mac or Windows disk `docs/plan.md` and `Docs/PLAN.md` are the same file.

If an `except` glob names a folder through a symlink (on a Mac `/tmp` is a link to `/private/tmp`), write it so it also matches the real path, for example `*/tmp/*`.

Path rules only see the `file_path` of tools like Write and Edit. A file written by a Bash command (`echo > file`, `cp`, `sed -i`) is not checked against them. Use a `command` rule to catch those.

If the config has bad JSON or a bad regex, the hook exits 2 and blocks the call instead of letting it through.

[`examples/guardrails.json`](examples/guardrails.json) has rules for the following:

- no bun
- no unrequested PRs
- ask before production EAS builds and OTA updates
- no new plan `.md` files in a projects folder
- a screenshot reminder after UI edits

## Test

```bash
./test/run.sh
```

Each line of `test/cases.jsonl` is a hook input plus the expected result (`deny`, `ask`, `allow`, `context` or `none`), checked against the example config.

## License

MIT
