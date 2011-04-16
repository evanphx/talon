module Talon
  module AST
    class BinaryOperator
      def to_code
        "(#{@receiver.to_code} #{@operator} #{@argument.to_code})"
      end
    end
  end
end
