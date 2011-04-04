module Talon
  module AST
    class Identifier
      def initialize(name)
        @name = name
      end

      attr_reader :name

      def to_code
        @name
      end
    end

    class TypedIdentifier
      def initialize(name, type)
        @name = name
        @type = type
      end

      attr_reader :name, :type
    end
  end
end
