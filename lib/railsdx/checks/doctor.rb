# frozen_string_literal: true

require "json"
require "toml-rb"

module Railsdx
  module Checks
    # Read-only inspection of a project's installed railsdx artifacts.
    #
    # Walks the expected wiring against the per-agent MCP configs and hook
    # configs and reports per-check ✓/✗ on stdout. Exits 0 if every required
    # wiring is present, 1 if anything is missing or mis-wired.
    #
    # Skips an entire agent's section when that agent has no MCP and no hook
    # artifacts — that's the documented signal the user opted out via
    # --skip-claude etc., not a failure mode.
    #
    # Rubydex MCP is treated as optional: it's only checked when at least one
    # agent already has it registered (the user installed with --with-rubydex).
    # Without that, rubydex rows are omitted entirely.
    class Doctor < Base
      EXPECTED_HOOKS = [
        { check: "rubocop-changed", event: "Stop",        command: "bin/rubocop-changed",
          opencode_plugin: ".opencode/plugins/rubocop-changed.js" },
        { check: "rubocop-edited",  event: "PostToolUse", command: "bin/rubocop-edited",
          opencode_plugin: ".opencode/plugins/rubocop-edited.js" }
      ].freeze

      # One row per agent describing where its MCP servers, hooks, and
      # opencode-style plugin directory live, plus how to read each one.
      # Adding a fourth agent is one row here.
      AGENTS = [
        { title: "Claude Code",
          mcp: { path: ".mcp.json", root: "mcpServers",   reader: :read_json },
          hooks: { path: ".claude/settings.json", reader: :read_json } },
        { title: "Codex CLI",
          mcp: { path: ".codex/config.toml", root: "mcp_servers",  reader: :read_toml },
          hooks: { path: ".codex/hooks.json", reader: :read_json } },
        { title: "OpenCode",
          mcp: { path: "opencode.json", root: "mcp", reader: :read_json },
          plugins: { dir: ".opencode/plugins" } }
      ].freeze

      def check_name = "doctor"

      def run(_argv)
        return no_install_result if no_artifacts?

        sections = compute_sections
        sections.each { |section| render_section(section) }
        Result.new(exit_code: exit_code_for(sections))
      end

      private

      def no_artifacts?
        AGENTS.none? { |agent| agent_has_artifacts?(agent) }
      end

      def compute_sections
        rubydex = rubydex_installed_anywhere?
        AGENTS.filter_map { |agent| inspect(agent, rubydex) }
      end

      def exit_code_for(sections)
        sections.any? { |s| s[:rows].any? { |r| !r[:ok] } } ? 1 : 0
      end

      def inspect(agent, rubydex)
        rows = mcp_rows(agent, rubydex) + hook_rows(agent) + plugin_rows(agent)
        return nil if rows.empty?

        { title: agent[:title], rows: rows }
      end

      def agent_has_artifacts?(agent)
        mcp_available?(agent) || hooks_available?(agent) || plugins_available?(agent)
      end

      def mcp_available?(agent)
        agent[:mcp] && File.exist?(agent[:mcp][:path])
      end

      def hooks_available?(agent)
        agent[:hooks] && File.exist?(agent[:hooks][:path])
      end

      def plugins_available?(agent)
        agent[:plugins] && Dir.exist?(agent[:plugins][:dir])
      end

      def rubydex_installed_anywhere?
        AGENTS.any? do |agent|
          next false unless mcp_available?(agent)

          mcp = agent[:mcp]
          send(mcp[:reader], mcp[:path]).dig(mcp[:root], "rubydex")
        end
      end

      # ===== Row builders (each returns [] when its source isn't applicable) =====

      def mcp_rows(agent, rubydex)
        return [] unless mcp_available?(agent)

        rows = [mcp_row(agent, "rubocop")]
        rows << mcp_row(agent, "rubydex") if rubydex
        rows
      end

      def mcp_row(agent, server)
        mcp = agent[:mcp]
        present = send(mcp[:reader], mcp[:path]).dig(mcp[:root], server)
        if present
          { ok: true, msg: "MCP server #{server} → #{mcp[:path]}" }
        else
          { ok: false, msg: "MCP server #{server} missing from #{mcp[:path]}" }
        end
      end

      def hook_rows(agent)
        return [] unless hooks_available?(agent)

        settings = send(agent[:hooks][:reader], agent[:hooks][:path])
        EXPECTED_HOOKS.map { |hook| json_hook_row(hook, settings, agent[:hooks][:path]) }
      end

      def plugin_rows(agent)
        return [] unless plugins_available?(agent)

        EXPECTED_HOOKS.map { |hook| opencode_plugin_row(hook) }
      end

      def json_hook_row(hook, settings, path)
        commands = hook_commands(settings, hook[:event])
        if commands.include?(hook[:command])
          { ok: true, msg: "#{hook[:event]} hook → #{hook[:command]} (#{path})" }
        elsif commands.empty?
          { ok: false, msg: "#{hook[:event]} hook missing in #{path} (#{hook[:check]} not wired)" }
        else
          { ok: false,
            msg: "#{hook[:event]} hook in #{path} points to #{commands.first}, expected #{hook[:command]}" }
        end
      end

      def opencode_plugin_row(hook)
        path = hook[:opencode_plugin]
        if File.exist?(path)
          { ok: true, msg: File.basename(path) }
        else
          { ok: false, msg: "#{File.basename(path)} missing (#{hook[:check]} not wired)" }
        end
      end

      def hook_commands(settings, event)
        groups = settings.dig("hooks", event) || []
        groups.flat_map { |group| Array(group["hooks"]).map { |h| h["command"] } }.compact
      end

      # ===== I/O =====

      def render_section(section)
        stdout.puts section[:title]
        section[:rows].each do |row|
          stdout.puts "  #{row[:ok] ? "✓" : "✗"} #{row[:msg]}"
        end
        stdout.puts
      end

      def no_install_result
        stdout.puts "No railsdx config detected. Run `bin/rails generate railsdx:install`."
        Result.new(exit_code: 1)
      end

      def read_json(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end

      def read_toml(path)
        TomlRB.parse(File.read(path))
      rescue StandardError
        {}
      end
    end
  end
end
