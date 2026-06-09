# frozen_string_literal: true

require_relative "lib/railsdx/version"

Gem::Specification.new do |spec|
  spec.name = "railsdx"
  spec.version = Railsdx::VERSION
  spec.authors = ["Lucian Ghinda"]
  spec.email = ["lucianghinda@users.noreply.github.com"]

  spec.summary = "Local agent-config generator for Claude Code, Codex CLI, and OpenCode."
  spec.description = "A Rails generator that writes per-agent configuration entirely " \
                     "inside your project folder so Claude Code, Codex CLI, and OpenCode " \
                     "share the same RuboCop workflow. RuboCop is the v0 payload; the " \
                     "generator never touches files outside the project root."
  spec.homepage = "https://github.com/lucianghinda/railsdx"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("lib/**/*") + Dir.glob("exe/*") + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.bindir = "exe"
  spec.executables = ["railsdx-check"]
  spec.require_paths = ["lib"]

  # railties for Rails::Generators::Base. RuboCop is intentionally NOT a dependency:
  # the host app supplies its own rubocop (>= 1.85 for --mcp).
  spec.add_dependency "railties", ">= 7.0"

  # Thor powers exe/railsdx-check's subcommand dispatch. It's already a
  # transitive dep of railties; declaring it explicitly pins the contract.
  spec.add_dependency "thor", ">= 1.0"

  # toml-rb reads and writes Codex CLI's project-local .codex/config.toml.
  # Codex stores MCP servers as TOML; the generator merges into existing
  # files idempotently, which needs a real parser.
  spec.add_dependency "toml-rb", "~> 4.0"
end
