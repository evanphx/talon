module Talon
  module AST
    class ClassDefinition
      def initialize(name,superclass_name,body)
        @name = name
        @superclass_name = superclass_name
        @body = body
      end

      attr_reader :name, :superclass_name, :body
    end
  end
end
