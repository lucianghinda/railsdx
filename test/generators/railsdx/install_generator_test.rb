# frozen_string_literal: true

require "test_helper"
require "json"
require "toml-rb"

module Railsdx
  module Generators
    class InstallGeneratorTest < Rails::Generators::TestCase
      tests Railsdx::Generators::InstallGenerator
      destination File.expand_path("../../tmp/generator_dest", __dir__)
      setup :prepare_destination

      # --- fresh install ---------------------------------------------------------

      def test_creates_all_files_on_fresh_install
        run_generator

        assert_file "AGENTS.md", /<!-- railsdx:start -->/
        assert_file "AGENTS.md", /<!-- railsdx:end -->/
        assert_file "AGENTS.md", /RuboCop via MCP/

        assert_file "CLAUDE.md", /<!-- railsdx:start -->/
        assert_file ".mcp.json" do |content|
          json = JSON.parse(content)
          assert_equal "bundle", json.dig("mcpServers", "rubocop", "command")
          assert_equal %w[exec rubocop --mcp], json.dig("mcpServers", "rubocop", "args")
        end

        assert_file ".codex/config.toml" do |content|
          toml = TomlRB.parse(content)
          assert_equal "bundle", toml.dig("mcp_servers", "rubocop", "command")
          assert_equal %w[exec rubocop --mcp], toml.dig("mcp_servers", "rubocop", "args")
        end

        assert_file ".opencode/instructions.md", /<!-- railsdx:start -->/
        assert_file "opencode.json" do |content|
          json = JSON.parse(content)
          assert_equal "local", json.dig("mcp", "rubocop", "type")
          assert_equal true, json.dig("mcp", "rubocop", "enabled")
        end
      end

      def test_writes_codex_config_toml_locally
        run_generator
        assert_file ".codex/config.toml", /\[mcp_servers\.rubocop\]/
      end

      def test_prints_next_steps
        output = run_generator
        assert_match(/Done\. Next:/, output)
        assert_match(/rubocop >= 1\.85/, output)
        assert_match(/railsdx-check doctor/, output)
      end

      def test_prints_codex_trust_step_when_codex_files_are_installed
        output = run_generator
        assert_match(/REQUIRED for Codex \(MCP \+ hooks\)/, output)
        assert_match(%r{codex trust \.codex/}, output)
        assert_match(/Codex CLI >= 0\.78\.0/, output)
      end

      def test_codex_trust_step_omitted_when_codex_skipped
        output = run_generator ["--skip-codex"]
        refute_match(/codex trust/, output)
      end

      def test_codex_trust_step_omitted_when_all_hooks_skipped
        output = run_generator ["--skip-stop-hook", "--skip-rubocop-edited"]
        refute_match(/codex trust/, output)
      end

      # --- skip flags ------------------------------------------------------------

      def test_skip_claude_omits_claude_files
        run_generator ["--skip-claude"]
        assert_no_file "CLAUDE.md"
        assert_no_file ".mcp.json"
        assert_file "AGENTS.md"
        assert_file "opencode.json"
      end

      def test_skip_opencode_omits_opencode_files
        run_generator ["--skip-opencode"]
        assert_no_file ".opencode/instructions.md"
        assert_no_file "opencode.json"
        assert_file "AGENTS.md"
        assert_file ".mcp.json"
      end

      def test_skip_codex_omits_codex_files
        run_generator ["--skip-codex"]
        assert_no_file ".codex/config.toml"
        assert_no_file ".codex/hooks.json"
        assert_file ".mcp.json"
      end

      # --- rubydex (opt-in) ------------------------------------------------------

      def test_rubydex_off_by_default
        output = run_generator
        assert_file "AGENTS.md" do |content|
          refute_match(/Rubydex/, content)
        end
        refute_match(/Rubydex MCP/, output)
        assert_file ".mcp.json" do |content|
          json = JSON.parse(content)
          assert_nil json.dig("mcpServers", "rubydex")
        end
        assert_file ".codex/config.toml" do |content|
          toml = TomlRB.parse(content)
          assert_nil toml.dig("mcp_servers", "rubydex")
        end
        assert_file "opencode.json" do |content|
          json = JSON.parse(content)
          assert_nil json.dig("mcp", "rubydex")
        end
      end

      def test_with_rubydex_writes_local_mcp_entries_in_all_three_agents
        output = run_generator ["--with-rubydex"]

        assert_file "AGENTS.md", /Rubydex \(semantic code intelligence\) via MCP/
        assert_file "AGENTS.md", /\*\*experimental\*\*/
        assert_file "AGENTS.md", /search_declarations/

        assert_file ".mcp.json" do |content|
          json = JSON.parse(content)
          assert_equal "${HOME}/.cargo/bin/rubydex_mcp", json.dig("mcpServers", "rubydex", "command")
        end
        assert_file ".codex/config.toml" do |content|
          toml = TomlRB.parse(content)
          assert_equal "${HOME}/.cargo/bin/rubydex_mcp", toml.dig("mcp_servers", "rubydex", "command")
        end
        assert_file "opencode.json" do |content|
          json = JSON.parse(content)
          assert_equal "local", json.dig("mcp", "rubydex", "type")
          assert_equal ["${HOME}/.cargo/bin/rubydex_mcp"], json.dig("mcp", "rubydex", "command")
        end

        assert_match(%r{cargo install --path rust/rubydex-mcp}, output)
        assert_match(/\[EXPERIMENTAL\]/, output)
      end

      def test_with_rubydex_respects_skip_claude
        run_generator ["--with-rubydex", "--skip-claude"]
        assert_no_file ".mcp.json"
        assert_file ".codex/config.toml" do |content|
          toml = TomlRB.parse(content)
          refute_nil toml.dig("mcp_servers", "rubydex")
        end
        assert_file "opencode.json" do |content|
          json = JSON.parse(content)
          refute_nil json.dig("mcp", "rubydex")
        end
      end

      def test_with_rubydex_respects_skip_codex
        run_generator ["--with-rubydex", "--skip-codex"]
        assert_no_file ".codex/config.toml"
        assert_file ".mcp.json" do |content|
          json = JSON.parse(content)
          refute_nil json.dig("mcpServers", "rubydex")
        end
        assert_file "opencode.json" do |content|
          json = JSON.parse(content)
          refute_nil json.dig("mcp", "rubydex")
        end
      end

      def test_with_rubydex_respects_skip_opencode
        run_generator ["--with-rubydex", "--skip-opencode"]
        assert_no_file "opencode.json"
        assert_file ".mcp.json" do |content|
          json = JSON.parse(content)
          refute_nil json.dig("mcpServers", "rubydex")
        end
        assert_file ".codex/config.toml" do |content|
          toml = TomlRB.parse(content)
          refute_nil toml.dig("mcp_servers", "rubydex")
        end
      end

      # --- idempotency: marker blocks --------------------------------------------

      def test_rerun_replaces_marker_block_without_duplicating
        run_generator
        first = File.read(File.join(destination_root, "AGENTS.md"))

        run_generator
        second = File.read(File.join(destination_root, "AGENTS.md"))

        assert_equal first, second, "re-running should be a no-op when content is unchanged"
        assert_equal 1, second.scan("<!-- railsdx:start -->").size
        assert_equal 1, second.scan("<!-- railsdx:end -->").size
      end

      def test_appends_when_existing_file_has_no_marker
        path = File.join(destination_root, "AGENTS.md")
        File.write(path, "# My existing notes\n\nKeep me.\n")

        run_generator
        content = File.read(path)

        assert_match(/# My existing notes/, content, "must preserve prior content")
        assert_match(/Keep me\./, content)
        assert_match(/<!-- railsdx:start -->/, content)
        assert_match(/<!-- railsdx:end -->/, content)
      end

      def test_replaces_marker_block_in_existing_file_with_surrounding_content
        path = File.join(destination_root, "AGENTS.md")
        File.write(path, <<~MD)
          # Project notes

          <!-- railsdx:start -->
          stale content from a previous version
          <!-- railsdx:end -->

          ## Other section the user wrote
        MD

        run_generator
        content = File.read(path)

        refute_match(/stale content from a previous version/, content)
        assert_match(/# Project notes/, content)
        assert_match(/## Other section the user wrote/, content)
        assert_match(/RuboCop via MCP/, content)
      end

      # --- idempotency: JSON merge -----------------------------------------------

      def test_json_merge_preserves_other_mcp_servers
        existing = { "mcpServers" => { "other" => { "command" => "node", "args" => ["server.js"] } } }
        File.write(File.join(destination_root, ".mcp.json"), JSON.pretty_generate(existing))

        run_generator
        json = JSON.parse(File.read(File.join(destination_root, ".mcp.json")))

        assert_equal "node", json.dig("mcpServers", "other", "command")
        assert_equal "bundle", json.dig("mcpServers", "rubocop", "command")
      end

      def test_json_merge_skips_when_rubocop_server_already_present
        existing = { "mcpServers" => { "rubocop" => { "command" => "custom", "args" => ["--flag"] } } }
        File.write(File.join(destination_root, ".mcp.json"), JSON.pretty_generate(existing))

        output = run_generator
        assert_match(/skip.*\.mcp\.json.*rubocop server already configured/i, output)
        json = JSON.parse(File.read(File.join(destination_root, ".mcp.json")))
        assert_equal "custom", json.dig("mcpServers", "rubocop", "command"),
                     "must not clobber user's existing rubocop server config"
      end

      # --- post-turn RuboCop safety net -----------------------------------------

      def test_installs_rubocop_changed_script_executable
        run_generator
        path = File.join(destination_root, "bin/rubocop-changed")

        # The shim execs the gem's bundled CLI so the lint logic stays in one
        # place (lib/railsdx/checks/rubocop_changed.rb).
        assert_file "bin/rubocop-changed", /exec\("bundle", "exec", "railsdx-check", "rubocop-changed"/
        assert_file "bin/rubocop-changed", %r{\A#!/usr/bin/env ruby}
        assert File.executable?(path), "bin/rubocop-changed must be chmod +x for hooks to invoke it"
      end

      def test_installs_claude_stop_hook
        run_generator
        json = JSON.parse(File.read(File.join(destination_root, ".claude/settings.json")))

        stop = json.dig("hooks", "Stop")
        assert_kind_of Array, stop
        commands = stop.flat_map { |group| Array(group["hooks"]).map { |h| h["command"] } }
        assert_includes commands, "bin/rubocop-changed"
      end

      def test_agents_md_documents_stop_hook_script
        run_generator
        assert_file "AGENTS.md", %r{bin/rubocop-changed}
      end

      def test_skip_stop_hook_removes_only_stop_event_artifacts
        run_generator ["--skip-stop-hook"]
        # The PostToolUse rubocop-edited side stays wired.
        assert_no_file "bin/rubocop-changed"
        assert_no_file ".opencode/plugins/rubocop-changed.js"
        assert_file "bin/rubocop-edited"
        # Settings files still exist for the surviving event.
        json = JSON.parse(File.read(File.join(destination_root, ".claude/settings.json")))
        assert_nil json.dig("hooks", "Stop"), "Stop event must be omitted"
        assert_kind_of Array, json.dig("hooks", "PostToolUse")
      end

      def test_skip_both_hook_flags_omits_settings_files_entirely
        run_generator ["--skip-stop-hook", "--skip-rubocop-edited"]
        assert_no_file "bin/rubocop-changed"
        assert_no_file "bin/rubocop-edited"
        assert_no_file ".claude/settings.json"
        assert_no_file ".codex/hooks.json"
        assert_no_file ".opencode/plugins/rubocop-changed.js"
        assert_no_file ".opencode/plugins/rubocop-edited.js"
      end

      def test_skip_claude_keeps_script_but_omits_claude_settings
        run_generator ["--skip-claude"]
        assert_file "bin/rubocop-changed"
        assert_no_file ".claude/settings.json"
      end

      def test_installs_codex_stop_hook
        run_generator
        json = JSON.parse(File.read(File.join(destination_root, ".codex/hooks.json")))

        commands = json.dig("hooks", "Stop").flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
        assert_includes commands, "bin/rubocop-changed"
      end

      def test_skip_codex_omits_codex_hooks_file
        run_generator ["--skip-codex"]
        assert_no_file ".codex/hooks.json"
        assert_file ".claude/settings.json", %r{bin/rubocop-changed}
      end

      def test_codex_hooks_merge_preserves_existing_hooks
        FileUtils.mkdir_p(File.join(destination_root, ".codex"))
        existing = {
          "hooks" => {
            "Stop" => [{ "hooks" => [{ "type" => "command", "command" => "echo other" }] }]
          }
        }
        File.write(File.join(destination_root, ".codex/hooks.json"), JSON.pretty_generate(existing))

        run_generator
        json = JSON.parse(File.read(File.join(destination_root, ".codex/hooks.json")))
        commands = json.dig("hooks", "Stop").flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }

        assert_includes commands, "echo other"
        assert_includes commands, "bin/rubocop-changed"
      end

      def test_installs_opencode_plugin
        run_generator
        assert_file ".opencode/plugins/rubocop-changed.js", /session\.idle/
        assert_file ".opencode/plugins/rubocop-changed.js", %r{bin/rubocop-changed}
      end

      def test_skip_opencode_omits_opencode_plugin
        run_generator ["--skip-opencode"]
        assert_no_file ".opencode/plugins/rubocop-changed.js"
        assert_file ".codex/hooks.json"
      end

      def test_agents_md_documents_all_three_integrations
        run_generator
        assert_file "AGENTS.md", %r{\.claude/settings\.json}
        assert_file "AGENTS.md", %r{\.codex/hooks\.json}
        assert_file "AGENTS.md", %r{\.opencode/plugins/rubocop-changed\.js}
      end

      def test_claude_settings_merge_preserves_existing_hooks
        FileUtils.mkdir_p(File.join(destination_root, ".claude"))
        existing = {
          "hooks" => {
            "Stop" => [
              { "hooks" => [{ "type" => "command", "command" => "echo other" }] }
            ],
            "PreToolUse" => [
              { "matcher" => "Bash",
                "hooks" => [{ "type" => "command", "command" => "echo pre" }] }
            ]
          },
          "permissions" => { "allow" => ["Bash(ls:*)"] }
        }
        File.write(File.join(destination_root, ".claude/settings.json"), JSON.pretty_generate(existing))

        run_generator
        json = JSON.parse(File.read(File.join(destination_root, ".claude/settings.json")))

        commands = json.dig("hooks", "Stop").flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
        assert_includes commands, "echo other", "must keep the user's existing Stop hook"
        assert_includes commands, "bin/rubocop-changed", "must append the rubocop-changed hook"
        assert_equal "echo pre", json.dig("hooks", "PreToolUse", 0, "hooks", 0, "command"),
                     "must not touch unrelated hook events"
        assert_equal ["Bash(ls:*)"], json.dig("permissions", "allow"),
                     "must not touch unrelated top-level keys"
      end

      def test_claude_settings_merge_is_idempotent
        run_generator
        first = File.read(File.join(destination_root, ".claude/settings.json"))

        output = run_generator
        second = File.read(File.join(destination_root, ".claude/settings.json"))

        assert_equal first, second, "re-running must not duplicate hook entries"
        assert_match(%r{skip.*\.claude/settings\.json.*railsdx hooks already configured}i, output)
      end

      # --- R1: PostToolUse rubocop-edited ----------------------------------------

      def test_installs_rubocop_edited_script_executable
        run_generator
        path = File.join(destination_root, "bin/rubocop-edited")
        assert_file "bin/rubocop-edited", /exec\("bundle", "exec", "railsdx-check", "rubocop-edited"/
        assert File.executable?(path)
      end

      def test_installs_claude_post_tool_use_hook
        run_generator
        json = JSON.parse(File.read(File.join(destination_root, ".claude/settings.json")))
        post = json.dig("hooks", "PostToolUse")
        assert_kind_of Array, post
        assert_equal "Edit|Write|MultiEdit", post.first["matcher"]
        commands = post.flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
        assert_includes commands, "bin/rubocop-edited"
      end

      def test_installs_codex_post_tool_use_hook
        run_generator
        json = JSON.parse(File.read(File.join(destination_root, ".codex/hooks.json")))
        commands = json.dig("hooks", "PostToolUse").flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
        assert_includes commands, "bin/rubocop-edited"
      end

      def test_installs_opencode_rubocop_edited_plugin
        run_generator
        assert_file ".opencode/plugins/rubocop-edited.js", /file\.edited/
        assert_file ".opencode/plugins/rubocop-edited.js", %r{bin/rubocop-edited}
      end

      def test_skip_rubocop_edited_removes_only_post_tool_use_artifacts
        run_generator ["--skip-rubocop-edited"]
        assert_no_file "bin/rubocop-edited"
        assert_no_file ".opencode/plugins/rubocop-edited.js"
        assert_file "bin/rubocop-changed"
        json = JSON.parse(File.read(File.join(destination_root, ".claude/settings.json")))
        assert_nil json.dig("hooks", "PostToolUse"), "PostToolUse must be omitted"
        assert_kind_of Array, json.dig("hooks", "Stop")
      end

      def test_agents_md_documents_rubocop_edited
        run_generator
        assert_file "AGENTS.md", %r{bin/rubocop-edited}
        assert_file "AGENTS.md", /PostToolUse/
      end

      def test_opencode_json_merge_preserves_other_servers
        existing = {
          "mcp" => {
            "other" => { "type" => "local", "command" => %w[node x], "enabled" => true }
          }
        }
        File.write(File.join(destination_root, "opencode.json"), JSON.pretty_generate(existing))

        run_generator
        json = JSON.parse(File.read(File.join(destination_root, "opencode.json")))

        assert_equal "node", json.dig("mcp", "other", "command", 0)
        assert_equal "local", json.dig("mcp", "rubocop", "type")
      end

      # --- TOML merge for .codex/config.toml -------------------------------------

      def test_codex_config_toml_merge_preserves_unrelated_keys_and_comments
        FileUtils.mkdir_p(File.join(destination_root, ".codex"))
        existing = <<~TOML
          # User preferences for this project
          model = "gpt-5-codex"

          [mcp_servers.other]
          command = "node"
          args = ["server.js"]
        TOML
        File.write(File.join(destination_root, ".codex/config.toml"), existing)

        run_generator

        content = File.read(File.join(destination_root, ".codex/config.toml"))
        assert_match(/# User preferences for this project/, content,
                     "must preserve user's comments")
        assert_match(/model = "gpt-5-codex"/, content,
                     "must preserve unrelated top-level keys")
        toml = TomlRB.parse(content)
        assert_equal "node", toml.dig("mcp_servers", "other", "command"),
                     "must preserve the user's existing mcp_servers"
        assert_equal "bundle", toml.dig("mcp_servers", "rubocop", "command"),
                     "must append our rubocop server"
      end

      def test_codex_config_toml_merge_skips_when_rubocop_already_configured
        FileUtils.mkdir_p(File.join(destination_root, ".codex"))
        existing = <<~TOML
          [mcp_servers.rubocop]
          command = "custom-rubocop"
          args = ["--flag"]
        TOML
        File.write(File.join(destination_root, ".codex/config.toml"), existing)

        output = run_generator
        assert_match(%r{skip.*\.codex/config\.toml.*rubocop server already configured}i, output)
        toml = TomlRB.parse(File.read(File.join(destination_root, ".codex/config.toml")))
        assert_equal "custom-rubocop", toml.dig("mcp_servers", "rubocop", "command"),
                     "must not clobber user's existing rubocop config"
      end

      def test_codex_config_toml_merge_is_idempotent
        run_generator
        first = File.read(File.join(destination_root, ".codex/config.toml"))

        run_generator
        second = File.read(File.join(destination_root, ".codex/config.toml"))

        assert_equal first, second, "re-running must not duplicate the rubocop block"
        assert_equal 1, second.scan(/\[mcp_servers\.rubocop\]/).size
      end
    end
  end
end
