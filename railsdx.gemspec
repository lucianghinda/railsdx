# frozen_string_literal: true

require_relative "lib/railsdx/version"

Gem::Specification.new do |spec|
  spec.name = "railsdx"
  spec.version = Railsdx::VERSION
  spec.authors = ["Lucian Ghinda"]
  spec.email = ["lucianghinda@users.noreply.github.com"]

  spec.summary = "Wire the RuboCop MCP server into Claude Code, Codex, and OpenCode."
  spec.description = "A Rails generator that drops MCP server configuration and agent " \
                     "instructions so AI coding assistants use RuboCop's built-in MCP " \
                     "server (rubocop --mcp) as their lint and autocorrect tool."
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
end
