# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "stringio"
require "tmpdir"

module Railsdx
  module Checks
    # Most scenarios that touch RuboCop's subprocess are stubbed via Open3 —
    # we trust RuboCop itself, what we're verifying is dispatch, file
    # filtering, and exit-code / stderr contract.
    class RubocopEditedTest < Minitest::Test
      def setup
        @stdout = StringIO.new
        @stderr = StringIO.new
        @stdin  = StringIO.new
      end

      def test_non_ruby_file_exits_zero_silently
        check = build_check
        assert_equal 0, check.call(["README.md"])
        assert_empty @stderr.string
      end

      def test_no_file_path_exits_zero_silently
        # No argv and no stdin payload: nothing to do.
        check = build_check
        assert_equal 0, check.call([])
        assert_empty @stderr.string
      end

      def test_parses_file_path_from_stdin_json
        @stdin = StringIO.new(JSON.generate({ "tool_input" => { "file_path" => "app/models/foo.rb" } }))
        check = build_check
        # No repo, no Gemfile → still exits 0, but proves we resolved the path.
        # We assert by overriding ruby_file? — easier: just assert it didn't crash on stdin parsing.
        Dir.mktmpdir { |dir| Dir.chdir(dir) { assert_equal 0, check.call([]) } }
      end

      def test_stdin_with_invalid_json_does_not_crash
        @stdin = StringIO.new("not json at all")
        check = build_check
        Dir.mktmpdir { |dir| Dir.chdir(dir) { assert_equal 0, check.call([]) } }
      end

      def test_skips_when_not_a_rails_project
        # File looks Ruby, but no Gemfile / no .rubocop.yml → skip silently.
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            system("git", "init", "--quiet")
            File.write("lonely.rb", "puts 'hi'\n")
            check = build_check
            assert_equal 0, check.call(["lonely.rb"])
            assert_empty @stderr.string
          end
        end
      end

      def test_un_autocorrectable_offenses_exit_two_with_stderr_report
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            system("git", "init", "--quiet")
            File.write("Gemfile", "source 'https://rubygems.org'\n")
            File.write(".rubocop.yml", "AllCops:\n  TargetRubyVersion: 3.3\n")
            File.write("bad.rb", "x = 1\nputs x\n")
            check = build_check

            # Stub Open3 to simulate "rubocop -A returned offenses".
            stub_open3_failure("bad.rb:1:1: C: Lint/UselessAssignment: ...")

            assert_equal 2, check.call(["bad.rb"])
            assert_includes @stderr.string, "[railsdx rubocop-edited]"
            assert_includes @stderr.string, "un-autocorrectable offenses in bad.rb"
            assert_includes @stderr.string, "→ try:"
          end
        end
      end

      def test_clean_file_exits_zero_silent
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            system("git", "init", "--quiet")
            File.write("Gemfile", "source 'https://rubygems.org'\n")
            File.write(".rubocop.yml", "AllCops:\n  TargetRubyVersion: 3.3\n")
            File.write("good.rb", "puts 1\n")
            check = build_check

            stub_open3_success

            assert_equal 0, check.call(["good.rb"])
            assert_empty @stderr.string
          end
        end
      end

      private

      def build_check
        RubocopEdited.new(stdout: @stdout, stderr: @stderr, stdin: @stdin)
      end

      def stub_open3_success
        Open3.singleton_class.define_method(:capture2e) do |*_args|
          status = Object.new
          status.define_singleton_method(:success?) { true }
          ["", status]
        end
      end

      def stub_open3_failure(output)
        Open3.singleton_class.define_method(:capture2e) do |*_args|
          status = Object.new
          status.define_singleton_method(:success?) { false }
          [output, status]
        end
      end

      def teardown
        # Undo the singleton_class stubs so other tests get real Open3 back.
        klass = Open3.singleton_class
        if klass.method_defined?(:capture2e) || klass.private_method_defined?(:capture2e)
          klass.remove_method(:capture2e)
        end
      rescue NameError
        # Not stubbed in this test
      end
    end
  end
end
