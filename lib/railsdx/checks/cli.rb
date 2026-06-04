# frozen_string_literal: true

require "thor"

module Railsdx
  module Checks
    # Thor-backed dispatcher for `bin/railsdx-check <subcommand>`.
    #
    # Each subcommand maps 1:1 to a concrete Checks::Base subclass. Add new
    # checks here when promoting them from the plan (R2 tests-changed, R3
    # brakeman-changed, etc.). The mapping is intentionally explicit rather
    # than reflective so the help output reads cleanly.
    class CLI < Thor
      def self.exit_on_failure? = true

      package_name "railsdx-check"

      desc "rubocop-changed [FILE...]", "Run RuboCop on Ruby files changed in the working tree"
      def rubocop_changed(*files)
        exit Checks::RubocopChanged.new.call(files)
      end

      desc "rubocop-edited [FILE]", "Autocorrect a single edited file (PostToolUse hook target)"
      def rubocop_edited(file = nil)
        exit Checks::RubocopEdited.new.call(Array(file))
      end

      desc "doctor", "Verify the railsdx install: inspect agent configs and report wiring"
      def doctor
        exit Checks::Doctor.new.call([])
      end
    end
  end
end
