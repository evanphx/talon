require 'talon/code'

module Talon
  class AST::Sequence
    def [](idx)
      @elements[idx]
    end
  end
end
