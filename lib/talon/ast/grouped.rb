module Talon
  module AST
    class Grouped
      def to_code
        "(#{@expression.to_code})"
      end
    end
  end
end
