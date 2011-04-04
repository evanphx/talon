module Talon
  module AST
    class TemplatedName
      def initialize(name, args)
        @name = name
        @arguments = args
      end

      attr_reader :name, :arguments
    end
  end
end
