module Falcon
  module AST
    class Sequence
      def initialize(elements)
        @elements = elements
      end

      attr_reader :elements

      def [](idx)
        @elements[idx]
      end
    end
  end
end
