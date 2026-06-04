# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "railsdx"
require "rails/generators"
require "rails/generators/test_case"
require_relative "../lib/generators/railsdx/install/install_generator"
require "minitest/autorun"
