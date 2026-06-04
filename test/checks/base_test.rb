# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"

module Railsdx
  module Checks
    class BaseTest < Minitest::Test
      # Stand-in concrete check used to exercise the Base contract without
      # depending on RuboCop or any other real check.
      class FakeCheck < Base
        attr_accessor :next_result

        def check_name = "fake-check"

        def run(_argv) = next_result || Result.new(exit_code: 0)
      end

      def setup
        @stdout = StringIO.new
        @stderr = StringIO.new
        @check  = FakeCheck.new(stdout: @stdout, stderr: @stderr)
      end

      def test_happy_path_returns_zero_and_writes_nothing_to_stderr
        Dir.mktmpdir do |dir|
          in_repo(dir) do
            assert_equal 0, @check.call([])
            assert_empty @stderr.string
          end
        end
      end

      def test_failure_with_offenses_emits_formatted_header_body_and_fix_hint
        @check.next_result = Result.new(
          exit_code: 2,
          offenses: [{ file: "app/models/foo.rb", line: 12, column: 3, message: "bad", cop: "Style/Foo" }],
          fix_hint: "bundle exec rubocop -A"
        )

        Dir.mktmpdir do |dir|
          in_repo(dir) do
            assert_equal 2, @check.call([])
          end
        end

        out = @stderr.string
        assert_includes out, "[railsdx fake-check] reported 1 offense:"
        assert_includes out, "app/models/foo.rb:12:3: Style/Foo: bad"
        assert_includes out, "→ try: bundle exec rubocop -A"
        # Order: header → body → fix hint
        assert out.index("[railsdx") < out.index("Style/Foo"),
               "header must come before offense body"
        assert out.index("Style/Foo") < out.index("→ try:"),
               "fix hint must come last"
      end

      def test_changed_ruby_files_in_fresh_repo_returns_empty_array
        Dir.mktmpdir do |dir|
          in_repo(dir) do
            assert_equal [], @check.changed_ruby_files
          end
        end
      end

      def test_check_name_derived_from_class_name
        # Verifies the demodulize+underscore+dasherize fallback used by every
        # check that doesn't override check_name.
        anonymous = Class.new(Base) { def run(_) = Result.new(exit_code: 0) }
        Object.const_set(:RubocopChangedSampleFake, anonymous)
        begin
          assert_equal "rubocop-changed-sample-fake", anonymous.new.check_name
        ensure
          Object.send(:remove_const, :RubocopChangedSampleFake)
        end
      end

      def test_write_state_emits_json_with_check_exit_code_and_timestamp
        @check.next_result = Result.new(exit_code: 0, state: { extra: "value" })

        Dir.mktmpdir do |dir|
          in_repo(dir) do
            @check.call([])
            state_path = File.join(dir, ".railsdx", "last-check.json")
            assert File.exist?(state_path), "must write .railsdx/last-check.json"
            payload = JSON.parse(File.read(state_path))
            assert_equal "fake-check", payload["check"]
            assert_equal 0, payload["exit_code"]
            assert_match(/\A\d{4}-\d{2}-\d{2}T/, payload["timestamp"])
            assert_equal "value", payload["extra"]
          end
        end
      end

      def test_interface_contract_exposes_documented_helpers
        # If a Base refactor silently renames or removes one of these, every
        # downstream check breaks at runtime. Pin them.
        %i[changed_ruby_files changed_migrations changed_test_files
           format_failure write_state repo_root rubocop_server_available?].each do |method|
          assert @check.respond_to?(method),
                 "Checks::Base must expose ##{method} for subclasses"
        end
      end

      def test_rubocop_server_env_var_forces_true
        with_env("RAILSDX_RUBOCOP_SERVER" => "1") do
          assert @check.rubocop_server_available?,
                 "RAILSDX_RUBOCOP_SERVER=1 must force --server even without a status probe"
        end
      end

      def test_rubocop_server_env_var_forces_false
        with_env("RAILSDX_RUBOCOP_SERVER" => "0") do
          refute @check.rubocop_server_available?,
                 "RAILSDX_RUBOCOP_SERVER=0 must never enable --server"
        end
      end

      def test_run_raises_not_implemented_when_subclass_forgets_to_override
        bad = Class.new(Base).new
        assert_raises(NotImplementedError) { bad.run([]) }
      end

      private

      def in_repo(dir)
        Dir.chdir(dir) do
          system("git", "init", "--quiet")
          yield
        end
      end

      def with_env(overrides)
        originals = overrides.transform_values { |_| nil }
        overrides.each_key { |k| originals[k] = ENV.fetch(k, nil) }
        overrides.each { |k, v| ENV[k] = v }
        yield
      ensure
        originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end
    end
  end
end
