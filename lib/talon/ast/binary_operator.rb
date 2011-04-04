module Talon
  module AST
    class BinaryOperator
      def initialize(receiver, argument, operator)
        @receiver = receiver
        @argument = argument
        @operator = operator
      end

      attr_reader :receiver, :argument, :operator

      def to_code
        "(#{@receiver.to_code} #{@operator} #{@argument.to_code})"
      end
    end
  end
end
