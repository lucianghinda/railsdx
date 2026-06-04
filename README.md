# railsdx

I built `railsdx` because I kept wiring the same handful of files into every Rails project I started using AI coding assistants - and getting it slightly wrong every time. The MCP config in one place, the agent instructions in another, the post-turn lint hook in a third. Three assistants, three protocols, one annoyed me.

This gem ships **one Rails generator** that does the wiring for you. The first thing it teaches your AI assistants is RuboCop:

- It registers the [RuboCop MCP server](https://docs.rubocop.org/rubocop/latest/usage/mcp.html) in Claude Code, Codex, and OpenCode so the agent calls `rubocop_inspection` and `rubocop_autocorrection` as structured tools.
- It writes `AGENTS.md` (and the per-assistant stubs that point at it) so the agent knows _when_ to reach for those tools.
- It drops two RuboCop safety nets - one mid-turn, one post-turn - so even when the agent forgets to call the MCP tools, RuboCop still runs.

That's the v0 surface. The name is broader on purpose - see [Where this is going](#where-this-is-going) below.

## Why

RuboCop 1.85+ exposes a built-in MCP server (`bundle exec rubocop --mcp`) with two tools: `rubocop_inspection` and `rubocop_autocorrection`. They return structured JSON instead of human-readable CLI output, which is the right substrate for an AI agent - but only if the agent knows the tool exists and when to call it.

Setting that up by hand across three assistants is fiddly and easy to get wrong. The first time I did it I forgot the `Stop` hook, the second time I clobbered an existing `.mcp.json`, the third time Codex silently ignored my hooks because I had not run `codex trust`. This gem makes it one command and tries to keep you from repeating any of those mistakes.

## Requirements

- Ruby ≥ 3.3
- Rails ≥ 7.0 (for the generator)
- `rubocop` ≥ 1.85 in the host app's Gemfile

## Installation

```ruby
# Gemfile
group :development do
  gem "railsdx", require: false
end
```

```bash
bundle install
bin/rails generate railsdx:install
```

Then restart your AI assistant so it loads the new MCP config. If you use Codex CLI, also read the [Codex trust step](#codex-trust-step-required-for-codex-hooks) below - hooks silently no-op until you do it.

## What gets written

The generator writes a small number of files and tries hard not to clobber anything you already have.

| File | Behavior |
| ---- | -------- |
| `AGENTS.md` | Section added between `<!-- railsdx:start -->` / `<!-- railsdx:end -->` markers. Re-running the generator replaces just our section; the rest of your file is untouched. Created if missing. |
| `CLAUDE.md` | Stub pointing to `AGENTS.md`. Same marker-based idempotency. |
| `.opencode/instructions.md` | Same as `CLAUDE.md`, for OpenCode. |
| `.mcp.json` | JSON-merged. Adds a `rubocop` entry under `mcpServers`. Skipped if `rubocop` is already registered. |
| `opencode.json` | JSON-merged. Adds a `rubocop` entry under `mcp`. Skipped if already registered. |
| Codex MCP (`~/.codex/config.toml`) | **Not auto-edited.** The generator prints the TOML snippet for you to paste. The MCP config is user-level, not project-level, and I do not want to touch your home directory silently. |
| `bin/rubocop-edited` | Shim that delegates to `bundle exec railsdx-check rubocop-edited`. Runs `rubocop -A` on the single file the agent just edited. Exit 0 = clean / autocorrected / not a Ruby file. Exit 2 + offense report on stderr = remaining offenses. |
| `bin/rubocop-changed` | Shim that delegates to `bundle exec railsdx-check rubocop-changed`. Runs RuboCop on every Ruby file modified in the working tree (tracked diffs, staged, untracked). Exit 0 = clean / nothing changed. Exit 2 + offense report on stderr = blocked. |
| `.claude/settings.json` | JSON-merged. Adds a `PostToolUse` hook (`Edit|Write|MultiEdit` → `bin/rubocop-edited`) **and** a `Stop` hook (→ `bin/rubocop-changed`). **Both blocking** - exit 2 re-enters the turn with the offense report. Preserves your other hooks and top-level keys; skipped per-hook if already wired. |
| `.codex/hooks.json` | JSON-merged. Same two hooks, same blocking behavior. Codex copied Claude's protocol so one merger drives both. **First-run gotcha:** see [Codex trust step](#codex-trust-step-required-for-codex-hooks). |
| `.opencode/plugins/rubocop-edited.js` | Bun-shell plugin that runs `bin/rubocop-edited` on `file.edited`. **Observation only** - OpenCode plugins cannot feed text back to the model, so remaining offenses are printed to the console. |
| `.opencode/plugins/rubocop-changed.js` | Bun-shell plugin that runs `bin/rubocop-changed` on `session.idle`. Same observation-only caveat. |

## Options

```bash
bin/rails generate railsdx:install --skip-claude            # no .mcp.json, CLAUDE.md, .claude/settings.json
bin/rails generate railsdx:install --skip-codex             # no Codex MCP snippet, no .codex/hooks.json
bin/rails generate railsdx:install --skip-opencode          # no opencode.json, instructions, or plugins
bin/rails generate railsdx:install --skip-stop-hook         # no bin/rubocop-changed and no Stop-hook configs
bin/rails generate railsdx:install --skip-rubocop-edited    # no bin/rubocop-edited and no PostToolUse configs
bin/rails generate railsdx:install --with-rubydex           # also wire rubydex (see docs/rubydex.md)
```

The skip flags compose: `--skip-claude --skip-codex` leaves only the OpenCode-side files; `--skip-stop-hook --skip-rubocop-edited` keeps the MCP setup but drops every safety-net artifact.

## The two workflows this enables

There are two distinct mechanisms in play here, and they catch different problems. I think it is worth understanding both before you install.

### 1. MCP tool calls (the primary path)

After install, the agent's instructions in `AGENTS.md` tell it to:

1. Call `rubocop_inspection` on every file it changed before declaring a task done.
2. Use `rubocop_autocorrection` rather than hand-editing offenses.
3. Never add `# rubocop:disable` to silence offenses without raising it with you first.
4. Stop and report if the MCP server is unavailable, rather than proceeding as if lint had passed.

The full text lives in the [AGENTS.md template](lib/generators/railsdx/install/templates/AGENTS.md.tt) - read it before running the generator so you know what you are committing to the repo.

This is the path that should fire 95% of the time. The agent reads the rules, calls the tools, and nothing else needs to happen.

### 2. Safety nets (defense in depth)

Even with the MCP tool sitting right there, agents skip it. Sometimes they forget. Sometimes they decide a file is "small enough not to lint." Sometimes the MCP server crashes and they keep going. So `railsdx` ships two complementary hooks that run regardless of what the MCP tools did or did not do.

**Mid-turn: `bin/rubocop-edited` (PostToolUse)**

Every time the agent calls `Edit`, `Write`, or `MultiEdit` on a Ruby file, this hook runs `bundle exec rubocop -A` on just that one file. Autocorrects are silent - the agent's next read of the file already sees the corrected version. Only when an offense cannot be autocorrected does the hook block the turn and surface the offense back to the model.

The point of this hook is that **style fixes never reach the post-turn check.** By the time the turn ends, the only offenses left are the ones a human (or the agent itself) needs to think about.

**Post-turn: `bin/rubocop-changed` (Stop / session.idle)**

When the agent is about to stop, this hook lints every Ruby file modified in the working tree - tracked diffs, staged changes, and untracked new files. If anything is wrong, exit 2 + the offense report on stderr re-enters the turn with the report as a continuation prompt.

The point of this hook is that **the agent cannot declare done while RuboCop is unhappy.**

| Agent | Mid-turn mechanism | Post-turn mechanism | Blocking? |
| ----- | ------------------ | ------------------- | --------- |
| Claude Code | `.claude/settings.json` `PostToolUse` | `.claude/settings.json` `Stop` | Both blocking |
| Codex CLI | `.codex/hooks.json` `PostToolUse` | `.codex/hooks.json` `Stop` | Both blocking (after `codex trust .codex/`) |
| OpenCode | `.opencode/plugins/rubocop-edited.js` (`file.edited`) | `.opencode/plugins/rubocop-changed.js` (`session.idle`) | Observation only |

Both hooks drive the same `bundle exec railsdx-check` command, so you can also run them from a git `pre-commit` hook, CI, or by hand:

```bash
bin/rubocop-changed
bin/rubocop-edited path/to/file.rb
```

## rubocop-server: faster hooks

Both hooks shell out to `bundle exec rubocop`. RuboCop's cold start is ~1-2 seconds on a small app and worse on a large one. When the PostToolUse hook fires after _every_ agent edit, that adds up fast.

The good news: RuboCop ships [`rubocop-server`](https://docs.rubocop.org/rubocop/usage/server.html), a daemon that keeps the configuration loaded between invocations. `railsdx` auto-detects when the server is running and passes `--server` for you - no flag, no config, no flag-flag-flag.

To turn it on for your project:

```bash
bundle exec rubocop --start-server
```

After that, both `bin/rubocop-edited` and `bin/rubocop-changed` will use the daemon automatically. You can force the behavior either way for CI or unusual environments:

```bash
RAILSDX_RUBOCOP_SERVER=1 bin/rubocop-changed    # force --server
RAILSDX_RUBOCOP_SERVER=0 bin/rubocop-changed    # never use --server
```

## Codex trust step (required for Codex hooks)

Codex CLI refuses to run scripts under `.codex/` until you trust the directory in this repo. Without this, the `Stop` and `PostToolUse` hooks `railsdx` writes will silently do nothing - which is the worst possible failure mode for a safety net.

Run this once per project, after the generator finishes:

```bash
codex trust .codex/
```

The generator prints a reminder. Do not skip it.

## Verifying the install

```bash
bundle exec railsdx-check doctor
```

The doctor reads `.claude/settings.json`, `.codex/hooks.json`, and `.opencode/plugins/` and reports per-check `✓` / `✗` against the expected wiring. It is read-only - it never modifies your config. Exit 0 means every expected hook is in place; exit 1 means something is missing. Re-run the install generator to fix gaps.

## Uninstall

There is no `--revert` flag yet. Here is the manual procedure - the gem only writes a small number of files, so this stays simple.

1. **Marker-delimited sections.** Delete the block between `<!-- railsdx:start -->` and `<!-- railsdx:end -->` (inclusive) in:
   - `AGENTS.md`
   - `CLAUDE.md`
   - `.opencode/instructions.md`

2. **JSON-merged entries.** Remove the `rubocop` key from:
   - `.mcp.json` under `mcpServers`
   - `opencode.json` under `mcp`
   - `.claude/settings.json` - delete any `hooks` group whose command is `bin/rubocop-changed` or `bin/rubocop-edited`
   - `.codex/hooks.json` - same as `.claude/settings.json`

3. **Standalone files.** Delete:
   - `bin/rubocop-changed`
   - `bin/rubocop-edited`
   - `.opencode/plugins/rubocop-changed.js`
   - `.opencode/plugins/rubocop-edited.js`

4. **State directory.** Delete `.railsdx/` if it exists (the doctor and checks drop a small JSON state file here).

5. **Codex MCP entry.** If you pasted the snippet into `~/.codex/config.toml`, remove the `[mcp_servers.rubocop]` block.

Then `bundle remove railsdx` from the Gemfile.

## Rubydex (opt-in, experimental)

`--with-rubydex` wires the [rubydex](https://github.com/shopify/rubydex) semantic-index MCP server. It is a separate story - structural search across Ruby code, user-scope registration, Rust binary prerequisite. The full instructions live in [docs/rubydex.md](docs/rubydex.md) so they do not crowd the main README.

## Where this is going

The name `railsdx` is broader than the v0 surface on purpose. RuboCop is the first thing every Rails-and-AI workflow needs, so it shipped first. The shape it established - generator drops config, optional safety-net hooks, host owns the underlying gem - is the shape future tools will follow.

On the roadmap:

- **Brakeman MCP wiring** when [`brakeman`](https://github.com/presidentbeef/brakeman) gains a stable MCP surface, with a `brakeman-changed` post-turn check and an AGENTS.md section that tells the agent when to read it.
- **Tests-changed safety net** - "if you touched a file under `app/`, you must have also touched a test." Optional, off by default.
- **Migration safety check** - opinionated guardrails for `db/migrate/*.rb` (no `change_column_null` without backfill, etc.).
- **Per-stack starter packs** - Hotwire, ViewComponent, Sidekiq - each contributing its own AGENTS.md section and (where it makes sense) its own MCP wiring.

Each addition follows the same contract: a `Railsdx::Checks::Base` subclass, an entry in the generator, a row in the doctor's expected-hooks list. See [docs/extending.md](docs/extending.md) for the contract.

## Development

```bash
bin/setup
rake test
```

### Running the gem's own checks

`bin/rubocop-changed` at the repo root is the same Ruby shim host apps get - it `exec`s `bundle exec railsdx-check rubocop-changed`. That command does not resolve inside the gem's own dev environment, because Bundler does not put a path-style gem's executables on the `bundle exec` PATH. When you want to run the checks against the gem itself, go through `exe/` directly:

```bash
bundle exec exe/railsdx-check rubocop-changed
bundle exec exe/railsdx-check rubocop-edited path/to/file.rb
bundle exec exe/railsdx-check doctor
```

If you would rather use the short names, generate the binstubs once and call them as `bin/railsdx-check`:

```bash
bundle binstubs railsdx
bin/railsdx-check rubocop-changed
```

The binstubs are gitignored - they are a personal convenience, not part of what the gem ships.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
