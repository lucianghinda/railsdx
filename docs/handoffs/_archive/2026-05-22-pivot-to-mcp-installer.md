---
created: 2026-05-22T12:19:05Z
branch: main
trigger: manual
restored: true
restored_at: 2026-05-22T15:25:00Z
topic: pivot-to-mcp-installer
---

# Handoff: Pivot railsdx from custom cops to RuboCop MCP installer

## Goal

Reshape the `railsdx` gem from "custom RuboCop cops for Rails" into a single-purpose installer that wires the **RuboCop MCP server** (`bundle exec rubocop --mcp`, RuboCop 1.85+) into Claude Code, Codex, and OpenCode. The gem's value is the integration glue — registering the MCP server with each agent and giving the agent instructions on when to use `rubocop_inspection` / `rubocop_autocorrection` — not curated cops, since rubocop-rails already covers nearly every safety rule we considered.

## Current State

- **All custom cops removed.** `lib/rubocop/`, `lib/rubocop-railsdx.rb`, `config/default.yml`, `test/cops/`, `test/support/` are deleted (shown as `D` in git status). The `NoTimeNow` and `NoSqlStringInterpolation` cops are gone — user explicitly chose this even though `NoSqlStringInterpolation` had no rubocop-rails equivalent.
- **Rails generator scaffolded** at `lib/generators/railsdx/install/install_generator.rb`. Invokes via `bin/rails generate railsdx:install`. Loads cleanly (verified with `bundle exec ruby` smoke test).
- **Templates written** under `lib/generators/railsdx/install/templates/`:
  - `AGENTS.md.tt` — workflow contract for the agent (the only opinionated content)
  - `CLAUDE.md.tt`, `opencode_instructions.md.tt` — pointers back to AGENTS.md
  - `mcp/claude_code.json` — `.mcp.json` template
  - `mcp/codex.toml` — printed for manual paste into `~/.codex/config.toml`
  - `mcp/opencode.json` — `opencode.json` template
- **Idempotency strategy:** markdown files use `<!-- railsdx:start -->` / `<!-- railsdx:end -->` markers so re-running replaces just our section. JSON files are parsed-and-merged (skip if `rubocop` server already present).
- **Gemspec updated:** dropped `lint_roller`, `rubocop`, `rubocop-ast` deps and `default_lint_roller_plugin` metadata. Added `railties >= 7.0` for `Rails::Generators::Base`. `rubocop` is intentionally NOT a dep — host app supplies it.
- **README rewritten** around the new framing.
- **Nothing committed yet.** All changes are working-tree only.

## Key Decisions

- **Pivot from cops to integration glue** — rationale: web search confirmed `rubocop-rails` already covers `Rails/TimeZone`, `Rails/SkipsModelValidations`, `Rails/OutputSafety`, `Rails/EnvironmentVariableAccess`, etc. Only `NoSqlStringInterpolation` had no equivalent (Brakeman territory). Building parallel cops is low-leverage; wiring the MCP server is unique value.
- **Remove existing cops entirely (not opt-in)** — user's call. Cleaner scope; the gem becomes single-purpose.
- **AGENTS.md as source of truth, CLAUDE.md/opencode stubs point to it** — user's call. Avoids content drift across three duplicate files.
- **Rails generator over plain executable or rake task** — user's call. Native Rails feel; pulls in `railties` as a dep but generators are lazy-loaded.
- **Codex TOML config is printed, not auto-edited** — Codex config lives in `~/.codex/config.toml` (user-level, not project-level). Silently editing the user's home dir is too invasive for a project-local generator.
- **Marker-block idempotency over full-file ownership** — lets users edit freely around our section; re-running only replaces between markers.

## Modified Files

Working tree (uncommitted):

