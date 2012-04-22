require 'test/helper'
require 'talon/type_check'

class TestTypeCheck < Talon::TestCase
  def test_check_locals
    node = parse "a = 1\na = \"hello\""

    tc = Talon::TypeCheck.new node
    assert_equal false, tc.check

    e = tc.errors.first
    assert_kind_of Talon::TypeMismatch, e
    assert_equal "a", e.identifier

    assert_equal tc.types['talon.lang.Integer'], e.expected
    assert_equal tc.types['talon.lang.Char'].pointer, e.actual
  end

  def test_check_call
    node = parse "foo 1"

    tc = Talon::TypeCheck.new node
    tc.add_method "foo", [tc.types['talon.lang.Char'].pointer],
                          tc.types['talon.lang.Void']

    assert_equal false, tc.check

    e = tc.errors.first

    assert_kind_of Talon::TypeMismatch, e
    assert_equal "foo", e.identifier

    assert_equal tc.types['talon.lang.Char'].pointer, e.expected
    assert_equal tc.types['talon.lang.Integer'], e.actual
  end

  def test_check_ivar
    node = parse <<-CODE
      class Blah
        var @age : int

        def set
          @age = "hello"
        end
      end
    CODE

    env = Talon::Environment.new
    env.import node

    cls = env.find "Blah"
    meth = cls.find "set"

    e = assert_raises Talon::TypeCheckError do
      meth.render
    end
  end
end
