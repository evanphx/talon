module Falcon
  module AST
    class If
      def initialize(cond, tb, eb)
        @condition = cond
        @then = tb
        @else = eb
      end

      attr_reader :condition, :then, :else
    end
  end
end
