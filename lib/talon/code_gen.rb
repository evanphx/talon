require 'stringio'
require 'talon/code'

module Talon
  class CodeGen
    def initialize(node)
      @node = node
    end

    def output(where=StringIO.new)
      @node.to_code(where)

      where
    end
  end
end
