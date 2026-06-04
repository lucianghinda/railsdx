# Rubydex via railsdx

> ⚠ **Experimental.** Upstream [rubydex](https://github.com/shopify/rubydex) ships its MCP server as experimental and the project is moving fast - tool names, the launch command, and even the existence of the MCP entrypoint may change. Watch the upstream repo; expect to revisit this integration. If/when rubydex stabilizes, this warning will come off (and the integration may flip on by default).

I had to learn this the hard way: when an AI agent reasons about a Ruby codebase using `Grep`, it does not actually know what a class is. It knows about lines of text that happen to look like a class. A search for `Bar` finds `Foo::Bar`, `Other::Bar`, the word `bar` in a comment, and the variable `bar` in someone's test. The agent has to filter through all of that with no structural context.

[Rubydex](https://github.com/shopify/rubydex) is a semantic Ruby indexer that builds a resolved, ancestry-aware index of the codebase. It exposes that index over MCP. For structural questions about Ruby code - "where is this defined?", "what inherits from this?", "who references this constant?" - it is strictly better than text search.

`railsdx --with-rubydex` wires it into your AI assistants without you having to write any of the registration files by hand.

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

2. **The launch command takes no path argument.** `rubydex_mcp` indexes whichever directory it is launched in. That makes **user scope** the right registration: one entry in `~/.claude.json` / `~/.codex/config.toml` / `~/.config/opencode/opencode.json` covers every Ruby project you `cd` into, with nothing committed to any repo.

Project-scope registration would lock the binary path into the repo, which is the wrong tradeoff for a binary that you may or may not have installed yet.

## What `--with-rubydex` does

Three things, none of them silent.

1. Adds a "Rubydex via MCP" section to `AGENTS.md` documenting the tools and when to prefer them over `Grep`.
2. Prints the exact `claude mcp add --scope user rubydex …` command for Claude Code.
3. Prints copy-paste TOML/JSON snippets for the Codex and OpenCode user-level config files. **No home-directory files are auto-edited.**

It honors `--skip-claude` / `--skip-codex` / `--skip-opencode`: e.g. `--with-rubydex --skip-opencode` skips the OpenCode snippet.

## Prerequisite: install the binary

```bash
git clone https://github.com/shopify/rubydex
cd rubydex
cargo install --path rust/rubydex-mcp
```

The generator looks for the binary at `${HOME}/.cargo/bin/rubydex_mcp` and warns you if it is missing. If you have it in another location, you will have to edit the printed snippets before pasting.

## Running the generator

```bash
bin/rails generate railsdx:install --with-rubydex
```

Then follow the printed instructions for each assistant. For Claude Code that is a single `claude mcp add` command; for Codex and OpenCode you paste a small block into the user-level config file.

After that, restart the assistant and the rubydex tools (`mcp__rubydex__*`) should appear in its tool list.

## If rubydex is unavailable

The agent instructions already say this, but to be explicit: if the `mcp__rubydex__*` tools are not listed, the agent falls back to `Grep` but tells you so. I want the degradation to be loud rather than silent - otherwise you do not know whether the agent is reasoning about structure or about text.

## Resources

- [Rubydex repository](https://github.com/shopify/rubydex)
- [RuboCop MCP server docs](https://docs.rubocop.org/rubocop/latest/usage/mcp.html) - the sibling integration `railsdx` wires by default
- [Model Context Protocol](https://modelcontextprotocol.io/) - the protocol both servers speak
