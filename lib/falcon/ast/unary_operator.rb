module Falcon
  module AST
    class UnaryOperator
      def initialize(receiver, operator)
        @receiver = receiver
        @operator = operator
      end

      attr_reader :receiver, :operator
    end
  end
end
