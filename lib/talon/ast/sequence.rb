module Talon
  module AST
    class Sequence
      def initialize(elements)
        @elements = elements
      end

      attr_reader :elements

      def [](idx)
        @elements[idx]
      end

      def to_code
        @elements.map { |i| i.to_code }.join("\n")
      end
    end
  end
end
