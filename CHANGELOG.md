## [Unreleased]

### Added

- `rubocop-server` auto-detect in both `bin/rubocop-changed` and `bin/rubocop-edited`. When the daemon is up (`bundle exec rubocop --start-server`) the hooks pass `--server` automatically, skipping rubocop's ~1-2s cold start that compounds across every PostToolUse fire. Override with `RAILSDX_RUBOCOP_SERVER=1` (force) or `=0` (never). Lives on `Checks::Base` via the new `Railsdx::Checks::RubocopServer` module so every future check that shells out to rubocop inherits it.
- Codex trust step surfaced as a numbered next-step in the generator's "Done. Next:" output, highlighted as **REQUIRED for Codex hooks**. Without `codex trust .codex/` the railsdx Stop / PostToolUse hooks silently no-op — surfacing it inline prevents the worst failure mode for a safety net.
- `docs/rubydex.md` — full rubydex install + usage doc lifted out of the main README so the README stays focused on the v0 RuboCop surface.
- `docs/extending.md` — public contract for writing a new check. Documents the four touchpoints (check class, autoload, CLI dispatcher, doctor row), the helpers `Checks::Base` exposes, and the design reasoning behind explicit-over-reflection registration.
- README rewrite covering both halves of the safety net (PostToolUse `bin/rubocop-edited` was previously undocumented), an "Uninstall" section with the manual procedure, and a "Where this is going" roadmap paragraph framing railsdx as an umbrella for Rails-AI DX (RuboCop is just first).

- `--with-rubydex` opt-in flag wires the [rubydex](https://github.com/shopify/rubydex) semantic-index MCP server. **Experimental** — upstream rubydex labels its MCP server experimental and is iterating; watch the repo, expect drift. Registers at **user scope** (rubydex inherits CWD, so one entry covers every project) — prints `claude mcp add --scope user` for Claude Code, plus TOML/JSON snippets for `~/.codex/config.toml` and `~/.config/opencode/opencode.json`. Adds a rubydex section to `AGENTS.md` documenting when to prefer rubydex over `Grep`. Honors `--skip-claude/codex/opencode`. Warns if `${HOME}/.cargo/bin/rubydex_mcp` isn't installed.
- `Railsdx::Checks` framework + `bin/railsdx-check` Thor executable. Each hook subclasses `Checks::Base` and is dispatched via `bundle exec railsdx-check <name>`. State recorded at `.railsdx/last-check.json`.
- Post-turn safety net: `bin/rubocop-changed` script that lints every `.rb` file modified in the working tree and exits non-zero with offenses on stderr.
- Per-edit autocorrect (R1): `bin/rubocop-edited` runs `rubocop -A` on whichever file the agent just edited via PostToolUse hooks. Reads `tool_input.file_path` from stdin JSON, exits 2 only when un-autocorrectable offenses remain.
- Hook configs across three agents:
  - `.claude/settings.json` (Claude Code) — blocking PostToolUse + Stop
  - `.codex/hooks.json` (Codex CLI) — blocking PostToolUse + Stop, requires trusting `.codex/` once
  - `.opencode/plugins/rubocop-changed.js` + `.opencode/plugins/rubocop-edited.js` (OpenCode) — observation only (`session.idle` / `file.edited`)
- `railsdx-check doctor` subcommand: read-only inspection that reports per-check ✓/✗ across the three agent configs. Exits 0 when wired correctly, 1 otherwise. Recommended after running the install generator.
- `--skip-stop-hook` opts out of the Stop-event safety net only; `--skip-rubocop-edited` opts out of the PostToolUse autocorrect only. `--skip-claude`, `--skip-codex`, `--skip-opencode` suppress the corresponding agent's hook config.
- AGENTS.md documents both checks alongside the MCP workflow.

## [0.1.0] - 2026-05-21

- Initial release
