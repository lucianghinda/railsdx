# frozen_string_literal: true

require_relative "../test_helper"

module Railsdx
  module Checks
    class CLITest < Minitest::Test
      def test_help_lists_registered_subcommands
        out, = capture_io { CLI.start(["help"]) }
        assert_includes out, "rubocop-changed"
        assert_includes out, "doctor"
      end

      def test_dispatches_rubocop_changed_to_the_check_class
        # We don't want this test to actually shell out to RuboCop. Stub the
        # check so we can assert dispatch happened.
        invocations = []
        fake = Class.new(Base) do
          define_method(:check_name) { "rubocop-changed" }
          define_method(:run) do |argv|
            invocations << argv
            Result.new(exit_code: 0)
          end
        end

        Checks.send(:remove_const, :RubocopChanged) if Checks.const_defined?(:RubocopChanged, false)
        Checks.const_set(:RubocopChanged, fake)

        begin
          assert_raises(SystemExit) do
            CLI.start(["rubocop-changed", "some_file.rb"])
          end
          refute_empty invocations, "CLI must route the subcommand to RubocopChanged#run"
        ensure
          Checks.send(:remove_const, :RubocopChanged)
          # Re-trigger the autoload by re-requiring.
          load File.expand_path("../../lib/railsdx/checks/rubocop_changed.rb", __dir__)
        end
      end
    end
  end
end
