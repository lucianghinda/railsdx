# LLM Coding Session Quality Hooks Requirements

**Version:** 1.0
**Status:** Draft
**Date:** 2026-05-24

## Problem Frame

LLM coding agents (Claude Code, Codex CLI, OpenCode) ship code that mostly works, but routinely lands defects a human reviewer catches hours or days later — style drift, untested code paths, security regressions, broken types, fragile migrations, leaked secrets, malformed commit messages. The agent has no in-loop signal that the code is broken, because the harness only runs what the agent is told to run.

Both Claude Code and Codex now expose a rich hook system that fires at well-defined points in the session lifecycle (before tools, after tools, on turn end, on task completion, on session start). These hooks can run arbitrary commands, can block the agent, and can feed text back into the next model call. OpenCode has a weaker plugin system that observes the same events but cannot block.

`railsdx` already ships one slice of this design space: a `Stop`-hook that runs RuboCop on changed Ruby files for Claude+Codex (blocking) and OpenCode (observation). That is **one cell in a 2-D matrix** of (hook event × static-analysis tool). The rest of the matrix is greenfield.

The problem is not "make agents write good code" — that is unbounded. The problem is **catch every mechanically-detectable defect before the agent declares a task done**, while keeping the friction low enough that the session stays usable.

## Requirements

Each requirement is one cell in the (hook event × tool) matrix. Hook event names use Claude Code's spelling; Codex equivalents are noted parenthetically where they differ. OpenCode availability is called out per requirement when relevant.

