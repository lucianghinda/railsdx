# frozen_string_literal: true

module Railsdx
  # Per-hook quality checks invoked from agent integrations (Claude Code Stop
  # hooks, Codex hooks, OpenCode plugins) via `bundle exec railsdx-check <name>`.
  #
  # Each concrete check subclasses Checks::Base and is dispatched through
  # Checks::CLI (Thor). See docs/plans/llm-quality-hooks-mvp-plan.md.
  module Checks
    autoload :Base,           "railsdx/checks/base"
    autoload :CLI,            "railsdx/checks/cli"
    autoload :Doctor,         "railsdx/checks/doctor"
    autoload :Result,         "railsdx/checks/result"
    autoload :RubocopChanged, "railsdx/checks/rubocop_changed"
    autoload :RubocopEdited,  "railsdx/checks/rubocop_edited"
    autoload :RubocopServer,  "railsdx/checks/rubocop_server"
  end
end
