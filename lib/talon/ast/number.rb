module Talon
  module AST
    class Number
      attr_reader :value

      def initialize(val)
        @value = val
      end

      def to_code
        @value.to_s
      end
    end
  end
end
