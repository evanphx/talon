require 'talon/type'

module Talon
  module AST
    class Number
      def type(env)
        env.types["talon.lang.Integer"]
      end
    end

    class String
      def type(env)
        env.types["talon.lang.Char"].pointer
      end
    end

    class Assignment
      def type_check(e)
        name = variable.name

        if other = e.env[name]
          et = other.type(e)
          at = value.type(e)

          e.errors << TypeMismatch.new(name, et, at) unless et =~ at
        else
          e.env[name] = value
        end

        nil
      end
    end

    class MethodCall
      def type_check(e)
        name = method_name

        target = e.find_method(name)

        @arguments.zip(target.arguments) do |expr,et|
          at = expr.type(e)
          e.errors << TypeMismatch.new(name, et, at) unless et =~ at
        end
      end
    end

    class Sequence
      def type_check(e)
        @elements.each do |x|
          x.type_check(e)
        end
      end
    end
  end

  class TypeMismatch
    def initialize(id, expected, actual)
      @identifier = id
      @expected = expected
      @actual = actual
    end

    attr_reader :identifier, :expected, :actual
  end

  class TypeCheckError < RuntimeError
  end

  class TypeCheck
    def initialize(node)
      @node = node
      @errors = []
      @types = {
        "talon.lang.Integer" => Type.new("talon.lang.Integer"),
        "talon.lang.Char" => Type.new("talon.lang.Char")
      }

      @methods = {}
      @env = {}
    end

    attr_reader :types, :errors, :env

    class Method
      def initialize(name, args, ret)
        @name = name
        @arguments = args
        @type = ret
      end

      attr_reader :arguments, :type
    end

    def add_method(name, args, ret)
      @methods[name] = Method.new(name, args, ret)
    end

    def find_method(name)
      @methods[name]
    end

    def check
      @node.type_check self
      @errors.empty?
    end
  end
end
