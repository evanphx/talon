require 'test/helper'

class TestMethodCall < Talon::TestCase
  def test_method_call
    node = parse("obj.foo")
    assert_kind_of Talon::AST::MethodCall, node
    assert_kind_of Talon::AST::Identifier, node.receiver
    assert_equal "obj", node.receiver.name
    assert_equal "foo", node.method_name
  end

  def test_method_call_on_number
    node = parse("1.foo")
    assert_kind_of Talon::AST::MethodCall, node
    assert_kind_of Talon::AST::Number, node.receiver
    assert_equal 1, node.receiver.value
    assert_equal "foo", node.method_name
  end

  def test_chained_method_call
    node = parse("1.obj.foo")
    assert_kind_of Talon::AST::MethodCall, node
    recv = node.receiver

    assert_kind_of Talon::AST::MethodCall, recv
    assert_kind_of Talon::AST::Number, recv.receiver
    assert_equal 1, recv.receiver.value
    assert_equal "obj", recv.method_name

    assert_equal "foo", node.method_name
  end

  def test_method_call_with_args
    node = parse("1.foo(2)")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 1, node.arguments.size
    assert_number node.arguments[0], 2
  end

  def test_method_call_with_no_args
    node = parse("1.foo()")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal nil, node.arguments
  end

  def test_method_call_with_multiple_args
    node = parse("1.foo(2,3)")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3
  end

  def test_method_call_with_multiple_args_spacing
    node = parse("1.foo( 2,3)")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3

    node = parse("1.foo( 2 ,3)")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3

    node = parse("1.foo( 2 , 3)")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3

    node = parse("1.foo( 2 , 3 )")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3

    node = parse("1.foo(\n2 , 3 )")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3

    node = parse("1.foo( \n 2 , \n  3 )")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3
  end

  def test_method_call_with_args_no_paren
    node = parse("1.foo 2")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 1, node.arguments.size
    assert_number node.arguments[0], 2
  end

  def test_method_call_with_args_no_paren_string_arg
    node = parse("1.foo \"hello\"")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 1, node.arguments.size
    assert_equal "hello", node.arguments[0].value
  end

  def test_method_call_with_args_no_paren_spaced
    node = parse("1.foo 2,\n  3")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3
  end

  def test_method_call_with_args_no_paren_twice
    assert_raises TestParser::ParseError do
      parse("1.bar 3.foo 2")
    end
  end

  def test_method_call_with_args_no_paren_somewhere_in_args
    assert_raises TestParser::ParseError do
      parse("1.bar 2, 3.foo 2")
    end
  end

  def test_method_call_with_args_no_paren_somewhere_in_args_with_grouping
    o = StringIO.new
    parse("1.bar 2, (3.foo 2)").to_code(o)

    assert_equal "1.bar(2, (3.foo(2)))", o.string
  end

  def test_method_call_with_no_paren1
    node = parse("1.fi c.qux(2)")

    assert_call node, "fi"
    assert_number node.receiver, 1
    assert_equal 1, node.arguments.size

    a1 = node.arguments[0]

    assert_call a1, "qux"
    assert_ident a1.receiver, "c"
    assert_equal 1, a1.arguments.size
    assert_number a1.arguments[0], 2
  end


  def test_method_call_with_no_paren2
    node = parse("1.fi a.foo, b.bar()")

    assert_call node, "fi"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size

    a1 = node.arguments[0]

    assert_call a1, "foo"
    assert_ident a1.receiver, "a"
    assert_equal nil, a1.arguments

    a2 = node.arguments[1]

    assert_call a2, "bar"
    assert_ident a2.receiver, "b"
    assert_equal nil, a2.arguments
  end

  def test_method_call_with_no_paren3
    node = parse("1.fi a.foo, c.qux(2)")

    assert_call node, "fi"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size

    a1 = node.arguments[0]

    assert_call a1, "foo"
    assert_ident a1.receiver, "a"
    assert_equal nil, a1.arguments

    a2 = node.arguments[1]

    assert_call a2, "qux"
    assert_ident a2.receiver, "c"
    assert_equal 1, a2.arguments.size
    assert_number a2.arguments[0], 2
  end

  def test_method_call_with_no_paren4
    node = parse("1.fi a.foo, b.bar(), c.qux(2)")

    assert_call node, "fi"
    assert_number node.receiver, 1
    assert_equal 3, node.arguments.size

    a1 = node.arguments[0]

    assert_call a1, "foo"
    assert_equal nil, a1.arguments

    a2 = node.arguments[1]

    assert_call a2, "bar"
    assert_equal nil, a2.arguments

    a3 = node.arguments[2]

    assert_call a3, "qux"
    assert_equal 1, a3.arguments.size
    assert_number a3.arguments[0], 2
  end

  def test_method_call_with_no_paren4_spacing
    node = parse("1.fi a.foo, b.bar(), c.qux( \n 2, \n 3 \n )")

    assert_call node, "fi"
    assert_number node.receiver, 1
    assert_equal 3, node.arguments.size

    a1 = node.arguments[0]

    assert_call a1, "foo"
    assert_equal nil, a1.arguments

    a2 = node.arguments[1]

    assert_call a2, "bar"
    assert_equal nil, a2.arguments

    a3 = node.arguments[2]

    assert_call a3, "qux"
    assert_equal 2, a3.arguments.size
    assert_number a3.arguments[0], 2
    assert_number a3.arguments[1], 3
  end

  def test_method_call_with_many_args_no_paren
    node = parse("1.foo 2, 3")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3
  end

  def test_function_call_with_no_paren1
    node = parse("fi c.qux(2)")

    assert_call node, "fi"
    assert_equal nil, node.receiver
    assert_equal 1, node.arguments.size

    a1 = node.arguments[0]

    assert_call a1, "qux"
    assert_ident a1.receiver, "c"
    assert_equal 1, a1.arguments.size
    assert_number a1.arguments[0], 2
  end

  def test_bracket_operator_with_method
    node = parse("a[1].foo")

    assert_kind_of Talon::AST::MethodCall, node

    recv = node.receiver
    assert_kind_of Talon::AST::BracketOperator, recv

    assert_ident recv.receiver, "a"

    assert_equal 1, recv.arguments.size
    assert_number recv.arguments[0], 1

    assert_equal "foo", node.method_name

    assert_equal nil, node.arguments
  end

  def test_bracket_operator_with_method_and_args
    node = parse("a[1].foo 2")

    assert_kind_of Talon::AST::MethodCall, node

    recv = node.receiver
    assert_kind_of Talon::AST::BracketOperator, recv

    assert_ident recv.receiver, "a"

    assert_equal 1, recv.arguments.size
    assert_number recv.arguments[0], 1

    assert_equal "foo", node.method_name

    assert_equal 1, node.arguments.size
    assert_number node.arguments[0], 2
  end

  def test_array_type_as_receiver
    node = parse "T[].new"

    assert_kind_of Talon::AST::MethodCall, node
    assert_equal "new", node.method_name

    recv = node.receiver

    assert_kind_of Talon::AST::ArrayType, recv
    assert_kind_of Talon::AST::NamedType, recv.inner
    assert_type "T", recv.inner
  end

  def test_templated_type_as_receiver
    node = parse "A<B>.new @capacity"

    assert_kind_of Talon::AST::MethodCall, node
    assert_equal "new", node.method_name

    recv = node.receiver

    assert_kind_of Talon::AST::TemplatedType, recv
    assert_kind_of Talon::AST::NamedType, recv.base
    assert_type "A", recv.base

    args = recv.arguments

    assert_equal 1, args.size

    assert_kind_of Talon::AST::NamedType, args[0]
    assert_type "B", args[0]

    args = node.arguments

    assert_equal 1, args.size

    assert_kind_of Talon::AST::InstanceVariable, args[0]
    assert_equal "capacity", args[0].name
  end


end
