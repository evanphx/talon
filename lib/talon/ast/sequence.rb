module Talon
  module AST
    class Sequence
      def [](idx)
        @elements[idx]
      end

      def to_code
        @elements.map { |i| i.to_code }.join("\n")
      end
    end
  end
end
