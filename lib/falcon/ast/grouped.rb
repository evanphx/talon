module Falcon
  module AST
    class Grouped
      def initialize(expr)
        @expression = expr
      end

      def to_code
        "(#{@expression.to_code})"
      end
    end
  end
end
