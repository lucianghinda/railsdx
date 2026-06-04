# frozen_string_literal: true

module Railsdx
  module Checks
    # Return value from a concrete check's #run. The Base wrapper turns this
    # into stderr output + an exit code + a JSON state record.
    #
    # offenses is an array of plain hashes shaped like:
    #   { file: "app/models/foo.rb", line: 12, column: 3, message: "...", cop: "Style/Foo" }
    # All keys optional except :message. Base.format_failure renders whichever
    # are present.
    Result = Struct.new(:exit_code, :offenses, :fix_hint, :state, keyword_init: true) do
      def initialize(exit_code:, offenses: [], fix_hint: nil, state: nil)
        super
      end

      def success? = exit_code.zero?
    end
  end
end