- `Gemfile` — bumped rubocop to `~> 1.85`, reordered deps
- `Gemfile.lock` — regenerated via `bundle install`
- `README.md` — full rewrite around MCP integration
- `Rakefile` — removed RuboCop rake task (gem no longer ships cops)
- `railsdx.gemspec` — dropped rubocop/lint_roller deps, added railties
- `test/test_helper.rb` — stripped rubocop/cop_test_helper requires
- `lib/generators/railsdx/install/install_generator.rb` — **new**
- `lib/generators/railsdx/install/templates/AGENTS.md.tt` — **new**
- `lib/generators/railsdx/install/templates/CLAUDE.md.tt` — **new**
- `lib/generators/railsdx/install/templates/opencode_instructions.md.tt` — **new**
- `lib/generators/railsdx/install/templates/mcp/claude_code.json` — **new**
- `lib/generators/railsdx/install/templates/mcp/codex.toml` — **new**
- `lib/generators/railsdx/install/templates/mcp/opencode.json` — **new**
- Deletions: `config/default.yml`, `lib/rubocop-railsdx.rb`, `lib/rubocop/cop/railsdx/no_time_now.rb`, `lib/rubocop/cop/railsdx/no_sql_string_interpolation.rb`, `lib/rubocop/railsdx/plugin.rb`, `test/cops/railsdx/no_time_now_test.rb`, `test/cops/railsdx/no_sql_string_interpolation_test.rb`, `test/support/cop_test_helper.rb`

## Failed Approaches

- **Suggested adding more custom cops first** (`NoSkipCallbacks`, `NoRawHtml`, `NoEnvInRuntimeCode`, N+1 detection). User pushed back asking whether rubocop-rails already covers them. Web search confirmed near-total overlap. This is what triggered the pivot. *Don't propose new cops in this gem.*
- **Initially proposed shipping a curated `.rubocop.yml` preset** that turned on the rubocop-rails safety cops at error severity. User explicitly rejected this: "I don't want to provide a list of cops, but just the integration with rubocop MCP." *Don't add cop config to the gem.*

## Files to Read

- `lib/generators/railsdx/install/install_generator.rb` — the only meaningful Ruby in the gem now
- `lib/generators/railsdx/install/templates/AGENTS.md.tt` — the workflow contract; the gem's actual opinion
- `README.md` — current public framing
- `RESEARCH.md` at parent repo root (`/Users/luciang/Dropbox/workprojects/explorations/setting-up-rails-for-working-with-ai/RESEARCH.md`) — background research that informed early direction

## Next Steps

1. **Write tests for the generator.** Currently zero test coverage. At minimum: smoke test that `InstallGenerator` runs in a tmpdir, creates expected files, and is idempotent on re-run. Use `Rails::Generators::TestCase` or just drive it via Thor in a tmpdir.
2. **Verify the generated MCP config snippets actually work** end-to-end against real Claude Code, Codex, and OpenCode installs. The JSON shapes are based on docs + memory; worth one round of manual validation before tagging a release.
3. **Decide whether to support a `--skip-agents-md` option** for users who prefer to manage their AGENTS.md by hand. Symmetry with the existing `--skip-claude` / `--skip-codex` / `--skip-opencode` flags.
4. **Commit and bump the version.** Major version bump warranted — the gem's public surface has completely changed (cops gone, generator new).
5. **Update CHANGELOG.md** documenting the breaking pivot.
6. **Consider an integration mode for non-Rails Ruby projects.** Right now the gem requires `railties` for the generator. A plain Ruby app that wants this wiring has no path. Possible future addition: a `railsdx` executable that calls the same logic without `Rails::Generators`.

## Open Questions

- **Naming:** is `railsdx` still the right gem name now that it's purely an MCP installer with no Rails-specific cops? The MCP server itself is RuboCop-general, not Rails-specific. Possible rename: `rubocop-mcp-installer`, `agentbridge`, or keep `railsdx` since the target audience is still Rails developers and Rails generators are the install path.
- **Codex config strategy:** should we provide a `--write-codex` flag that *does* modify `~/.codex/config.toml` (with a TOML library)? Currently we only print the snippet. Trade-off: less hand-work for users vs. silently touching `$HOME`.
- **AGENTS.md content review:** the workflow rules in `AGENTS.md.tt` are my draft, not the user's words. Worth a pass from the user to make sure the tone and specifics match how they actually want agents to behave.
- **Should the gem ship a `bin/railsdx-check` script** that the user can wire into pre-commit / CI to verify the MCP server is reachable? Out of scope for v1 but worth noting.
