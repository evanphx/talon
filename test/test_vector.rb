require 'test/helper'
require 'talon/environment'

require 'pp'

class TestVector < Talon::TestCase
  CODE = <<-CODE
class Vector<T>
  var @size : int
  var @capacity : int
  var @elements : Array<T>

  def initialize
    @size = 0
    @capacity = 10
    @elements = T[].new @capacity
  end

  def put(e : T)
    var idx = @size

    @size += 1

    if @size > @capacity
      resize
    end

    @elements[idx] = e
  end

  def get(i : int) : T
    @elements[i]
  end

  def resize
    var new_size = @capacity + 10
    var n = T[].new new_size

    @elements = n
    @capacity = new_size
  end
end
  CODE

  def test_parse
    node = parse CODE

    env = Talon::Environment.new
    env.import node

    cls = env.find "Vector"
    assert_kind_of Talon::TemplatedClass, cls

    i = cls.ivars
    assert_equal "size", i[0].name
    assert_equal "talon.lang.Int", i[0].type.name

    assert_equal "capacity", i[1].name
    assert_equal "talon.lang.Int", i[1].type.name

    assert_equal "elements", i[2].name
    assert_equal "talon.lang.Array", i[2].type.base.name
    arg = i[2].type.arguments[0]

    assert_kind_of Talon::TemplateArgumentType, arg
    assert_equal "T", arg.name
  end

  def test_initialize
    node = parse CODE

    env = Talon::Environment.new
    env.import node

    cls = env.find "Vector"
    assert_kind_of Talon::TemplatedClass, cls

    meth = cls.find "initialize"

    assert_kind_of Talon::Method, meth

    ops = meth.render

    assert_kind_of Talon::Op::SetIvar, ops[0]
    assert_kind_of Talon::Op::SetIvar, ops[1]
    assert_kind_of Talon::Op::SetIvar, ops[2]
  end
end
