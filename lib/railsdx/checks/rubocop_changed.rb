# frozen_string_literal: true

require "open3"

module Railsdx
  module Checks
    # Ported from the original bash bin/rubocop-changed: lint every Ruby file
    # changed in the working tree (tracked diffs, staged, untracked) and exit
    # non-zero with the full RuboCop report on stderr.
    class RubocopChanged < Base
      def check_name = "rubocop-changed"

      def run(_argv)
        return Result.new(exit_code: 0) if repo_root.nil?

        Dir.chdir(repo_root) { lint_changed_files }
      end

      private

      def lint_changed_files
        return Result.new(exit_code: 0) unless project_supports_rubocop?

        files = changed_ruby_files
        return Result.new(exit_code: 0) if files.empty?

        output, status = run_rubocop(files)
        return Result.new(exit_code: 0) if status.success?

        emit_report(output)
        Result.new(exit_code: 2, state: { files: files })
      end

      def project_supports_rubocop?
        File.exist?(".rubocop.yml") && File.exist?("Gemfile")
      end

      def run_rubocop(files)
        args = ["--force-exclusion", "--no-color", *files]
        args.unshift("--server") if rubocop_server_available?
        Open3.capture2e("bundle", "exec", "rubocop", *args)
      end

      # Pass the RuboCop report through verbatim — re-shaping would lose cop
      # names, source snippets, and the autocorrect summary.
      def emit_report(output)
        stderr.puts "[railsdx rubocop-changed] RuboCop reported offenses on changed Ruby files."
        stderr.puts "→ try: bundle exec rubocop -A  # safe autocorrects, then fix the rest"
        stderr.puts
        stderr.puts output
      end
    end
  end
end
