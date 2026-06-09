# frozen_string_literal: true

require "json"
require "toml-rb"
require "rails/generators/base"

module Railsdx
  module Generators
    # Writes local agent-config files for Claude Code, Codex CLI, and
    # OpenCode so all three share the same RuboCop workflow inside this
    # project. Every file lives under destination_root — no home-directory
    # writes and no global commands.
    #
    # Methods are grouped per agent. Each install_* method owns every file
    # that agent needs (instructions, MCP server registration, hooks).
    # Cross-cutting artifacts (AGENTS.md, the bin/ shims) live in
    # install_shared.
    class InstallGenerator < Rails::Generators::Base
      MARKER_START = "<!-- railsdx:start -->"
      MARKER_END = "<!-- railsdx:end -->"
      RUBYDEX_BIN = "${HOME}/.cargo/bin/rubydex_mcp"

      source_root File.expand_path("templates", __dir__)

      class_option :skip_claude, type: :boolean, default: false,
                                 desc: "Skip Claude Code files (.mcp.json, CLAUDE.md, .claude/settings.json)"
      class_option :skip_codex, type: :boolean, default: false,
                                desc: "Skip Codex CLI files (.codex/config.toml, .codex/hooks.json)"
      class_option :skip_opencode, type: :boolean, default: false,
                                   desc: "Skip OpenCode files (opencode.json, .opencode/instructions.md, plugins)"
      class_option :skip_stop_hook, type: :boolean, default: false,
                                    desc: "Skip the Stop-event RuboCop safety net (bin/rubocop-changed)"
      class_option :skip_rubocop_edited, type: :boolean, default: false,
                                         desc: "Skip the PostToolUse RuboCop autocorrect (bin/rubocop-edited)"
      class_option :with_rubydex, type: :boolean, default: false,
                                  desc: "Also wire the rubydex semantic-index MCP server (local; experimental)"

      # ===== Generator entry points (run in definition order) =====

      def install_shared
        upsert_marker_section("AGENTS.md", "AGENTS.md.tt")
        install_rubocop_changed_script unless options[:skip_stop_hook]
        install_rubocop_edited_script  unless options[:skip_rubocop_edited]
      end

      def install_claude
        return if options[:skip_claude]

        upsert_marker_section("CLAUDE.md", "CLAUDE.md.tt")
        merge_json(".mcp.json", "mcp/claude_code.json", root_key: "mcpServers", server_key: "rubocop")
        if options[:with_rubydex]
          merge_json(".mcp.json", "mcp/rubydex.claude.json", root_key: "mcpServers",
                                                             server_key: "rubydex")
        end
        install_agent_hook_settings(target: ".claude/settings.json")
      end

      def install_codex
        return if options[:skip_codex]

        merge_toml(".codex/config.toml", "mcp/codex.toml", root_key: "mcp_servers", server_key: "rubocop")
        if options[:with_rubydex]
          merge_toml(".codex/config.toml", "mcp/rubydex.codex.toml", root_key: "mcp_servers",
                                                                     server_key: "rubydex")
        end
        install_agent_hook_settings(target: ".codex/hooks.json")
      end

      def install_opencode
        return if options[:skip_opencode]

        upsert_marker_section(".opencode/instructions.md", "opencode_instructions.md.tt")
        merge_json("opencode.json", "mcp/opencode.json", root_key: "mcp", server_key: "rubocop")
        if options[:with_rubydex]
          merge_json("opencode.json", "mcp/rubydex.opencode.json", root_key: "mcp",
                                                                   server_key: "rubydex")
        end
        install_opencode_plugins
      end

      def show_next_steps
        say "\nDone. Next:", :green
        say "  1. Ensure rubocop >= 1.85 is in your Gemfile."
        say "  2. Restart your AI assistant so it picks up the new MCP config."
        say "  3. Confirm the `rubocop` MCP server appears in the tool list."
        show_hook_next_steps
        show_codex_trust_step
        show_rubydex_next_steps if options[:with_rubydex]
        say "  Run `bundle exec railsdx-check doctor` to verify the install."
      end

      private

      # ===== Codex trust =====
      #
      # Codex ignores both project-local config.toml AND .codex/ hook scripts
      # until the project is trusted. One `codex trust` unlocks both — surface
      # it loudly so the silent-no-op failure mode never bites.
      def show_codex_trust_step
        return if options[:skip_codex]
        return if no_codex_artifacts_to_load?

        say "  4. ", :green
        say "REQUIRED for Codex (MCP + hooks)", :yellow
        say "     Run once in this repo so Codex trusts the project config:"
        say "       codex trust .codex/", :cyan
        say "     Without this, Codex will silently skip the local config.toml"
        say "     and the railsdx hooks. Requires Codex CLI >= 0.78.0."
      end

      def no_codex_artifacts_to_load?
        all_hooks_skipped?
      end

      def all_hooks_skipped?
        options[:skip_stop_hook] && options[:skip_rubocop_edited]
      end

      def show_hook_next_steps
        return if all_hooks_skipped?

        say "  RuboCop hooks wired into your agents:"
        say "       - bin/rubocop-edited runs PostToolUse (Edit/Write/MultiEdit)" unless options[:skip_rubocop_edited]
        say "       - bin/rubocop-changed runs at Stop / session.idle"            unless options[:skip_stop_hook]
      end

      def show_rubydex_next_steps
        say "\n  Rubydex MCP wired (local) — [EXPERIMENTAL]", :yellow
        say "  Upstream rubydex ships its MCP server as experimental and is"
        say "  moving fast. Tool names / flags may change — watch the repo:"
        say "  https://github.com/shopify/rubydex"
        say ""
        say "  Prereq: install the binary once (skip if you already have it):", :yellow
        say "    cargo install --path rust/rubydex-mcp   # from a clone of shopify/rubydex"
        warn_if_rubydex_missing
      end

      def warn_if_rubydex_missing
        expanded = File.expand_path(RUBYDEX_BIN.sub("${HOME}", "~"))
        return if File.executable?(expanded)

        say "\n  ⚠  #{RUBYDEX_BIN} not found.", :red
        say "     Run the cargo install above before restarting your agent."
      end

      # ===== Shared artifacts =====

      def install_rubocop_changed_script
        copy_file "bin/rubocop-changed", "bin/rubocop-changed"
        chmod "bin/rubocop-changed", 0o755
      end

      def install_rubocop_edited_script
        copy_file "bin/rubocop-edited", "bin/rubocop-edited"
        chmod "bin/rubocop-edited", 0o755
      end

      def install_opencode_plugins
        copy_file "opencode_rubocop_changed.js", ".opencode/plugins/rubocop-changed.js" unless options[:skip_stop_hook]
        return if options[:skip_rubocop_edited]

        copy_file "opencode_rubocop_edited.js", ".opencode/plugins/rubocop-edited.js"
      end

      # ===== Hook settings (Claude + Codex share the same JSON schema) =====

      def install_agent_hook_settings(target:)
        template = filtered_hook_template
        return if template["hooks"].empty?

        absolute = File.expand_path(target, destination_root)
        return create_file(target, "#{JSON.pretty_generate(template)}\n") unless File.exist?(absolute)

        merged, added = merge_hook_events(JSON.parse(File.read(absolute)), template)
        if added.empty?
          say_status :skip, "#{target} (railsdx hooks already configured)", :yellow
        else
          File.write(absolute, "#{JSON.pretty_generate(merged)}\n")
          say_status :update, "#{target} (added: #{added.join(", ")})", :green
        end
      end

      def filtered_hook_template
        template = JSON.parse(File.read(File.expand_path("templates/agent_hook_settings.json", __dir__)))
        template["hooks"].delete("Stop")        if options[:skip_stop_hook]
        template["hooks"].delete("PostToolUse") if options[:skip_rubocop_edited]
        template
      end

      def merge_hook_events(existing, template)
        existing["hooks"] ||= {}
        added = []
        template["hooks"].each do |event, groups|
          existing["hooks"][event] ||= []
          groups.each do |group|
            command = group.dig("hooks", 0, "command")
            next if hook_command_present?(existing["hooks"][event], command)

            existing["hooks"][event] << group
            added << event
          end
        end
        [existing, added.uniq]
      end

      def hook_command_present?(groups, command)
        groups.any? { |group| Array(group["hooks"]).any? { |h| h["command"] == command } }
      end

      # ===== Marker-delimited markdown sections =====

      def upsert_marker_section(target_path, template_name)
        rendered = render_template(template_name)
        absolute = File.expand_path(target_path, destination_root)
        existing = File.exist?(absolute) ? File.read(absolute) : nil

        if existing.nil?
          create_file(target_path, rendered)
        elsif existing.include?(MARKER_START)
          replace_marker_section(target_path, absolute, existing, rendered)
        else
          append_to_file(target_path, "\n#{rendered}")
        end
      end

      def replace_marker_section(target_path, absolute, existing, rendered)
        pattern = /#{Regexp.escape(MARKER_START)}.*?#{Regexp.escape(MARKER_END)}/m
        new_block = rendered.match(pattern).to_s
        updated = existing.sub(pattern, new_block)
        File.write(absolute, updated)
        say_status :update, target_path, :green
      end

      def render_template(template_name)
        source = File.read(File.expand_path("templates/#{template_name}", __dir__))
        ERB.new(source, trim_mode: "-").result(binding)
      end

      # ===== JSON merge (Claude .mcp.json, OpenCode opencode.json, hooks) =====

      def merge_json(target_path, template_name, root_key:, server_key:)
        template = JSON.parse(File.read(File.expand_path("templates/#{template_name}", __dir__)))
        server_config = template.fetch(root_key).fetch(server_key)
        absolute = File.expand_path(target_path, destination_root)

        if File.exist?(absolute)
          existing = JSON.parse(File.read(absolute))
          existing[root_key] ||= {}
          if existing[root_key][server_key]
            say_status :skip, "#{target_path} (#{server_key} server already configured)", :yellow
            return
          end
          existing[root_key][server_key] = server_config
          File.write(absolute, "#{JSON.pretty_generate(existing)}\n")
          say_status :update, target_path, :green
        else
          create_file(target_path, "#{JSON.pretty_generate(template)}\n")
        end
      end

      # ===== TOML merge (Codex .codex/config.toml) =====
      #
      # Parses the existing config to detect whether the server is already
      # registered, then appends the template block verbatim so any comments
      # and key ordering the user added survive. A round-trip through
      # TomlRB.dump would re-serialize the whole file and lose those.
      def merge_toml(target_path, template_name, root_key:, server_key:)
        template_block = File.read(File.expand_path("templates/#{template_name}", __dir__))
        absolute = File.expand_path(target_path, destination_root)

        return create_file(target_path, template_block) unless File.exist?(absolute)

        existing_text = File.read(absolute)
        existing_parsed = parse_toml_safely(existing_text)

        if existing_parsed.dig(root_key, server_key)
          say_status :skip, "#{target_path} (#{server_key} server already configured)", :yellow
          return
        end

        File.write(absolute, append_toml_block(existing_text, template_block))
        say_status :update, target_path, :green
      end

      def parse_toml_safely(text)
        TomlRB.parse(text)
      rescue StandardError => e
        say_status :warn, ".codex/config.toml is not valid TOML (#{e.message}); appending anyway", :red
        {}
      end

      def append_toml_block(existing_text, block)
        prefix = existing_text
        prefix += "\n" unless prefix.empty? || prefix.end_with?("\n")
        prefix += "\n" unless prefix.empty? || prefix.end_with?("\n\n")
        "#{prefix}#{block}"
      end
    end
  end
end
