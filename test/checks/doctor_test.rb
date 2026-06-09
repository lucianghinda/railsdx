# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "toml-rb"

module Railsdx
  module Checks
    class DoctorTest < Minitest::Test
      def setup
        @stdout = StringIO.new
        @doctor = Doctor.new(stdout: @stdout, stderr: StringIO.new)
      end

      def test_no_install_exits_one_with_explanation
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            assert_equal 1, @doctor.call([])
            assert_includes @stdout.string, "No railsdx config detected"
          end
        end
      end

      def test_full_install_exits_zero_with_all_checks_passing
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_claude_full
            write_codex_full
            write_opencode_full
            assert_equal 0, @doctor.call([])
            assert_includes @stdout.string, "Claude Code"
            assert_includes @stdout.string, "Codex CLI"
            assert_includes @stdout.string, "OpenCode"
            assert_includes @stdout.string, "✓ Stop hook → bin/rubocop-changed"
            assert_includes @stdout.string, "✓ PostToolUse hook → bin/rubocop-edited"
            assert_includes @stdout.string, "✓ rubocop-changed.js"
            assert_includes @stdout.string, "✓ rubocop-edited.js"
          end
        end
      end

      def test_post_tool_use_missing_reports_not_wired
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_claude_stop_hook("bin/rubocop-changed") # Stop only, no PostToolUse
            assert_equal 1, @doctor.call([])
            assert_includes @stdout.string, "PostToolUse hook missing"
            assert_includes @stdout.string, "rubocop-edited not wired"
          end
        end
      end

      def test_only_claude_installed_omits_other_sections
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_claude_full
            assert_equal 0, @doctor.call([])
            assert_includes @stdout.string, "Claude Code"
            refute_includes @stdout.string, "Codex CLI"
            refute_includes @stdout.string, "OpenCode"
          end
        end
      end

      def test_wrong_command_reports_mismatch_and_exits_one
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_claude_stop_hook("bin/wrong-name")
            assert_equal 1, @doctor.call([])
            assert_includes @stdout.string, "points to bin/wrong-name"
            assert_includes @stdout.string, "expected bin/rubocop-changed"
            assert_includes @stdout.string, "✗"
          end
        end
      end

      def test_claude_present_but_hook_missing_reports_not_wired
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            File.write(".claude/settings.json".tap { |p| FileUtils.mkdir_p(File.dirname(p)) }, "{}")
            assert_equal 1, @doctor.call([])
            assert_includes @stdout.string, "Stop hook missing"
            assert_includes @stdout.string, "rubocop-changed not wired"
          end
        end
      end

      def test_opencode_dir_present_but_plugin_missing
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p(".opencode/plugins")
            assert_equal 1, @doctor.call([])
            assert_includes @stdout.string, "rubocop-changed.js missing"
          end
        end
      end

      # --- MCP verification -----------------------------------------------------

      def test_rubocop_mcp_present_in_all_three_agents
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_claude_mcp_with_rubocop
            write_codex_config_with_rubocop
            write_opencode_with_rubocop
            assert_equal 0, @doctor.call([])
            assert_includes @stdout.string, "✓ MCP server rubocop → .mcp.json"
            assert_includes @stdout.string, "✓ MCP server rubocop → .codex/config.toml"
            assert_includes @stdout.string, "✓ MCP server rubocop → opencode.json"
          end
        end
      end

      def test_rubocop_mcp_missing_reports_failure
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            File.write(".mcp.json", JSON.pretty_generate({ "mcpServers" => { "other" => { "command" => "x" } } }))
            assert_equal 1, @doctor.call([])
            assert_includes @stdout.string, "✗ MCP server rubocop missing from .mcp.json"
          end
        end
      end

      def test_rubydex_omitted_when_not_installed_anywhere
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_claude_mcp_with_rubocop
            @doctor.call([])
            refute_includes @stdout.string, "rubydex"
          end
        end
      end

      def test_rubydex_verified_when_present_in_any_agent
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_claude_mcp_with_rubocop_and_rubydex
            write_codex_config_with_rubocop # rubydex missing from codex
            assert_equal 1, @doctor.call([])
            assert_includes @stdout.string, "✓ MCP server rubydex → .mcp.json"
            assert_includes @stdout.string, "✗ MCP server rubydex missing from .codex/config.toml"
          end
        end
      end

      def test_codex_config_toml_with_rubocop_passes
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            write_codex_config_with_rubocop
            assert_equal 0, @doctor.call([])
            assert_includes @stdout.string, "✓ MCP server rubocop → .codex/config.toml"
          end
        end
      end

      private

      def write_claude_stop_hook(command)
        write_json_hooks(".claude/settings.json", "Stop", command)
      end

      def write_codex_stop_hook(command)
        write_json_hooks(".codex/hooks.json", "Stop", command)
      end

      def write_json_hooks(path, event, command)
        FileUtils.mkdir_p(File.dirname(path))
        hook_group = { "hooks" => [{ "type" => "command", "command" => command }] }
        payload    = { "hooks" => { event => [hook_group] } }
        File.write(path, JSON.pretty_generate(payload))
      end

      def write_claude_full
        FileUtils.mkdir_p(".claude")
        File.write(".claude/settings.json", JSON.pretty_generate(full_hooks_payload))
      end

      def write_codex_full
        FileUtils.mkdir_p(".codex")
        File.write(".codex/hooks.json", JSON.pretty_generate(full_hooks_payload))
      end

      def full_hooks_payload
        {
          "hooks" => {
            "Stop" => [{ "hooks" => [{ "type" => "command", "command" => "bin/rubocop-changed" }] }],
            "PostToolUse" => [
              { "matcher" => "Edit|Write|MultiEdit",
                "hooks" => [{ "type" => "command", "command" => "bin/rubocop-edited" }] }
            ]
          }
        }
      end

      def write_opencode_plugin
        FileUtils.mkdir_p(".opencode/plugins")
        File.write(".opencode/plugins/rubocop-changed.js", "// installed by railsdx\n")
      end

      def write_opencode_full
        FileUtils.mkdir_p(".opencode/plugins")
        File.write(".opencode/plugins/rubocop-changed.js", "// installed by railsdx\n")
        File.write(".opencode/plugins/rubocop-edited.js",  "// installed by railsdx\n")
      end

      def rubocop_mcp_command
        { "command" => "bundle", "args" => %w[exec rubocop --mcp] }
      end

      def write_claude_mcp_with_rubocop
        File.write(".mcp.json", JSON.pretty_generate(
                                  "mcpServers" => { "rubocop" => rubocop_mcp_command }
                                ))
      end

      def write_claude_mcp_with_rubocop_and_rubydex
        File.write(".mcp.json", JSON.pretty_generate(
                                  "mcpServers" => {
                                    "rubocop" => rubocop_mcp_command,
                                    "rubydex" => { "command" => "${HOME}/.cargo/bin/rubydex_mcp" }
                                  }
                                ))
      end

      def write_codex_config_with_rubocop
        FileUtils.mkdir_p(".codex")
        File.write(".codex/config.toml", TomlRB.dump(
                                           "mcp_servers" => { "rubocop" => rubocop_mcp_command }
                                         ))
      end

      def write_opencode_with_rubocop
        File.write("opencode.json", JSON.pretty_generate(
                                      "mcp" => {
                                        "rubocop" => {
                                          "type" => "local",
                                          "command" => %w[bundle exec rubocop --mcp],
                                          "enabled" => true
                                        }
                                      }
                                    ))
      end
    end
  end
end
