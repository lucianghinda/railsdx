# frozen_string_literal: true

require "open3"

module Railsdx
  module Checks
    # Detects whether rubocop-server is up so checks can pass --server and
    # skip the ~1-2s cold start. Mixed into Checks::Base because every check
    # that shells out to rubocop benefits from it.
    #
    # Override knobs:
    #   RAILSDX_RUBOCOP_SERVER=1  → force --server (CI / containers where
    #                                the status probe isn't reachable)
    #   RAILSDX_RUBOCOP_SERVER=0  → never use --server
    module RubocopServer
      def rubocop_server_available?
        return false if ENV["RAILSDX_RUBOCOP_SERVER"] == "0"
        return true  if ENV["RAILSDX_RUBOCOP_SERVER"] == "1"

        _, _, status = Open3.capture3("bundle", "exec", "rubocop-server", "--status")
        status.success?
      rescue StandardError
        false
      end
    end
  end
end
