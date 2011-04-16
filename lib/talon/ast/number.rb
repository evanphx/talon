module Talon
  module AST
    class Number
      def to_code
        @value.to_s
      end
    end
  end
end
