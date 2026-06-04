# Extending railsdx: writing a new check

When I designed `Railsdx::Checks::Base`, I had one constraint in mind: a new check should be a single file. Not a file plus a CLI wiring plus a generator wiring plus a doctor wiring - just _the check_. That goal turned out to be aspirational. Today a new check is four touchpoints. This document explains all four and why each exists.

If you are landing a check that already has a corresponding RuboCop / Brakeman / whatever MCP server, the contract here is what your check has to satisfy.

Let's start.

## The mental model

Every railsdx check is a small Ruby class that:

1. Knows how to figure out _what_ to look at (usually "files changed in the working tree").
2. Shells out to a tool that has an opinion about whether those files are OK.
3. Returns a `Result` saying clean / dirty + the offenses.

The `Base` class handles the cross-cutting concerns: stderr formatting in the railsdx contract, JSON state writing at `.railsdx/last-check.json`, turning the `Result` into a process exit code, exposing git helpers for "what changed."

A subclass implements `#run(argv)` and returns a `Checks::Result`. That is the whole contract.

## The four touchpoints

When you add a check, you touch these four places. The pattern is intentional - each touchpoint is doing different work for a different consumer.

### 1. The check class itself (`lib/railsdx/checks/<name>.rb`)

```ruby
module Railsdx
  module Checks
    class TestsChanged < Base
      def check_name = "tests-changed"

      def run(_argv)
        return Result.new(exit_code: 0) if repo_root.nil?

        Dir.chdir(repo_root) do
          missing = files_without_tests
          return Result.new(exit_code: 0) if missing.empty?

          Result.new(
            exit_code: 2,
            offenses: missing.map { |f| { file: f, message: "no test touched" } },
            fix_hint: "add or update a test under test/ or spec/ for each file above",
            state: { missing: missing }
          )
        end
      end

      private

      def files_without_tests
        # ... uses changed_ruby_files from Base
      end
    end
  end
end
```

Two things worth knowing:

- **`check_name` should be the kebab-case name.** It shows up in `[railsdx <name>]` stderr headers and in the `.railsdx/last-check.json` state file. The default derivation from the class name is "TestsChanged" → "tests-changed", so you usually do not need to override it. Override only if the class name and the desired CLI name diverge.
- **The `Result` shape is the public contract.** `exit_code`, `offenses`, `fix_hint`, `state`. The `Base#emit` method renders the failure header from `offenses` and the fix hint, and `Base#write_state` persists the state hash. The exit code is what the hook sees - `0` means OK, `2` means the agent should re-enter the turn with the offense report.

### 2. The autoload entry (`lib/railsdx/checks.rb`)

```ruby
module Checks
  autoload :Base,           "railsdx/checks/base"
  autoload :CLI,            "railsdx/checks/cli"
  autoload :Doctor,         "railsdx/checks/doctor"
  autoload :Result,         "railsdx/checks/result"
  autoload :RubocopChanged, "railsdx/checks/rubocop_changed"
  autoload :RubocopEdited,  "railsdx/checks/rubocop_edited"
  autoload :TestsChanged,   "railsdx/checks/tests_changed"   # <- add here
end
```

I could have made this reflection-based. I deliberately did not - explicit autoload makes the list of available checks readable in one place, which is more important than the one line of typing it saves.

### 3. The CLI dispatcher (`lib/railsdx/checks/cli.rb`)

```ruby
desc "tests-changed", "Verify every changed app/ file has a matching test edit"
def tests_changed(*files)
  exit Checks::TestsChanged.new.call(files)
end
```

Each subcommand is a 1:1 mapping to a check class. The Thor `desc` line is what shows up in `railsdx-check help`. Same reasoning as the autoload list - keeping the dispatcher explicit makes the surface readable.

### 4. The doctor row (`lib/railsdx/checks/doctor.rb`)

If your check is wired into agent hooks (most are), it goes in `EXPECTED_HOOKS`:

```ruby
{
  check: "tests-changed",
  claude: { event: "Stop", command: "bin/tests-changed" },
  codex: { event: "Stop", command: "bin/tests-changed" },
  opencode: ".opencode/plugins/tests-changed.js"
}
```

The doctor walks this list and reports per-row `✓` / `✗`. Adding a row here is how you make the new check observable to `bundle exec railsdx-check doctor`.

If your check is meant to be invoked manually (no hook wiring), skip this step.

## What `Base` gives you for free

These are the helpers I found myself wanting in every concrete check. They live on `Base` so subclasses do not reach for stdlib boilerplate.

| Helper | What it does |
|--------|--------------|
| `repo_root` | Resolves to the git repo root, or `nil` if we are not in a repo. Always check for `nil` and return `Result.new(exit_code: 0)` - "not in a repo" is not a failure. |
| `changed_ruby_files` | Tracked diffs + staged + untracked, filtered to `.rb`, `.rake`, `.gemspec`, `Gemfile`, `Rakefile`. Use this for Ruby-touching checks. |
| `changed_migrations` | Same as above but scoped to `db/migrate/`. Use for migration-safety checks. |
| `changed_test_files` | Same but scoped to `test/` and `spec/`. |
| `rubocop_server_available?` | True when `rubocop-server` is running (or forced via `RAILSDX_RUBOCOP_SERVER=1`). Use when shelling out to `rubocop` so cold-start cost does not compound. |
| `format_failure(check_name:, offenses:, fix_hint:)` | Renders the standard `[railsdx <name>] reported N offenses:` header followed by formatted offenses. You rarely call this directly - `Base#emit` does it. |
| `write_state(result)` | Writes `.railsdx/last-check.json` with the check name, exit code, timestamp, and the `state` hash from your `Result`. Best-effort; never raises. |

## The contract in one paragraph

A check is a `Railsdx::Checks::Base` subclass with a `#run(argv)` method that returns a `Checks::Result`. The result's `exit_code` becomes the process exit code (`0` = clean, `2` = blocking offenses). The `offenses` array becomes the stderr report. The `state` hash becomes JSON in `.railsdx/last-check.json`. The check is registered in the autoload list, exposed as a Thor subcommand on `Checks::CLI`, and (if hook-wired) listed in `Doctor::EXPECTED_HOOKS`. Nothing else has to know about the new check.

## Why I didn't make this fully convention-driven

I considered loading checks from a directory and registering subcommands by reflection. Two reasons I did not:

1. The 1:1 explicit mapping makes the available checks visible in three files (`checks.rb`, `cli.rb`, `doctor.rb`) that I can read end-to-end in 30 seconds. That readability matters more than the one-line savings on each new check.
2. Reflection would couple the public CLI surface to internal class names. I want to be able to rename `Railsdx::Checks::TestsChanged` to `Railsdx::Checks::MissingTests` without breaking `railsdx-check tests-changed`.

When the gem grows beyond ~10 checks I may revisit. Until then, explicit wins.

## Resources

- [Source: `lib/railsdx/checks/base.rb`](../lib/railsdx/checks/base.rb) - the contract
- [Source: `lib/railsdx/checks/rubocop_changed.rb`](../lib/railsdx/checks/rubocop_changed.rb) - the canonical reference implementation
- [Source: `lib/railsdx/checks/doctor.rb`](../lib/railsdx/checks/doctor.rb) - how to make a check observable
- [Thor README](https://github.com/rails/thor) - the dispatcher used by `Checks::CLI`
