# LLM Quality Hooks MVP Plan (R1–R5)

**Version:** 1.1
**Status:** Ready for implementation (Phase 5 review folded in)
**Date:** 2026-05-24
**Source brainstorm:** `docs/brainstorms/llm-quality-hooks.md`
**Session log:** `docs/sessions/2026-05-24-llm-quality-hooks.md`
**Phase 5 review:** 6 P1 findings folded into Units 0/6 + Release Strategy (see "Phase 5 Findings Folded In" section at the bottom).

## Scope

Five concrete requirements from the brainstorm — R1, R2, R3, R4, R5 — built on a shared check framework (Unit 0). Goal: ship the v0.2 release that establishes the "per-hook specialization" architecture and proves out the framework with five real checks.

Out of plan: R6–R18 (deferred to v0.3+). Profile bundles (R17) and per-check opt-out flags (R18) will be designed once we see how the v0.2 checks behave in real projects.

## Architecture (one new abstraction)

```
lib/railsdx/checks/
├── base.rb            # Abstract base: changed-file detection,
│                      # exit-code + stderr conventions,
│                      # JSON state writer for OpenCode parity,
│                      # dispatch from bin/<name> scripts.
├── rubocop.rb         # R1: rubocop -A on a single file
├── tests_changed.rb   # R2: run only tests for changed source files
├── brakeman_changed.rb # R3: brakeman on changed files
├── session_context.rb # R4: emit additionalContext digest for SessionStart
└── dangerous_bash.rb  # R5: deny-list gate for dangerous Bash commands
```

Each `bin/<name>` template is a 4-line Ruby script that requires railsdx and dispatches to the matching check class. Hook configs reference `bin/<name>` so users can read/edit them.

## Implementation Units

### Unit 0: Check framework (foundation) — REVISED

**Goal:** Introduce `Railsdx::Checks::Base` (with Thor-backed dispatcher and standardized failure formatting); refactor the existing `bin/rubocop-changed` template to use it.

**Requirements trace:** Foundation for R1–R5 (and Unit 6 doctor). Doesn't satisfy a requirement on its own.

**Dependencies:** None.

