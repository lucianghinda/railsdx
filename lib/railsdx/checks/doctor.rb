# frozen_string_literal: true

require "json"

module Railsdx
  module Checks
    # Read-only inspection of a project's installed railsdx artifacts.
    #
    # Walks the expected hook registry against the three agent config files
    # (.claude/settings.json, .codex/hooks.json, .opencode/plugins/) and
    # reports per-check ✓/✗ on stdout. Exits 0 if every expected wiring is
    # present, exit 1 if anything is missing or mis-wired.
    #
    # Skips an entire agent's section when that agent's config doesn't exist
    # — that's the documented signal the user opted out via --skip-claude
    # etc., not a failure mode.
    #
    # New units add a row to EXPECTED_HOOKS rather than editing the
    # inspector logic.
    class Doctor < Base
      # Each row describes a single railsdx wiring across the three agents.
      # claude / codex are JSON-hook descriptors; opencode is a plugin path.
      EXPECTED_HOOKS = [
        {
          check: "rubocop-changed",
          claude: { event: "Stop", command: "bin/rubocop-changed" },
          codex: { event: "Stop", command: "bin/rubocop-changed" },
          opencode: ".opencode/plugins/rubocop-changed.js"
        },
        {
          check: "rubocop-edited",
          claude: { event: "PostToolUse", command: "bin/rubocop-edited" },
          codex: { event: "PostToolUse", command: "bin/rubocop-edited" },
          opencode: ".opencode/plugins/rubocop-edited.js"
        }
      ].freeze

      CLAUDE_SETTINGS = ".claude/settings.json"
      CODEX_HOOKS     = ".codex/hooks.json"
      OPENCODE_DIR    = ".opencode/plugins"

      def check_name = "doctor"

      def run(_argv)
        return no_install_result if no_railsdx_artifacts?

        sections = build_sections
        sections.each { |section| render_section(section) }

        any_missing = sections.any? { |s| s[:rows].any? { |r| !r[:ok] } }
        Result.new(exit_code: any_missing ? 1 : 0)
      end

      private

      def build_sections
        sections = []
        sections << inspect_claude  if File.exist?(CLAUDE_SETTINGS)
        sections << inspect_codex   if File.exist?(CODEX_HOOKS)
        sections << inspect_opencode if Dir.exist?(OPENCODE_DIR)
        sections
      end

      def inspect_claude
        inspect_json_hooks(title: "Claude Code (#{CLAUDE_SETTINGS})", path: CLAUDE_SETTINGS, key: :claude)
      end

      def inspect_codex
        inspect_json_hooks(title: "Codex CLI (#{CODEX_HOOKS})", path: CODEX_HOOKS, key: :codex)
      end

      def inspect_json_hooks(title:, path:, key:)
        settings = read_json(path)
        rows = EXPECTED_HOOKS.map { |hook| json_hook_row(hook, settings, key) }
        { title: title, rows: rows }
      end

      def json_hook_row(hook, settings, key)
        expected = hook[key]
        commands = hook_commands(settings, expected[:event])
        if commands.include?(expected[:command])
          { ok: true, msg: "#{expected[:event]} hook → #{expected[:command]}" }
        elsif commands.empty?
          { ok: false, msg: "#{expected[:event]} hook missing (#{hook[:check]} not wired)" }
        else
          { ok: false, msg: "#{expected[:event]} hook points to #{commands.first}, expected #{expected[:command]}" }
        end
      end

      def inspect_opencode
        rows = EXPECTED_HOOKS.map { |hook| opencode_row(hook) }
        { title: "OpenCode (#{OPENCODE_DIR}/)", rows: rows }
      end

      def opencode_row(hook)
        path = hook[:opencode]
        return { ok: true, msg: "#{hook[:check]} has no OpenCode plugin (intentional)" } if path.nil?
        return { ok: true, msg: File.basename(path) } if File.exist?(path)

        { ok: false, msg: "#{File.basename(path)} missing (#{hook[:check]} not wired)" }
      end

      def hook_commands(settings, event)
        groups = settings.dig("hooks", event) || []
        groups.flat_map { |group| Array(group["hooks"]).map { |h| h["command"] } }.compact
      end

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

      def no_railsdx_artifacts?
        !File.exist?(CLAUDE_SETTINGS) && !File.exist?(CODEX_HOOKS) && !Dir.exist?(OPENCODE_DIR)
      end

      def read_json(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end
    end
  end
end
