# frozen_string_literal: true

require "json"
require "rails/generators/base"

module Railsdx
  module Generators
    # Drops MCP server configuration and agent instructions so Claude Code,
    # Codex, and OpenCode use RuboCop's built-in MCP server.
    class InstallGenerator < Rails::Generators::Base
      MARKER_START = "<!-- railsdx:start -->"
      MARKER_END = "<!-- railsdx:end -->"

      source_root File.expand_path("templates", __dir__)

      class_option :skip_claude, type: :boolean, default: false,
                                 desc: "Skip Claude Code config (.mcp.json, CLAUDE.md)"
      class_option :skip_codex, type: :boolean, default: false,
                                desc: "Skip Codex MCP config snippet"
      class_option :skip_opencode, type: :boolean, default: false,
                                   desc: "Skip OpenCode config (opencode.json, .opencode/instructions.md)"
      class_option :skip_stop_hook, type: :boolean, default: false,
                                    desc: "Skip the Stop-event RuboCop safety net (bin/rubocop-changed)"
      class_option :skip_rubocop_edited, type: :boolean, default: false,
                                         desc: "Skip the PostToolUse RuboCop autocorrect (bin/rubocop-edited)"
      class_option :with_rubydex, type: :boolean, default: false,
                                  desc: "Also wire the rubydex semantic-index MCP server (user scope; prints snippets)"

      RUBYDEX_BIN = "${HOME}/.cargo/bin/rubydex_mcp"

      def install_agents_md
        upsert_marker_section("AGENTS.md", "AGENTS.md.tt")
      end

      def install_claude_code
        return if options[:skip_claude]

        upsert_marker_section("CLAUDE.md", "CLAUDE.md.tt")
        merge_json(".mcp.json", "mcp/claude_code.json", root_key: "mcpServers", server_key: "rubocop")
      end

      def install_agent_hooks
        return if all_hooks_skipped?

        install_rubocop_changed_script unless options[:skip_stop_hook]
        install_rubocop_edited_script  unless options[:skip_rubocop_edited]
        install_agent_hook_settings(target: ".claude/settings.json") unless options[:skip_claude]
        install_agent_hook_settings(target: ".codex/hooks.json")     unless options[:skip_codex]
        install_opencode_plugins                                     unless options[:skip_opencode]
      end

      def install_opencode
        return if options[:skip_opencode]

        upsert_marker_section(".opencode/instructions.md", "opencode_instructions.md.tt")
        merge_json("opencode.json", "mcp/opencode.json", root_key: "mcp", server_key: "rubocop")
      end

      def show_codex_snippet
        return if options[:skip_codex]

        snippet = File.read(File.expand_path("templates/mcp/codex.toml", __dir__))
        say "\nCodex uses ~/.codex/config.toml (TOML). Add this snippet manually:\n", :yellow
        say snippet, :cyan
      end

      def show_rubydex_snippets
        return unless options[:with_rubydex]

        say "\nRubydex MCP — user-scope setup  [EXPERIMENTAL]", :yellow
        say "  Upstream rubydex ships its MCP server as experimental and is"
        say "  moving fast. Tool names / flags may change — watch the repo:"
        say "  https://github.com/shopify/rubydex"
        say ""
        say "  Rubydex indexes whichever directory it is launched in, so one"
        say "  user-level registration covers every Ruby project. Nothing in"
        say "  this repo needs to change."
        say ""
        say "  Prereq: install the binary once (skip if you already have it):", :yellow
        say "    cargo install --path rust/rubydex-mcp   # from a clone of shopify/rubydex"
        warn_if_rubydex_missing

        show_rubydex_claude_command  unless options[:skip_claude]
        show_rubydex_codex_snippet   unless options[:skip_codex]
        show_rubydex_opencode_snippet unless options[:skip_opencode]
      end

      def show_next_steps
        say "\nDone. Next:", :green
        say "  1. Ensure rubocop >= 1.85 is in your Gemfile."
        say "  2. Restart your AI assistant so it picks up the new MCP config."
        say "  3. Confirm the `rubocop` MCP server appears in the tool list."
        show_hook_next_steps
        show_codex_trust_step
        say "  6. Run `bundle exec railsdx-check doctor` to verify the install."
      end

      # Codex CLI refuses to run scripts under .codex/ until the directory is
      # trusted. Without this step the Stop / PostToolUse hooks silently do
      # nothing — which is the worst possible failure mode for a safety net.
      # Surface it loudly the first time we write the file.
      def show_codex_trust_step
        return if options[:skip_codex]
        return if all_hooks_skipped?

        say "  5. ", :green
        say "REQUIRED for Codex hooks", :yellow
        say "     Run once in this repo so Codex trusts the hook scripts:"
        say "       codex trust .codex/", :cyan
        say "     Without this, Codex will silently skip the railsdx hooks."
      end

      private

      def all_hooks_skipped?
        options[:skip_stop_hook] && options[:skip_rubocop_edited]
      end

      def show_hook_next_steps
        return if all_hooks_skipped?

        say "  4. RuboCop hooks wired into your agents:"
        say "       - bin/rubocop-edited runs PostToolUse (Edit/Write/MultiEdit)" unless options[:skip_rubocop_edited]
        say "       - bin/rubocop-changed runs at Stop / session.idle"            unless options[:skip_stop_hook]
        say "       (Codex CLI requires `codex` to trust .codex/ once.)"
      end

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

      # Drops/merges the hook settings file. Claude Code (.claude/settings.json)
      # and Codex CLI (.codex/hooks.json) share the exact same JSON schema, so
      # one merger drives both.
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

      # Reads the template and removes events the user opted out of.
      def filtered_hook_template
        template = JSON.parse(File.read(File.expand_path("templates/agent_hook_settings.json", __dir__)))
        template["hooks"].delete("Stop")        if options[:skip_stop_hook]
        template["hooks"].delete("PostToolUse") if options[:skip_rubocop_edited]
        template
      end

      # Walk every event in the template; append the group when its command
      # isn't already wired. Returns [merged_hash, [appended_event_names]].
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

      def warn_if_rubydex_missing
        expanded = File.expand_path(RUBYDEX_BIN.sub("${HOME}", "~"))
        return if File.executable?(expanded)

        say "\n  ⚠  #{RUBYDEX_BIN} not found.", :red
        say "     Run the cargo install above before restarting your agent."
      end

      def show_rubydex_claude_command
        say "\n  Claude Code (run once; writes to ~/.claude.json):", :green
        say %(    claude mcp add --scope user rubydex "#{RUBYDEX_BIN}"), :cyan
        say "    # verify: claude mcp get rubydex   # Scope must read 'User config'"
      end

      def show_rubydex_codex_snippet
        snippet = File.read(File.expand_path("templates/mcp/rubydex.codex.toml", __dir__))
        say "\n  Codex CLI — paste into ~/.codex/config.toml:", :green
        say snippet, :cyan
      end

      def show_rubydex_opencode_snippet
        snippet = File.read(File.expand_path("templates/mcp/rubydex.opencode.json", __dir__))
        say "\n  OpenCode — merge into ~/.config/opencode/opencode.json:", :green
        say snippet, :cyan
      end

      def merge_json(target_path, template_name, root_key:, server_key:)
        template = JSON.parse(File.read(File.expand_path("templates/#{template_name}", __dir__)))
        server_config = template.fetch(root_key).fetch(server_key)
        absolute = File.expand_path(target_path, destination_root)

        if File.exist?(absolute)
          existing = JSON.parse(File.read(absolute))
          existing[root_key] ||= {}
          if existing[root_key][server_key]
            say_status :skip, "#{target_path} (rubocop server already configured)", :yellow
            return
          end
          existing[root_key][server_key] = server_config
          File.write(absolute, "#{JSON.pretty_generate(existing)}\n")
          say_status :update, target_path, :green
        else
          create_file(target_path, "#{JSON.pretty_generate(template)}\n")
        end
      end
    end
  end
end
