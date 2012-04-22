module Talon

  module AST
    class Node
      attr_accessor :target
    end

    class Identifier
      def resolve_under(res)
        @target = res.find(name)
      end
    end

    class Number
      def resolve_under(res)
        @target = MachineInteger.new(res)
      end
    end

    class Assignment
      def resolve_under(res)
        res.add_local variable.name, value.resolve_under(res).type
      end
    end
  end

  class LocalVariable
    def initialize(name, type)
      @name = name
      @type = type
    end

    attr_reader :name, :type
  end

  class MachineInteger
    def initialize(res)
      @type = res.find('talon.lang.Integer')
    end

    attr_reader :type
  end

  class Resolver
    def initialize
      @locals = {}
    end

    def add_local(name, type)
      @locals[name] = LocalVariable.new(name, type)
    end

    def find(name)
      @locals[name]
    end

    def resolve(node)
      node.resolve_under self
    end
  end
end
