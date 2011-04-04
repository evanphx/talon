module Talon
  module AST
    class Comment
      def initialize(text)
        @text = text
      end

      attr_reader :text
    end
  end
end
