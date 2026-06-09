## [Unreleased]

## [0.1.0] - 2026-06-04

### Initial release

A Rails generator that writes per-agent configuration entirely inside your project folder so Claude Code, Codex CLI, and OpenCode share the same RuboCop workflow.

**Strictly local.** Every file the generator touches lives under `Rails.root`. Nothing is written to `~/.codex/`, `~/.claude.json`, or any other user-level location. Global agent state is out of scope for this release.

### Files written

Per agent, all under the project root:

- **Claude Code** — `CLAUDE.md` (stub pointing to `AGENTS.md`), `.mcp.json` (registers the `rubocop` MCP server), `.claude/settings.json` (PostToolUse + Stop hooks).
- **Codex CLI** — `.codex/config.toml` (registers the `rubocop` MCP server locally; requires Codex CLI ≥ 0.78.0 and `codex trust .codex/`), `.codex/hooks.json` (same PostToolUse + Stop hooks as Claude).
- **OpenCode** — `.opencode/instructions.md`, `opencode.json` (registers the `rubocop` MCP server), `.opencode/plugins/rubocop-changed.js` + `.opencode/plugins/rubocop-edited.js`.
- **Shared** — `AGENTS.md` (cross-agent RuboCop rules), `bin/rubocop-changed`, `bin/rubocop-edited` (Ruby shims that delegate to `railsdx-check`).

### MCP wiring

RuboCop 1.85+ ships an MCP server (`bundle exec rubocop --mcp`) exposing `rubocop_inspection` and `rubocop_autocorrection` as structured tools. The generator registers it in each agent's project-local MCP config, and `AGENTS.md` tells the agent to call those tools before declaring a task done.

### Safety-net hooks

Two RuboCop hooks fire regardless of whether the agent remembered to call the MCP tools:

- **`bin/rubocop-edited`** runs `rubocop -A` on every file the agent edits (Claude/Codex `PostToolUse`, OpenCode `file.edited`). Style fixes land silently; only un-autocorrectable offenses block the turn with exit 2 + report.
- **`bin/rubocop-changed`** lints every Ruby file modified in the working tree at turn-end (Claude/Codex `Stop`, OpenCode `session.idle`). Exit 2 re-enters the turn with the offense report so the agent can't declare done while RuboCop is unhappy.

`rubocop-server` auto-detect — when the daemon is up (`bundle exec rubocop --start-server`) the hooks pass `--server` automatically, skipping rubocop's ~1-2s cold start. Override with `RAILSDX_RUBOCOP_SERVER=1` (force) or `=0` (never).

### Skip flags

- `--skip-claude` / `--skip-codex` / `--skip-opencode` — drop every file for the named agent.
- `--skip-stop-hook` — drop the Stop-event safety net (no `bin/rubocop-changed`, no Stop hook entries).
- `--skip-rubocop-edited` — drop the PostToolUse autocorrect (no `bin/rubocop-edited`, no PostToolUse entries).

### Rubydex (opt-in, experimental)

`--with-rubydex` also registers the [rubydex](https://github.com/shopify/rubydex) semantic-index MCP server in each agent's local MCP config and adds a rubydex section to `AGENTS.md` documenting when to prefer rubydex over `Grep`. Upstream rubydex labels its MCP server experimental and iterates fast — expect drift. Honors `--skip-claude/codex/opencode`. Warns if `${HOME}/.cargo/bin/rubydex_mcp` isn't installed.

### Verification

`bundle exec railsdx-check doctor` reads `.mcp.json`, `.codex/config.toml`, `opencode.json`, `.claude/settings.json`, `.codex/hooks.json`, and `.opencode/plugins/` and reports per-check ✓ / ✗ for both MCP servers and hooks. Exits 0 when wired correctly. Rubydex MCP is treated as optional — only verified when at least one agent already has it registered.

### Idempotency

- Marker-delimited sections (`<!-- railsdx:start -->` / `<!-- railsdx:end -->`) in `AGENTS.md`, `CLAUDE.md`, and `.opencode/instructions.md` — re-running the generator replaces just the railsdx block.
- JSON merging in `.mcp.json`, `opencode.json`, `.claude/settings.json`, `.codex/hooks.json` — existing keys preserved; railsdx entries appended only when not already present.
- TOML merging in `.codex/config.toml` — the existing file is parsed for the presence check, then the template block is appended verbatim so any comments or key ordering in the user's file survive.

### Codex trust

Codex ignores both project-local `config.toml` AND `.codex/` hook scripts until the project is trusted. The generator prints a highlighted reminder: `codex trust .codex/`. Without it, both MCP server registration and hooks silently no-op.
