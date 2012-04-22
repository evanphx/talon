require 'talon/templated_class'
require 'talon/ops'

module Talon
  class Environment
    def initialize(parent=Environment.toplevel)
      @identifiers = {}
      @parent = parent
    end

    @toplevel = nil

    def self.toplevel
      return @toplevel if @toplevel

      t = Environment.new(nil)
      t.add "int", Type.new("talon.lang.Int")

      t.add "String", Type.new("talon.lang.String")

      ary = TemplateType.new("talon.lang.Array")
      ary.add_operation "new", Op::ArrayNew.new
      t.add "Array", ary

      @toplevel = t
    end

    def import(node)
      Array(node).each do |n|
        case n
        when AST::ClassDefinition
          name = n.name
          if name.kind_of? AST::TemplatedName
            obj = TemplatedClass.new(self, n)
            name = name.name
          else
            obj = Class.new(self, n)
          end
        
          @identifiers[name] = obj
        end
      end
    end

    def find(n)
      @identifiers[n]
    end

    def add(name, obj)
      @identifiers[name] = obj
    end

    def lookup(name)
      if v = @identifiers[name]
        return v
      end

      return @parent.lookup(name) if @parent
    end

    def resolve(ast)
      case ast
      when AST::TemplatedType
        base = resolve(ast.base)
        args = ast.arguments.map { |i| resolve(i) }

        base.instance args
      when AST::NamedType
        lookup ast.identifier
      else
        raise "unsupported ast : #{ast.class}"
      end
    end
  end
end