| ID  | Requirement | Priority | Notes |
|-----|-------------|----------|-------|
| **R1** | **Per-edit RuboCop autocorrect.** PostToolUse hook on `Edit\|Write\|MultiEdit` runs `bundle exec rubocop -A --force-exclusion <file>` on the just-edited file. Sub-second target. Silent on success; surfaces remaining un-autocorrectable offenses via stderr so the model sees them on the next tool call. Changes intra-turn behavior — agent learns to write clean code by getting immediate feedback per edit instead of only at Stop. | Must Have | Claude + Codex (PostToolUse); OpenCode `file.edited` observation-only |
| **R2** | **Stop-hook test runner on changed paths.** Extends current `bin/rubocop-changed` model with `bin/tests-changed`: identifies test files corresponding to changed `.rb` files (Rails convention: `app/models/foo.rb` → `test/models/foo_test.rb`), runs only those. Exits 2 with failure summary on stderr. Bounded at ~30s; falls back to "no tests found, prompt the agent to write some" if a changed source file has no corresponding test. | Must Have | Claude + Codex (Stop); biggest single defect-catching upgrade after RuboCop |
| **R3** | **Stop-hook Brakeman scan on changed files.** `bin/brakeman-changed` runs `brakeman --only-files <changed> --quiet --no-progress`. Surfaces medium+ confidence findings. Catches SQL injection, mass assignment, unsafe redirects, command injection — exactly the defects LLMs introduce by reflex when writing Rails code. | Must Have | Claude + Codex (Stop); Rails-specific |
| **R4** | **SessionStart project context injection.** Hook fires when the agent's session begins and emits an `additionalContext` block summarising: Ruby + Rails versions, current branch, whether the test suite is passing on main, list of pending migrations, count of TODO comments in changed paths, last successful CI run if available. Saves the agent from N tool calls just to orient itself. | Must Have | Claude + Codex (SessionStart); OpenCode has no equivalent |
| **R5** | **PreToolUse gate for dangerous Bash commands.** Hook matcher on `Bash` with `if Bash(rails db:drop*\|rails db:reset*\|git push --force*\|git reset --hard*)` returns `permissionDecision: "deny"` with an explanation. Codex equivalent: PreToolUse with matcher on tool_name="Bash" plus content-based check in the hook script. Catches destructive operations the agent might reach for under pressure. | Must Have | Claude (richer `if` field); Codex (PreToolUse, content-check in script) |
| **R6** | **Strong_migrations preflight on migration edits.** PostToolUse hook on `Edit\|Write` filtered to `db/migrate/*.rb` runs `bundle exec rake db:migrate:status` and a `strong_migrations`-style lint. Surfaces unsafe operations (adding NOT NULL without default, removing columns without `safety_assured!`, renaming on large tables) before the agent commits. | Should Have | Claude + Codex (PostToolUse with path filter); Rails-specific; requires `strong_migrations` gem |
| **R7** | **Secret scan on commit-equivalent operations.** PreToolUse hook matched to `Bash(git commit*)` runs `gitleaks protect --staged --no-banner` and `bundle-audit check --update` against the changed files / Gemfile.lock. Blocks the commit if a secret is detected; surfaces the line. | Should Have | Claude + Codex (PreToolUse); Rails apps regularly leak `.env` content |
| **R8** | **Stop-hook bundler-audit + npm-audit.** Run `bundle-audit check --update` and (if `package.json` present) `npm audit --omit=dev` after any tool that touched `Gemfile.lock` or `package-lock.json`. Surfaces newly-introduced vulnerable dependencies as part of the turn-end battery. | Should Have | Claude + Codex (Stop); fast, well-understood |
| **R9** | **Stop-hook type check on changed files.** If Sorbet (`sorbet/config` present) or RBS+Steep (`Steepfile` present) is configured, run `srb tc <changed>` or `steep check <changed>`. Surfaces type errors introduced by changes. Skipped silently if no type system is configured. | Should Have | Claude + Codex (Stop); zero-config detection |
| **R10** | **PostToolUse(Bash) commit-message lint.** Hook matched to `Bash(git commit*)` parses the `-m` value and runs a conventional-commit linter (`commitlint`-style or a Ruby equivalent). Rewrites or blocks malformed messages. | Should Have | Claude + Codex (PostToolUse); minor but compounds repo hygiene |
| **R11** | **PostToolUse Edit/Write fast syntax check.** Before the heavier R1 RuboCop pass, run `ruby -wc <file>` for parse errors. Sub-100ms. Catches syntax errors that would otherwise pollute later tool output. | Should Have | Claude + Codex (PostToolUse); cheap insurance |
| **R12** | **TaskCompleted verification gate (Claude-only).** When the agent calls `TaskCreated` then later marks the task completed, the hook reads the last assistant message and the recent diff and requires evidence: did `bin/agent-check` exit 0 in this turn? If not, block task completion with `decision: "block"` + reason. Forces the agent to run the check before declaring done. | Should Have | Claude only (Codex has no TaskCompleted event); strong signal-to-noise |
| **R13** | **PostToolBatch aggregated lint after parallel edits (Claude-only).** Claude Code can edit multiple files in parallel; PostToolBatch fires once after the batch resolves. Run R1+R11 once across the union of edited files rather than per-edit. Reduces redundant runs when the agent does big refactors. | Should Have | Claude only (Codex has no PostToolBatch) |
| **R14** | **UserPromptSubmit context augmentation.** When the user submits a prompt mentioning specific files or models, inject a digest: file content, related test, related model associations. Saves the agent's first 3-5 exploratory tool calls. Must be tightly scoped (skip if the prompt isn't a coding task) to avoid context bloat. | Nice to Have | Claude + Codex (UserPromptSubmit); high-leverage but high-risk for noise |
| **R15** | **PreCompact session checkpoint.** Before compaction, dump the current changed-files list, last test result, and last RuboCop status to `.railsdx/session-state.json`. Agents can re-read this after compaction to recover state without re-discovering it. | Nice to Have | Claude + Codex (PreCompact); helps long sessions |
| **R16** | **OpenCode `session.idle` parity-as-much-as-possible.** For every Must Have hook above, ship an equivalent OpenCode plugin handler. Because OpenCode plugins cannot block, the plugin prints offenses to the console + writes them to `.opencode/last-check.json` for the next session to read. Documented as observation-only. | Nice to Have | OpenCode-specific; gracefully degrades the Claude/Codex story |
| **R17** | **Profile bundles.** Three named install profiles wrapping the requirements above: `minimal` (R1+R2+R4 — fast, no Rails-specific tools), `standard` (R1-R10 — current sweet spot), `paranoid` (R1-R15 — everything that's free of false-positive risk). User picks via `--profile=NAME` on `railsdx:install`. | Nice to Have | Cross-cutting; not a hook itself; install UX |
| **R18** | **Per-check opt-out flags.** Each Must/Should requirement gets a `--skip-NAME` flag (e.g., `--skip-tests-changed`, `--skip-brakeman`) for users who can't or don't want a specific tool. Mirrors existing `--skip-claude`, `--skip-codex`, `--skip-opencode` patterns. | Nice to Have | Install UX |

## Success Criteria

Measured one month after the feature ships:

- **Detection signal:** ≥3 of the requirements R1-R10 are running in at least 5 user projects. (We ship value if the hooks actually fire.)
- **Friction acceptance:** No user reports the per-edit hooks (R1, R11) as "too noisy to keep on." Sub-second target for per-edit must hold in real projects.
- **Defect catch rate (anecdotal, opt-in):** Users report that the hooks caught a real defect at least once. (Hard to instrument; gathered via issue comments / Twitter.)
- **No regression in MCP path:** The existing MCP+Stop-hook combo continues to work. New hooks compose, don't replace.

## Scope Boundaries

**In scope:**

- Static analysis hooks for Ruby + Rails projects (matches railsdx's existing positioning).
- Hook events available in Claude Code and Codex CLI. OpenCode treated as observation-only.
- Tools that exist as Ruby gems or well-known CLIs and don't require API keys or network calls (Brakeman, RuboCop, bundler-audit, gitleaks, Sorbet, Steep, strong_migrations).
- Per-hook configurability via skip flags.
- Documentation in `AGENTS.md` and `README.md` so all three agents understand what fires when.

**Out of scope:**

- **Semantic / behavioral quality.** "Is this the right solution?" "Did the agent understand the requirements?" — hooks can't catch this and the doc doesn't promise it.
- **LLM-on-LLM critique** (e.g., calling Claude to review Claude's output from inside a hook). Adds cost, latency, non-determinism. Out of scope for v1.
- **Non-Ruby ecosystems.** Whatever JS/Python tools exist would belong in sibling gems / npm packages, not railsdx.
- **Cloud telemetry / dashboards.** No "send the offenses to our server" feature. Everything runs locally.
- **Hook framework / DSL.** No "railsdx plugin SDK." Each check is a shell script in `bin/` invoked by a hook entry; the install generator wires the entries.
- **Editing the agent's actual prompt.** R14 *injects context*, it doesn't rewrite the user's prompt. We don't second-guess what the user wrote.

## Key Decisions

| Decision | Chosen | Rationale | Alternatives Considered |
|----------|--------|-----------|------------------------|
| Hook architecture | Per-hook specialization (Approach B from brainstorm session) | Different checks at different hook points maximize signal-per-cost. Fast feedback per edit changes the agent's intra-turn behavior, not just exit gate. | Single Stop-hook battery (current model, easier but less leverage); plugin framework (over-engineered). |
| Cross-agent strategy | Graceful degradation — Claude gets the richest set (29 events including TaskCompleted, PostToolBatch); Codex gets the shared subset; OpenCode is observation-only with `session.idle` parity. | Hook capabilities are fundamentally asymmetric. Pretending otherwise produces worst-of-all-worlds compromises. Better to honestly document the gradient. | Lowest-common-denominator (only ship what all three can do — loses Claude's exclusive events); separate gems per agent (more code, more docs). |
| Tool selection | Local CLIs only (RuboCop, Brakeman, bundler-audit, gitleaks, Sorbet/Steep, strong_migrations) | Deterministic, free, fast, no API keys. Matches the existing RuboCop precedent and the gem's name. | LLM-based critique (cost + latency + non-determinism); custom static analyzers (we're not in that business). |
| Distribution | Single gem (`railsdx`); each check is a shell script in `bin/`; install generator wires hook configs | Continues current model — `bin/rubocop-changed` already exists as the template. Adding `bin/tests-changed`, `bin/brakeman-changed`, etc. composes naturally. | Separate gems per check (fragments the install UX); plugin discovery via Bundler (premature). |
| Opt-out granularity | Both profile bundles (R17) **and** per-check skip flags (R18) | Two audiences: someone who wants "just give me the recommended set" picks a profile; someone tuning for their project skips individual checks. Both should compose. | Profiles only (less control); flags only (no curated default). |
| OpenCode positioning | Observation-only plugins, explicitly documented as such | OpenCode plugins genuinely cannot block. Telling users otherwise misleads them about the agent's behavior. | Skip OpenCode entirely (the gem already supports it for MCP — would create inconsistency). |

## Outstanding Questions

| #   | Question | Impact if Wrong | Owner |
|-----|----------|-----------------|-------|
| Q1  | Should per-edit hooks (R1, R11) fire on every Edit/Write, or only when the agent appears to have *stopped editing a file* (heuristic: no Edit on the same file in the next ~3 tool calls)? Per-edit is simpler; deferred is less noisy for big refactors. | Wrong: per-edit makes large refactors painful; deferred adds complexity and timing edge cases. | User to decide before R1 implementation. |
| Q2  | When `bin/tests-changed` (R2) can't find a test file for a changed source file, should it (a) fail and demand a test, (b) warn and continue, (c) noop silently? | Wrong (a): hostile to exploratory work, dead code refactors. Wrong (c): hides genuinely untested changes. | Recommend (b) with `--strict` for CI; needs user OK. |
| Q3  | Should R12 (TaskCompleted gate) require a *specific verification script* to have exited 0 in the turn, or accept any of: `rake test` clean, `bin/agent-check` clean, all hooks clean? | Wrong (too strict): false positives block legitimate task completion. Wrong (too loose): the hook becomes ceremony with no teeth. | Needs design pass when implementing R12. |
| Q4  | For R14 (UserPromptSubmit context augmentation): how do we decide a prompt is "a coding task" worth augmenting vs. a question/chat we shouldn't pre-load context for? Cheap heuristics (mentions a file path, mentions a Rails model name) miss cases; LLM-based detection violates "no LLM-in-hook" decision. | Wrong: either spammy injection on every prompt or miss the cases where it helps. | Defer R14 until R1-R10 ship and we have telemetry. |
| Q5  | Profile defaults (R17) — should `standard` include type checking (R9)? Type errors are real defects but Sorbet/Steep adoption is uneven; running them on a project without sigs/RBS produces noise. | Wrong: bad first-run experience if `standard` is noisy on a typical project. | Default: standard excludes R9; paranoid includes it. Confirm with user. |
| Q6  | Should we ship the actual hook scripts (`bin/tests-changed`, `bin/brakeman-changed`, …) as bash like `bin/rubocop-changed`, or as Ruby scripts that can share helpers (changed-file detection, output formatting)? | Wrong (bash): duplication, harder to test. Wrong (Ruby): adds bootstrap cost (must `bundle exec`). | Recommend Ruby scripts in a `lib/railsdx/checks/` runner. Decision deferred to implementation plan. |

## Hook × Tool Matrix (Reference Table)

Cross-reference of the requirements above against the available hook events. **Bold cells** are the proposed Must-Have implementations.

| Hook event           | Claude | Codex | OpenCode    | Proposed tool(s)                                                                 |
|----------------------|--------|-------|-------------|-----------------------------------------------------------------------------------|
| SessionStart         | ✅     | ✅    | ❌          | **R4: project context digest**                                                    |
| UserPromptSubmit     | ✅     | ✅    | ❌          | R14: scoped context augmentation                                                  |
| PreToolUse(Bash)     | ✅ (if)| ✅    | ❌          | **R5: dangerous-command gate**; R7: secret scan on `git commit`                   |
| PreToolUse(Edit/Write)| ✅    | ✅    | ❌          | (Reserved for future preflights)                                                  |
| PostToolUse(Edit/Write)| ✅ (if)| ✅   | `file.edited` obs | **R1: rubocop -A on changed file**; R11: ruby -wc; R6: strong_migrations on migrations |
| PostToolUse(Bash)    | ✅     | ✅    | `tool.execute.after` obs | R10: commit-message lint                                              |
| PostToolBatch        | ✅     | ❌    | ❌          | R13: aggregated lint after parallel edits                                         |
| Stop                 | ✅     | ✅    | `session.idle` obs | **R2: tests-changed**; **R3: brakeman-changed**; R8: bundler-audit; R9: type check |
| TaskCompleted        | ✅     | ❌    | ❌          | R12: verification gate                                                            |
| PreCompact           | ✅     | ✅    | ❌          | R15: session checkpoint                                                           |

## Performance Budget (Reference)

To keep the session usable, each hook event has a target wall-clock budget:

| Event class     | Budget | Rationale |
|-----------------|--------|-----------|
| PostToolUse(Edit/Write) | ≤ 1s | Fires per edit. Sub-second or the session crawls. |
| PostToolUse(Bash)       | ≤ 2s | Fires per shell command. Slightly looser. |
| PreToolUse              | ≤ 0.5s | Synchronous before tool runs. Must be near-instant. |
| SessionStart            | ≤ 3s | One-shot per session. More slack. |
| Stop                    | ≤ 30s | Fires once at turn end. Heaviest checks live here. |
| PostToolBatch           | ≤ 5s | Fires once per parallel batch. Aggregation lets it amortize. |
| PreCompact              | ≤ 1s | Should be fast or it interrupts compaction. |

Any check exceeding its event's budget must be deferred to Stop or split.

## What This Doc Does NOT Resolve

- Concrete implementation plan (file paths, generator templates, tests). That's a Phase 4 deliverable for the implementation of any specific requirement, written after the user picks which requirements to actually build first.
- Telemetry / metrics on whether hooks fire as intended in real projects.
- Compatibility matrix for older Claude Code / Codex versions that may lack some events.
- Exact behavior when a hook script is missing on a user's machine (graceful skip vs. install-time check).
