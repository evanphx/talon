module Talon
  module AST
    class BracketOperator
      def initialize(recv, arguments)
        @receiver = recv
        @arguments = arguments
      end

      attr_reader :receiver, :arguments

    end
  end
end