**Files:**
- `lib/railsdx/checks.rb` — autoloader for the namespace (new)
- `lib/railsdx/checks/base.rb` — abstract base class (new)
- `lib/railsdx/checks/cli.rb` — Thor-backed subcommand dispatcher (new)
- `railsdx.gemspec` — declare `bin/railsdx-check` as a gem executable; no new dep (Thor comes via railties) (edit)
- `bin/railsdx-check` — gem-level executable that boots Thor CLI (new — this is the gem's exe, not a template)
- `lib/railsdx.rb` — `require "railsdx/checks"` (edit)
- `lib/generators/railsdx/install/templates/bin/rubocop-changed` — rewrite from bash to Ruby dispatch that shells to `bundle exec railsdx-check rubocop-changed` (edit)
- `test/checks/base_test.rb` — base class tests + interface contract test (new)
- `test/checks/cli_test.rb` — dispatcher tests (new)
- `test/generators/railsdx/install_generator_test.rb` — update assertion that the script content matches the new Ruby form (edit)

**Approach:** `Base` exposes `call(*argv)` → integer exit code. Subclasses implement `#run(argv)` which returns `Result.new(exit_code:, offenses: [], fix_hint: nil, state: nil)`. Base handles:
- Standardized failure formatting via `format_failure(check_name:, offenses:, fix_hint:)` → emits `[railsdx <check-name>] <file>:<line>:<col>: <message>\n…\n→ try: <fix_hint>` on stderr
- Writing optional JSON state to `.railsdx/last-check.json` (for the OpenCode plugin and the future R12 TaskCompleted gate to read)
- Exiting with the returned code

Changed-file helpers (`changed_ruby_files`, `changed_migrations`, `changed_test_files`) live on Base. No Rails dependency — pure stdlib + git + Thor.

`bin/railsdx-check` is a gem-level executable (shipped via `spec.executables`); user-level `bin/<check-name>` templates are 2-line shims that exec the gem's binary. Thor gives us `--help` / arg parsing / subcommand routing for free.

**Patterns:** Mirror the existing `bin/rubocop-changed` exit code contract (0/2). Standardized failure format becomes the **contract** every concrete check must use — pinned by the interface-contract test below so any Base refactor breaks loudly rather than silently misbehaving in subclasses.

**Test scenarios:**
- [ ] Happy: a check that returns `Result.new(exit_code: 0)` exits 0, writes nothing to stderr
- [ ] Failure: a check that returns `Result.new(exit_code: 2, offenses: [...], fix_hint: "...")` exits 2; stderr contains the formatted header, body, and `→ try:` line in that order
- [ ] Edge: `changed_ruby_files` in a fresh git repo with no commits returns `[]` without crashing
- [ ] Edge: invoking with `--help` prints Thor-generated usage and exits 0
- [ ] **Interface contract:** a test that subclasses `Base` with a fake check, calls every documented helper (`changed_ruby_files`, `changed_migrations`, `changed_test_files`, `format_failure`, `write_state`), and asserts each returns the documented type. Pinning the API stops a Base refactor from silently breaking the 5 subclasses.
- [ ] CLI dispatch: `bin/railsdx-check rubocop-changed` routes to `Railsdx::Checks::Rubocop` (or whatever Unit 1 wires)

**Verification:** `bundle exec rake test` passes. `bundle exec railsdx-check --help` lists registered subcommands. Running the rewritten `bin/rubocop-changed` against the railsdx gem itself produces exit 0 (smoke test).

**Planning-time unknowns:**
- *Deferred to planning:* exact `.railsdx/last-check.json` shape (R12 will expand; sketch minimum `{check, exit_code, timestamp}` for v0.2)
- *Resolved before planning:* no Rails dependency — confirmed, stdlib + Thor only.
- *Resolved before planning:* dispatcher via Thor — confirmed; railties already loads it, zero new deps.

---

### Unit 1: R1 — Per-edit RuboCop autocorrect (PostToolUse Edit/Write)

**Goal:** Run `bundle exec rubocop -A --force-exclusion <file>` on every file the agent edits, so style fixes happen mid-turn instead of accumulating until Stop.

**Requirements trace:** R1.

**Dependencies:** Unit 0.

**Files:**
- `lib/railsdx/checks/rubocop.rb` — wraps `bundle exec rubocop` with `-A` for autocorrect, `--no-color`, `--force-exclusion`. Accepts a single file path on argv. (new)
- `lib/generators/railsdx/install/templates/bin/rubocop-edited` — Ruby dispatch script (new)
- `lib/generators/railsdx/install/templates/stop_hook_settings.json` — add `PostToolUse` block alongside the existing `Stop` block (edit; rename file to `agent_hook_settings.json` since it now covers multiple events)
- `lib/generators/railsdx/install/templates/opencode_rubocop_edited.js` — `file.edited` plugin handler (new)
- `lib/generators/railsdx/install/install_generator.rb` — extend hook installer to also drop `PostToolUse` config + new OpenCode plugin; add `--skip-rubocop-edited` flag (edit)
- `lib/generators/railsdx/install/templates/AGENTS.md.tt` — document R1 in the safety-net section (edit)
- `test/generators/railsdx/install_generator_test.rb` — tests for the new hook entry, OpenCode plugin, skip flag (edit)

**Approach:** PostToolUse matcher = `Edit|Write|MultiEdit`. The hook script reads `tool_input.file_path` from stdin JSON (both Claude and Codex pass it there). For MultiEdit, the field is a list — the script runs RuboCop once across the list rather than once per file. Skip silently when the file isn't `*.rb`/`*.rake`/`*.gemspec`/`Gemfile`/`Rakefile`. Always exit 0 in autocorrect mode unless RuboCop returns un-autocorrectable offenses; surface those on stderr so they show up in the agent's next tool result.

**Patterns:** Same hook-merge plumbing as the existing Stop-hook installer (`merge_stop_hook` → generalize to `merge_event_hook(event:, ...)`). OpenCode plugin same Bun-shell shape as the existing `rubocop-changed.js`.

**Test scenarios:**
- [ ] Happy: file with no offenses → exit 0, silent
- [ ] Autocorrect: file with `'single'` quotes (project requires double) → rewrites file, exit 0, silent
- [ ] Failure: file with un-autocorrectable offense → exit 2, stderr has cop name + message
- [ ] Edge: non-Ruby file (e.g., `README.md`) → exit 0 silently, no RuboCop invocation
- [ ] Idempotency: PostToolUse hook added to existing `.claude/settings.json` preserves the Stop hook

**Verification:** Generator test fixture: install on a fresh dir, verify `.claude/settings.json.hooks.PostToolUse[].hooks[].command == "bin/rubocop-edited"`; same for `.codex/hooks.json`; OpenCode plugin file exists and references `bin/rubocop-edited`.

**Planning-time unknowns:**
- *Deferred to planning:* whether the script logs which file it autocorrected (useful for users to see, noisy for the agent). Default: silent on success.

---

### Unit 2: R2 — Tests on changed paths (Stop)

**Goal:** Run the test files corresponding to changed source files at Stop. Warn on missing tests; fail on red tests.

**Requirements trace:** R2.

**Dependencies:** Unit 0.

**Files:**
- `lib/railsdx/checks/tests_changed.rb` — heuristic source→test mapping; runner detection (minitest vs rspec); test invocation (new)
- `lib/generators/railsdx/install/templates/bin/tests-changed` — Ruby dispatch (new)
- `lib/generators/railsdx/install/templates/agent_hook_settings.json` — add second Stop-hook entry referencing `bin/tests-changed` (edit)
- `lib/generators/railsdx/install/install_generator.rb` — wire the new Stop entry; add `--skip-tests-changed` flag (edit)
- `lib/generators/railsdx/install/templates/AGENTS.md.tt` — document R2 (edit)
- `test/checks/tests_changed_test.rb` — heuristic tests (new)
- `test/generators/railsdx/install_generator_test.rb` — generator tests (edit)

**Approach:** Heuristic mapping: `app/models/foo.rb` → `test/models/foo_test.rb` (minitest) or `spec/models/foo_spec.rb` (rspec); `app/controllers/foos_controller.rb` → `test/controllers/foos_controller_test.rb` or `spec/`. Detection: presence of `spec/` directory + `rspec` in Gemfile → rspec; else minitest (Rails default). Run the matched tests with `bin/rails test <files>` or `bundle exec rspec <files>`. For changed source files with no matching test: stderr line `[railsdx tests-changed] no test found for <file>\n→ try: create test/<mirror_path>_test.rb`, exit 0. For test runs that fail: format via `Base.format_failure(check_name: "tests-changed", offenses: parsed_failures, fix_hint: "bundle exec rake test TEST=<failing_file>")`, exit 2.

**Patterns:** Reuse `changed_ruby_files` from `Checks::Base`. Filter to `app/**/*.rb` (and `lib/**/*.rb` if `lib/` looks like app code). Test runner invocation via `Open3.capture3` so we can capture and pass through both stdout (the failure summary) and exit code.

**Test scenarios:**
- [ ] Happy: changed model + passing test → runs test, exit 0
- [ ] Failure: changed model + failing test → exit 2 with failure output
- [ ] Warning: changed model + no test file → exit 0, stderr has "no test found"
- [ ] Edge: only `.md` changed → no tests to run → exit 0 silent
- [ ] Edge: no git repo → exit 0 silent (degrade gracefully)
- [ ] Heuristic: rspec detected when `spec/` exists and gemfile lists `rspec`

**Verification:** Integration test in a fixture Rails-like dir; modify a model file with corresponding passing test; run the script; assert exit 0. Modify the test to fail; run; assert exit 2.

**Planning-time unknowns:**
- *Deferred to planning:* timeout for test runs (default 30s from Stop budget; what if user's suite takes longer?). Probably let the test runner enforce its own timeout; we don't kill it.
- *Deferred to planning:* whether to also run tests when *test files themselves* change. Yes, makes sense — include `test/**/*_test.rb` in the changed-file scan.

---

### Unit 3: R3 — Brakeman on changed files (Stop)

**Goal:** Run Brakeman scoped to changed files at Stop. Surface medium+ confidence findings.

**Requirements trace:** R3.

**Dependencies:** Unit 0.

**Files:**
- `lib/railsdx/checks/brakeman_changed.rb` — invoke `brakeman --only-files <list> --quiet --no-progress --confidence-level=2` (new)
- `lib/generators/railsdx/install/templates/bin/brakeman-changed` — Ruby dispatch (new)
- `lib/generators/railsdx/install/templates/agent_hook_settings.json` — add Stop-hook entry (edit)
- `lib/generators/railsdx/install/install_generator.rb` — wire entry; add `--skip-brakeman-changed`; add Brakeman to next-steps as a recommended dependency (edit)
- `lib/generators/railsdx/install/templates/AGENTS.md.tt` — document R3 (edit)
- `test/checks/brakeman_changed_test.rb` — fixture-based test (new)
- `test/generators/railsdx/install_generator_test.rb` — generator tests (edit)

**Approach:** Skip silently if `config/routes.rb` doesn't exist (not a Rails app — legitimately not the right tool). If `brakeman` binary isn't on PATH: emit stderr line `[railsdx brakeman-changed] brakeman not installed\n→ try: bundle add brakeman --group=development` then exit 0 (don't block — the user opted in by installing railsdx, the gap is on their side, but say so loudly). Run with `--quiet`, `--no-progress`, `--confidence-level=2` (medium and high). Parse JSON output (`--format json`) and pass through `Base.format_failure(check_name: "brakeman-changed", offenses: findings, fix_hint: "bundle exec brakeman -A")`. Exit 2 if any findings.

**Patterns:** Same `Checks::Base` plumbing. Brakeman's `--only-files` accepts paths; pass the filtered changed list.

**Test scenarios:**
- [ ] Happy: changed file with no Brakeman finding → exit 0
- [ ] Failure: changed file with mass-assignment vulnerability → exit 2 with finding
- [ ] Edge: no `config/routes.rb` → exit 0 silently (not a Rails app)
- [ ] Edge: `brakeman` binary missing → stderr "brakeman not installed; skipping" + exit 0
- [ ] Edge: low-confidence finding → not surfaced (confidence < 2)

**Verification:** Fixture Rails-shaped dir with a deliberately vulnerable controller; run script; assert exit 2 and stderr contains the cop name.

**Planning-time unknowns:**
- *Deferred to planning:* whether to also fail on `--confidence-level=1` if a `--strict` flag is passed (CI use case). Probably yes; mirror `--strict` pattern from R2.

---

### Unit 4: R4 — SessionStart project context digest

**Goal:** When the agent starts a session, emit an `additionalContext` block summarising the project state so the agent doesn't burn its first 5 tool calls on orientation.

**Requirements trace:** R4.

**Dependencies:** Unit 0.

**Files:**
- `lib/railsdx/checks/session_context.rb` — gather Ruby version, Rails version (if any), current branch, pending migrations count, test framework, count of TODO/FIXME in changed paths; emit JSON (new)
- `lib/generators/railsdx/install/templates/bin/session-context` — Ruby dispatch (new)
- `lib/generators/railsdx/install/templates/agent_hook_settings.json` — add `SessionStart` block (edit)
- `lib/generators/railsdx/install/install_generator.rb` — wire entry; add `--skip-session-context` flag (edit)
- `lib/generators/railsdx/install/templates/AGENTS.md.tt` — short note about R4 (edit)
- `test/checks/session_context_test.rb` — output-shape tests (new)
- `test/generators/railsdx/install_generator_test.rb` — generator tests (edit)

**Approach:** Output a JSON object on stdout with shape `{"additionalContext": "Project context:\n- Ruby 3.3.6\n- Rails 8.0.1\n- Branch: feature/foo\n- Pending migrations: 2\n- Test framework: minitest\n- TODOs in app/: 3"}`. Both Claude Code and Codex CLI's `SessionStart` consume this shape. Skip silently when any data point can't be determined; never crash. Run under tight 3s budget — no slow operations like `bundle exec rails runner`.

**Patterns:** Pure stdlib. Read `Gemfile.lock` directly for version detection rather than booting Rails. Use `git rev-parse --abbrev-ref HEAD` for branch (graceful "detached HEAD" handling). `git status --porcelain db/migrate/*.rb` for pending migrations heuristic (or scan `db/schema.rb` against migration filenames).

**Test scenarios:**
- [ ] Happy: in a Rails app, emits valid JSON with all fields populated
- [ ] Edge: no `Gemfile` → emits minimal context with only git fields
- [ ] Edge: detached HEAD → branch field reads "detached" not crash
- [ ] Edge: no git repo at all → emits a one-line context, exit 0
- [ ] Performance: completes in <500ms on a typical Rails app (assertion via Benchmark in test)

**Verification:** Run `bin/session-context` in the railsdx repo; output is valid JSON parseable by `JSON.parse`; `additionalContext` string contains "Branch:".

**Planning-time unknowns:**
- *Deferred to planning:* whether to include `git diff --stat HEAD~5` as a "recent changes" hint. Adds tokens; defer to user feedback.
- *Deferred to planning:* matcher behavior — `source` field on SessionStart can be `startup|resume|clear|compact`. Fire on all four? Probably yes for `startup|resume`, skip on `clear|compact` to avoid context bloat.

---

### Unit 5: R5 — PreToolUse dangerous-Bash gate

**Goal:** Block the agent from running known-destructive shell commands without user approval.

**Requirements trace:** R5.

**Dependencies:** Unit 0.

**Files:**
- `lib/railsdx/checks/dangerous_bash.rb` — parses `tool_input.command` from stdin JSON; matches against an embedded deny-list of patterns; emits a hook decision JSON (new)
- `lib/generators/railsdx/install/templates/bin/dangerous-bash` — Ruby dispatch (new)
- `lib/generators/railsdx/install/templates/agent_hook_settings.json` — add `PreToolUse` block with `matcher: "Bash"` (edit)
- `lib/generators/railsdx/install/install_generator.rb` — wire entry; add `--skip-dangerous-bash` flag (edit)
- `lib/generators/railsdx/install/templates/AGENTS.md.tt` — document R5 + list the deny patterns (edit)
- `test/checks/dangerous_bash_test.rb` — pattern-match tests (new)
- `test/generators/railsdx/install_generator_test.rb` — generator tests (edit)

**Approach:** Deny-list patterns (regex):
- `\brails db:(drop|reset|setup)\b`
- `\brake db:(drop|reset|setup)\b`
- `\bgit push (.*)--force\b` or `--force-with-lease` excluded
- `\bgit reset --hard\b`
- `\bgit clean -f\b`
- `\brm -rf /\b`

When matched: emit `{"permissionDecision": "deny", "permissionDecisionReason": "...command...is in railsdx deny-list. Ask the user before running it."}` (Claude format) AND exit 2 with the same reason on stderr (Codex format). Both agents support exit 2 as a fallback if they don't see the JSON, so this dual-output approach works for both.

**Patterns:** Match Claude's hook decision JSON shape exactly. For commands with no match, exit 0 silently — do NOT emit `permissionDecision: "allow"`, that would suppress other PreToolUse hooks that might want to deny.

**Test scenarios:**
- [ ] Happy: `Bash(ls -la)` → exit 0, no JSON output
- [ ] Block: `Bash(rails db:drop)` → exit 2 with deny JSON; stderr has reason
- [ ] Block: `Bash(git push --force origin main)` → blocked
- [ ] Allow: `Bash(git push --force-with-lease origin feature)` → NOT blocked (safer variant)
- [ ] Block: nested via `bash -c "rails db:reset"` → blocked (regex matches inner command)
- [ ] Edge: malformed stdin JSON → stderr `[railsdx dangerous-bash] malformed tool_input on stdin`, exit 0 (loud-fail-open: don't break the agent, but say so)

**Verification:** Pipe a faked `tool_input` JSON to the script; assert exit code and JSON output match expected.

**Planning-time unknowns:**
- *Deferred to planning:* should the deny-list be user-extensible via `.railsdx/deny-bash.txt`? Yes, but for v0.2 ship with embedded list; add file-based extension in v0.3.
- *Deferred to planning:* `bash -c "..."` parsing — naive regex match against the full command string works for simple cases; complex shell quoting could evade. Acceptable for v0.2; document the limitation.

---

---

### Unit 6: Doctor command (post-install verification) — NEW from Phase 5

**Goal:** Give the user one command that tells them "your install actually works" — reads `.claude/settings.json`, `.codex/hooks.json`, and `.opencode/plugins/` and reports per-check `✓` / `✗` with the missing wiring named precisely.

**Requirements trace:** Cross-cutting; supports R1–R5 by closing the install verification gap. Not a brainstorm requirement on its own; promoted from Phase 5 P1 finding #3.

**Dependencies:** Unit 0.

**Files:**
- `lib/railsdx/checks/doctor.rb` — reads the three config files, walks the expected hook entries, reports per-check status (new)
- `lib/generators/railsdx/install/install_generator.rb` — append a line to next-steps output: `"Run \`bundle exec railsdx-check doctor\` to verify the install."` (edit)
- `lib/generators/railsdx/install/templates/AGENTS.md.tt` — short note about the doctor command (edit)
- `test/checks/doctor_test.rb` — fixture-based tests covering all-installed, partial-install, none-installed (new)

**Approach:** Subcommand on the Thor CLI. Output table:

```
railsdx-check doctor
====================
Claude Code (.claude/settings.json)
  ✓ Stop hook → bin/rubocop-changed
  ✓ PostToolUse hook → bin/rubocop-edited
  ✗ SessionStart hook missing (R4 not wired)

Codex CLI (.codex/hooks.json)
  ✓ Stop hook → bin/rubocop-changed
  ✗ PreToolUse hook missing (R5 not wired)

OpenCode (.opencode/plugins/)
  ✓ rubocop-changed.js
  ✗ rubocop-edited.js missing (R1 not wired)

Run `bin/rails generate railsdx:install` to install missing pieces.
```

Exit 0 if everything that should be wired is wired; exit 1 if anything is missing. Skip a section entirely if the agent's config file doesn't exist (user opted out via `--skip-claude` etc.).

**Patterns:** Pure read-only inspection. No mutation. Uses `Base` for nothing except the Thor command registration; no changed-file detection needed.

**Test scenarios:**
- [ ] Happy: full install → exit 0, all `✓`
- [ ] Partial: only Claude installed → exit 1, Claude all `✓`, Codex section omitted (file not present)
- [ ] Wrong wiring: settings.json has Stop hook but command name mismatches → exit 1 with `✗ Stop hook points to bin/wrong-name, expected bin/rubocop-changed`
- [ ] No install at all → exit 1 with `No railsdx config detected. Run \`bin/rails generate railsdx:install\`.`

**Verification:** Fixture project with various combinations of installed/missing configs; assert doctor output and exit code per fixture.

**Planning-time unknowns:**
- *Deferred to planning:* `--fix` flag that re-runs the generator for missing pieces. Tempting; defer to v0.3 to keep doctor read-only for v0.2.

---

## Dependency DAG

```
Unit 0 (framework + Thor + format_failure)
  ├── Unit 1 (R1 RuboCop autocorrect)
  ├── Unit 2 (R2 tests-changed)
  ├── Unit 3 (R3 brakeman-changed)
  ├── Unit 4 (R4 SessionStart context)
  ├── Unit 5 (R5 dangerous-bash)
  └── Unit 6 (doctor command, post-install verification)
```

Units 1–6 are mutually independent. Can ship as one PR or staggered.

## Quality Bar Checklist

- [x] Every unit has a requirements trace (Units 1–5 → R1–R5; Unit 0 is foundation, traced to "supports R1-R5")
- [x] Dependencies form a DAG (no cycles — Unit 0 has no dependencies; Units 1–5 depend only on Unit 0)
- [x] Every unit has at least 3 test scenarios (all units have 4–6)
- [x] No unit touches >8 files (max is Unit 1 at 7 files; close but under limit)
- [x] No more than 2 new abstractions per unit (Unit 0 introduces exactly 1: `Railsdx::Checks::Base`; Units 1–5 each add one concrete subclass which is not a "new abstraction" — it's an instance of the existing one)
- [x] Every planning-time unknown classified as "Resolve Before Planning" or "Deferred to Planning"
- [x] Handoff completeness test: a competent engineer can execute each unit without inventing product behavior — only implementation details remain

## Release Strategy

**v0.2.0 candidate:** Unit 0 + Unit 1 + Unit 2 + Unit 6. That's the minimum coherent shipping increment — framework plus the two most impactful checks (intra-turn style + turn-end tests) plus the doctor so users can verify the install. Unit 6 is cheap (~100 lines) and a force multiplier for everything that follows.

**v0.2.x patches:** Add Unit 3 (Brakeman), Unit 4 (SessionStart), Unit 5 (dangerous-Bash) as separate releases or batched depending on review cycle.

**Migration story:** Existing `bin/rubocop-changed` users get the script rewritten under their feet on next `bin/rails generate railsdx:install`. Hook configs already reference `bin/rubocop-changed` — no config migration needed. The rewritten script delegates to `bundle exec railsdx-check rubocop-changed`. Add a CHANGELOG entry calling out the rewrite + the new gem-level executable.

**End-to-end fixture integration test (cross-cutting):** Before shipping v0.2, add `test/integration/hooks_e2e_test.rb` that:
1. Boots a fixture Rails-shaped project under `test/fixtures/sample_app/`
2. Runs the install generator against it
3. For each installed hook, fakes the input the agent would pipe in (PostToolUse JSON, Stop event JSON, etc.) and exec's `bin/railsdx-check <name>`
4. Asserts the expected exit code and stderr format

Without this, unit tests cover each check in isolation but nothing verifies the "hook config → script invocation → stderr" loop the agent actually traverses. This is the gap that lets subtle hook-config bugs ship.

## What This Plan Does NOT Cover

- v0.3 requirements (R6–R18): strong_migrations, secret scan, bundler-audit, type check, commit-message lint, syntax check, TaskCompleted gate, PostToolBatch aggregation, UserPromptSubmit augmentation, PreCompact checkpoint, OpenCode parity matrix, profile bundles, skip-flag UX.
- README + CHANGELOG copy. Will be drafted as part of Unit 1's PR (since Unit 1 is the user-visible shipping behavior).
- Performance benchmarking harness. Each unit has a performance test scenario, but a centralized benchmark suite is out of scope for v0.2.
- Telemetry on hook firing in the wild. No instrumentation built in.

## Phase 5 Findings Folded In

| # | Finding | Resolution |
|---|---------|------------|
| 1 | Silent failures (brakeman missing, malformed stdin, generic skips) | Units 3 and 5 updated to emit `[railsdx <name>] <reason>` on stderr and exit 0 (loud-fail-open). Unit 4 unchanged — per-field silent fallback was already intentional and the script as a whole always emits something. |
| 2 | Stderr format unspecified for Units 2 and 3 | Pinned via `Base.format_failure(check_name:, offenses:, fix_hint:)` helper. Units 2 and 3 explicitly call it. |
| 3 | No install-time verification | Added Unit 6 (doctor command) — reads three config files, reports per-check ✓/✗, exits non-zero if anything is missing. Wired into Release Strategy as part of v0.2.0 candidate. |
| 4 | No "→ try:" fix-hint at end of failures | Part of `Base.format_failure` contract: always emits a final `→ try: <command>` line. All concrete checks supply the hint. |
| 5 | Thor not chosen for dispatcher | Unit 0 explicitly uses Thor. Comes via railties (no new dep). Free `--help`, arg parsing, subcommand routing. |
| 6 | No interface-contract test for `Checks::Base` and no end-to-end fixture test | Unit 0 test scenarios include "interface contract" test that exercises every documented Base helper. End-to-end fixture test added to Release Strategy as a gating item for v0.2. |
