# Rubydex via railsdx

> ⚠ **Experimental.** Upstream [rubydex](https://github.com/shopify/rubydex) ships its MCP server as experimental and the project is moving fast - tool names, the launch command, and even the existence of the MCP entrypoint may change. Watch the upstream repo; expect to revisit this integration. If/when rubydex stabilizes, this warning will come off (and the integration may flip on by default).

I had to learn this the hard way: when an AI agent reasons about a Ruby codebase using `Grep`, it does not actually know what a class is. It knows about lines of text that happen to look like a class. A search for `Bar` finds `Foo::Bar`, `Other::Bar`, the word `bar` in a comment, and the variable `bar` in someone's test. The agent has to filter through all of that with no structural context.

[Rubydex](https://github.com/shopify/rubydex) is a semantic Ruby indexer that builds a resolved, ancestry-aware index of the codebase. It exposes that index over MCP. For structural questions about Ruby code - "where is this defined?", "what inherits from this?", "who references this constant?" - it is strictly better than text search.

`railsdx --with-rubydex` wires it into your AI assistants' **project-local** MCP configs without you having to write any of the registration files by hand.

## The tools rubydex exposes

- `search_declarations` - fuzzy-find classes, modules, methods, constants by name.
- `get_declaration` - full details (docs, ancestors, members, definitions) for a fully-qualified name.
- `get_descendants` - every class/module that inherits from or includes a given one.
- `find_constant_references` - all resolved usages of a constant across the codebase.
- `get_file_declarations` - structural overview of a single file.
- `codebase_stats` - high-level metrics about the indexed tree.

## When to prefer rubydex over `Grep`

| Task | Reach for |
|------|-----------|
| "Where is `Foo::Bar` defined?" | `get_declaration` |
| "What includes `Notifiable`?" | `get_descendants` |
| "Who calls `PAYMENT_TIMEOUT`?" | `find_constant_references` |
| "Does a method named `publish` exist anywhere?" | `search_declarations` |
| Substring/regex grep for a literal string | `Grep` (rubydex does not index string literals) |

The point is structural awareness. `find_constant_references` for `Bar` returns the precise resolved hits and nothing else. `Grep "Bar"` returns everything that contains the letters B-a-r. Different tools for different questions.

## Why it is off by default

Two reasons. Both matter.

1. **The MCP server is a Rust binary.** You install it with `cargo install --path rust/rubydex-mcp` from a clone of `shopify/rubydex`. Not every teammate has a Rust toolchain.

2. **The integration is genuinely experimental.** Upstream rubydex's MCP surface is still moving. Pinning a project to it today means committing a registration that may need rewriting next month.

Project-local registration is the right shape for this gem: every other file `railsdx` writes lives under `Rails.root`, and rubydex now follows the same rule. If you would rather register rubydex at user scope (one entry covers every project), that is a perfectly reasonable choice - just do it by hand in `~/.claude.json` / `~/.codex/config.toml` / `~/.config/opencode/opencode.json` and skip `--with-rubydex`.

## What `--with-rubydex` does

Four things:

1. Adds a "Rubydex via MCP" section to `AGENTS.md` documenting the tools and when to prefer them over `Grep`.
2. Merges a `rubydex` entry into `.mcp.json` for Claude Code.
3. Merges a `[mcp_servers.rubydex]` block into `.codex/config.toml` for Codex CLI.
4. Merges a `rubydex` entry into `opencode.json` for OpenCode.

It honors `--skip-claude` / `--skip-codex` / `--skip-opencode`: e.g. `--with-rubydex --skip-opencode` wires rubydex in Claude and Codex but leaves `opencode.json` alone.

Each registration uses `${HOME}/.cargo/bin/rubydex_mcp` as the command path. The agents that read these configs are responsible for expanding the variable; if your binary lives elsewhere you will need to edit the registered command after install.

## Prerequisite: install the binary

```bash
git clone https://github.com/shopify/rubydex
cd rubydex
cargo install --path rust/rubydex-mcp
```

The generator looks for the binary at `${HOME}/.cargo/bin/rubydex_mcp` and warns you if it is missing.

## Running the generator

```bash
bin/rails generate railsdx:install --with-rubydex
```

Restart the assistant after install and the rubydex tools (`mcp__rubydex__*`) should appear in its tool list.

For Codex CLI specifically: the local MCP server registration is gated on project trust. If you have not yet run `codex trust .codex/` in this repo, do it now - otherwise Codex will silently skip the rubydex entry along with everything else under `.codex/`.

## If rubydex is unavailable

The agent instructions already say this, but to be explicit: if the `mcp__rubydex__*` tools are not listed, the agent falls back to `Grep` but tells you so. I want the degradation to be loud rather than silent - otherwise you do not know whether the agent is reasoning about structure or about text.

## Resources

- [Rubydex repository](https://github.com/shopify/rubydex)
- [RuboCop MCP server docs](https://docs.rubocop.org/rubocop/latest/usage/mcp.html) - the sibling integration `railsdx` wires by default
- [Model Context Protocol](https://modelcontextprotocol.io/) - the protocol both servers speak
