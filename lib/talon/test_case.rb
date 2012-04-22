require 'test/unit'

module Talon
  class TestCase < Test::Unit::TestCase

    undef_method :default_test

    def parse(str, rule="root")
      parser = TestParser.new(str)

      yield parser if block_given?

      unless parser.parse(rule)
        parser.raise_error
      end

      return parser.ast
    end

    def assert_type(val, obj)
      assert_equal val.to_s, obj.to_s
    end

    def assert_number(obj, val)
      assert_kind_of Talon::AST::Number, obj
      assert_equal val, obj.value
    end

    def assert_ident(obj, name)
      assert_kind_of Talon::AST::Identifier, obj
      assert_equal name, obj.name
    end

    def assert_typed_ident(obj, name, type)
      assert_kind_of Talon::AST::TypedIdentifier, obj
      assert_equal name, obj.name
      assert_equal type, obj.type.to_s
    end

    def assert_seq(obj, size)
      assert_kind_of Talon::AST::Sequence, obj
      assert_equal size, obj.elements.size
    end

    def assert_if(obj)
      assert_kind_of Talon::AST::If, obj
      return [obj.condition, obj.then_body, obj.else_body]
    end

    def assert_call(obj, name)
      assert_kind_of Talon::AST::MethodCall, obj
      assert_equal obj.method_name, name
    end
  end
end
