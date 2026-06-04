# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"

require_relative "rubocop_server"

module Railsdx
  module Checks
    # Abstract base class for railsdx quality checks.
    #
    # Subclasses implement #run(argv) and return a Checks::Result. Base handles
    # the cross-cutting concerns: stderr formatting, JSON state writing, and
    # turning the Result into a process exit code.
    #
    # The dispatcher (Checks::CLI) instantiates the subclass and calls #call.
    class Base
      include RubocopServer
      RAILSDX_STATE_DIR  = ".railsdx"
      RAILSDX_STATE_FILE = "last-check.json"

      attr_reader :stdout, :stderr, :stdin

      def initialize(stdout: $stdout, stderr: $stderr, stdin: $stdin)
        @stdout = stdout
        @stderr = stderr
        @stdin  = stdin
      end

      # Entry point invoked by Checks::CLI. Returns the integer exit code so
      # tests can assert on it without exercising Kernel#exit.
      def call(argv = [])
        result = run(Array(argv))
        emit(result)
        write_state(result)
        result.exit_code
      end

      # Subclasses override.
      def run(_argv)
        raise NotImplementedError, "#{self.class} must implement #run(argv) returning a Checks::Result"
      end

      # Name used in stderr headers and state file. Defaults to the demodulized,
      # underscored class name with dashes for readability ("RubocopChanged" →
      # "rubocop-changed"). Override on a subclass to pin a different name.
      def check_name
        klass = self.class.name.to_s.split("::").last
        klass.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
             .gsub(/([a-z\d])([A-Z])/, '\1_\2')
             .downcase
             .tr("_", "-")
      end

      # Helpers for subclasses. Pure stdlib + git.

      def changed_ruby_files
        changed_files(extensions: %w[.rb .rake .gemspec], also: %w[Gemfile Rakefile])
      end

      def changed_migrations
        changed_files(extensions: [".rb"]).select { |f| f.start_with?("db/migrate/") }
      end

      def changed_test_files
        changed_files(extensions: [".rb"]).select { |f| f =~ %r{\A(test|spec)/} }
      end

      # Render an offense report on stderr in the railsdx contract:
      #
      #   [railsdx <name>] <message body / offense list>
      #   → try: <fix_hint>
      #
      # Concrete checks call this; tests assert on the exact shape.
      def format_failure(check_name:, offenses:, fix_hint: nil)
        lines = ["[railsdx #{check_name}] reported #{offenses.size} offense#{"s" if offenses.size != 1}:"]
        offenses.each { |o| lines << "  #{format_offense(o)}" }
        lines << "→ try: #{fix_hint}" if fix_hint
        lines.join("\n")
      end

      # Write a small JSON record at .railsdx/last-check.json for OpenCode
      # plugins and the future TaskCompleted gate (R12) to read. Always
      # includes :check, :exit_code, :timestamp; merges in result.state if
      # the subclass provided one.
      def write_state(result)
        return if repo_root.nil?

        write_state_file(state_payload(result))
      rescue StandardError
        # State writing is best-effort. Never let a state-write failure mask
        # the check's real exit code.
        nil
      end

      # Resolve to the git repo root or nil if we're not in a repo.
      def repo_root
        @repo_root ||= begin
          out, _err, status = Open3.capture3("git", "rev-parse", "--show-toplevel")
          status.success? ? out.strip : nil
        end
      end

      private

      def emit(result)
        return if result.exit_code.zero? && result.offenses.empty?
        return if result.offenses.empty?

        stderr.puts format_failure(
          check_name: check_name,
          offenses: result.offenses,
          fix_hint: result.fix_hint
        )
      end

      def format_offense(offense)
        return offense if offense.is_a?(String)
        return offense.to_s unless offense.is_a?(Hash)

        format_offense_hash(offense)
      end

      def format_offense_hash(offense)
        location = [offense[:file], offense[:line], offense[:column]].compact.join(":")
        cop      = offense[:cop] ? " #{offense[:cop]}:" : ""
        message  = offense[:message] || offense[:msg] || offense.inspect
        location.empty? ? "#{cop.strip} #{message}".strip : "#{location}:#{cop} #{message}"
      end

      def state_payload(result)
        payload = { check: check_name, exit_code: result.exit_code, timestamp: Time.now.utc.iso8601 }
        payload.merge!(result.state) if result.state.is_a?(Hash)
        payload
      end

      def write_state_file(payload)
        dir = File.join(repo_root, RAILSDX_STATE_DIR)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, RAILSDX_STATE_FILE), "#{JSON.pretty_generate(payload)}\n")
      end

      def changed_files(extensions:, also: [])
        return [] if repo_root.nil?

        Dir.chdir(repo_root) do
          patterns = extensions.map { |ext| "*#{ext}" } + also
          out = git_changed(patterns)
          out.split("\n").reject(&:empty?).uniq
        end
      end

      def git_changed(patterns)
        diff_tracked = Open3.capture3("git", "diff", "--name-only", "--diff-filter=ACMR", "--", *patterns).first
        diff_staged  = Open3.capture3("git", "diff", "--name-only", "--diff-filter=ACMR", "--cached", "--",
                                      *patterns).first
        untracked    = Open3.capture3("git", "ls-files", "--others", "--exclude-standard", "--", *patterns).first
        [diff_tracked, diff_staged, untracked].join("\n")
      end
    end
  end
end
