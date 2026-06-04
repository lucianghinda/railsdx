# frozen_string_literal: true

require "json"
require "open3"

module Railsdx
  module Checks
    # R1: run `rubocop -A --force-exclusion <file>` on every file the agent
    # edits via PostToolUse (Edit | Write | MultiEdit). Style fixes happen
    # mid-turn, not at Stop — so the agent's next tool call already sees the
    # corrected file and turn-end RuboCop has nothing left to complain about.
    #
    # Input contract: file path is taken from argv[0] when invoked directly,
    # or from stdin JSON (`{"tool_input": {"file_path": "..."}}`) when
    # dispatched from a Claude / Codex PostToolUse hook.
    #
    # Exits 0 on success even when RuboCop autocorrected the file — the
    # whole point is silent fixes. Exits 2 only when offenses remain after
    # autocorrect; those go on stderr so the agent's next tool result
    # surfaces them.
    class RubocopEdited < Base
      RUBY_EXTENSIONS = %w[.rb .rake .gemspec].freeze
      RUBY_FILENAMES  = %w[Gemfile Rakefile].freeze

      def check_name = "rubocop-edited"

      def run(argv)
        file = resolve_file_path(argv)
        return Result.new(exit_code: 0) if file.nil? || !ruby_file?(file)
        return Result.new(exit_code: 0) if repo_root.nil?

        Dir.chdir(repo_root) { autocorrect(file) }
      end

      private

      def autocorrect(file)
        return Result.new(exit_code: 0) unless project_supports_rubocop?

        output, status = run_rubocop(file)
        return Result.new(exit_code: 0) if status.success?

        emit_report(file, output)
        Result.new(exit_code: 2, state: { file: file })
      end

      def resolve_file_path(argv)
        return argv.first if argv.first && !argv.first.start_with?("-")

        parse_stdin_file_path
      end

      # Hook integrations pipe the tool_use payload on stdin. Both Claude
      # Code and Codex CLI use the shape `{"tool_input": {"file_path": ...}}`.
      def parse_stdin_file_path
        return nil if stdin.respond_to?(:tty?) && stdin.tty?

        raw = stdin.read
        return nil if raw.nil? || raw.empty?

        JSON.parse(raw).dig("tool_input", "file_path")
      rescue JSON::ParserError
        nil
      end

      def ruby_file?(path)
        RUBY_EXTENSIONS.include?(File.extname(path)) ||
          RUBY_FILENAMES.include?(File.basename(path))
      end

      def project_supports_rubocop?
        File.exist?(".rubocop.yml") && File.exist?("Gemfile")
      end

      def run_rubocop(file)
        args = ["-A", "--force-exclusion", "--no-color", file]
        args.unshift("--server") if rubocop_server_available?
        Open3.capture2e("bundle", "exec", "rubocop", *args)
      end

      def emit_report(file, output)
        stderr.puts "[railsdx rubocop-edited] un-autocorrectable offenses in #{file}:"
        stderr.puts "→ try: fix the remaining offenses by hand before continuing"
        stderr.puts
        stderr.puts output
      end
    end
  end
end
