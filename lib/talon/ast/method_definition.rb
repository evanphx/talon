module Talon
  module AST
    class MethodDefinition
      def initialize(name, args, body, return_type)
        @name = name
        @arguments = args
        @body = body
        @return_type = return_type
      end

      attr_reader :name, :arguments, :body, :return_type
    end
  end
end
