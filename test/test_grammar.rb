require 'test/unit'
require 'rubygems'
require 'kpeg'

require 'falcon'

KPeg.load File.expand_path("../../grammar.kpeg", __FILE__), "TestParser"

class TestGrammar < Test::Unit::TestCase
  def parse(str)
    parser = TestParser.new(str)

    yield parser if block_given?

    unless parser.parse
      parser.raise_error
    end

    return parser.ast
  end

  def assert_number(obj, val)
    assert_kind_of Falcon::AST::Number, obj
    assert_equal val, obj.value
  end

  def assert_ident(obj, name)
    assert_kind_of Falcon::AST::Identifier, obj
    assert_equal name, obj.name
  end

  def assert_typed_ident(obj, name, type)
    assert_kind_of Falcon::AST::TypedIdentifier, obj
    assert_equal name, obj.name
    assert_equal type, obj.type
  end

  def assert_seq(obj, size)
    assert_kind_of Falcon::AST::Sequence, obj
    assert_equal size, obj.elements.size
  end

  def assert_if(obj)
    assert_kind_of Falcon::AST::If, obj
    return [obj.condition, obj.then, obj.else]
  end

  def assert_call(obj, name)
    assert_kind_of Falcon::AST::MethodCall, obj
    assert_equal obj.method_name, name
  end

  def test_integer_literal
    node = parse("1")
    assert_kind_of Falcon::AST::Number, node
    assert_equal 1, node.value
  end

  def test_float_literal
    node = parse("1.1")
    assert_kind_of Falcon::AST::Number, node
    assert_equal 1.1, node.value
  end

  def test_true_literal
    node = parse("true")
    assert_kind_of Falcon::AST::True, node
  end

  def test_false_literal
    node = parse("false")
    assert_kind_of Falcon::AST::False, node
  end

  def test_identifier
    node = parse("obj")
    assert_kind_of Falcon::AST::Identifier, node
    assert_equal "obj", node.name
  end

  def test_method_call
    node = parse("obj.foo")
    assert_kind_of Falcon::AST::MethodCall, node
    assert_kind_of Falcon::AST::Identifier, node.receiver
    assert_equal "obj", node.receiver.name
    assert_equal "foo", node.method_name
  end

  def test_method_call_on_number
    node = parse("1.foo")
    assert_kind_of Falcon::AST::MethodCall, node
    assert_kind_of Falcon::AST::Number, node.receiver
    assert_equal 1, node.receiver.value
    assert_equal "foo", node.method_name
  end

  def test_chained_method_call
    node = parse("1.obj.foo")
    assert_kind_of Falcon::AST::MethodCall, node
    recv = node.receiver

    assert_kind_of Falcon::AST::MethodCall, recv
    assert_kind_of Falcon::AST::Number, recv.receiver
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
  end

  def test_method_call_with_args_no_paren
    node = parse("1.foo 2")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 1, node.arguments.size
    assert_number node.arguments[0], 2
  end

  def test_method_call_with_many_args_no_paren
    node = parse("1.foo 2, 3")

    assert_call node, "foo"
    assert_number node.receiver, 1
    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 2
    assert_number node.arguments[1], 3
  end

  def test_unary_operator
    node = parse("+1")

    assert_kind_of Falcon::AST::UnaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1
  end

  def test_strange_unary_operator
    node = parse("`1")

    assert_kind_of Falcon::AST::UnaryOperator, node
    assert_equal "`", node.operator

    assert_number node.receiver, 1
  end

  def test_binary_operator
    node = parse("1+2")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1
    assert_number node.argument, 2
  end

  def test_crazy_binary_operator
    node = parse("1 <+-+> 2")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "<+-+>", node.operator

    assert_number node.receiver, 1
    assert_number node.argument, 2
  end

  def test_chevron_operator
    node = parse("1 << 2 << 3")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "<<", node.operator

    recv = node.receiver
    assert_kind_of Falcon::AST::BinaryOperator, recv
    assert_equal "<<", recv.operator

    assert_number recv.receiver, 1
    assert_number recv.argument, 2

    assert_number node.argument, 3
  end

  def test_right_assoc
    node = parse("1 << 2 << 3") { |x| x.set_assoc "<<", :right }

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "<<", node.operator

    assert_number node.receiver, 1

    arg = node.argument
    assert_kind_of Falcon::AST::BinaryOperator, arg
    assert_equal "<<", arg.operator

    assert_number arg.receiver, 2
    assert_number arg.argument, 3
  end

  def test_binary_operator_precedence
    node = parse("1+2*3")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1

    arg = node.argument
    assert_kind_of Falcon::AST::BinaryOperator, arg
    assert_equal "*", arg.operator

    assert_number arg.receiver, 2
    assert_number arg.argument, 3
  end

  def test_binary_operator_precedence_2
    node = parse("1*2+3")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    recv = node.receiver
    assert_kind_of Falcon::AST::BinaryOperator, recv
    assert_equal "*", recv.operator

    assert_number recv.receiver, 1
    assert_number recv.argument, 2

    assert_number node.argument, 3
  end

  def test_binary_operator_precedence_3
    node = parse("1*2+3*4")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    recv = node.receiver
    assert_kind_of Falcon::AST::BinaryOperator, recv
    assert_equal "*", recv.operator

    assert_number recv.receiver, 1
    assert_number recv.argument, 2

    arg = node.argument
    assert_kind_of Falcon::AST::BinaryOperator, arg
    assert_number arg.receiver, 3
    assert_number arg.argument, 4
  end

  def test_binary_operator_4
    node = parse "a == b && c == d || e == f"
    assert_equal "(((a == b) && (c == d)) || (e == f))", node.to_code
  end

  def test_binary_operator_5
    node = parse "a := b && c == d || e == f"
    assert_equal "(a := ((b && (c == d)) || (e == f)))", node.to_code
  end

  def test_binary_operator_with_method_call
    node = parse("1+a.b")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1

    assert_call node.argument, "b"
    assert_ident node.argument.receiver, "a"
  end

  def test_binary_operator_with_method_call2
    node = parse("a.b + 1")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_call node.receiver, "b"
    assert_ident node.receiver.receiver, "a"

    assert_number node.argument, 1
  end

  def test_binary_operator_with_method_call3
    node = parse("a.b.c + 1")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    recv = node.receiver
    assert_call recv, "c"
    assert_call recv.receiver, "b"
    assert_ident recv.receiver.receiver, "a"

    assert_number node.argument, 1
  end

  def test_binary_operator_with_method_call4
    node = parse("a.b + c.d")

    assert_kind_of Falcon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_call node.receiver, "b"
    assert_ident node.receiver.receiver, "a"

    assert_call node.argument, "d"
    assert_ident node.argument.receiver, "c"
  end

  def test_binary_operator_in_noparen_args
    assert_equal "a.b((c + 1))", parse("a.b c + 1").to_code
  end

  def test_if_with_else
    node = parse "if 1\nyes\nelse\nno\nend"
    assert_kind_of Falcon::AST::If, node

    cond = node.condition
    tb = node.then
    eb = node.else

    assert_number cond, 1
    assert_ident tb, "yes"
    assert_ident eb, "no"
  end

  def test_if_without_else
    node = parse "if 1\nyes\nend"
    assert_kind_of Falcon::AST::If, node

    cond = node.condition
    tb = node.then

    assert_number cond, 1
    assert_ident tb, "yes"
    assert_equal nil, node.else
  end

  def test_sequence
    node = parse "1\n2"
    assert_kind_of Falcon::AST::Sequence, node
    assert_equal 2, node.elements.size

    assert_number node.elements[0], 1
    assert_number node.elements[1], 2
  end

  def test_sequence_in_if
    node = parse "if 1\n2\n3\nend"

    cond = node.condition
    tb = node.then

    assert_number cond, 1
    assert_seq tb, 2
    assert_number tb[0], 2
    assert_number tb[1], 3
  end

  def test_if_within_if
    node = parse "if 1\n2\nif 3\n4\nend\n5\nend"
    c,t,e = assert_if node

    assert_number c, 1
    assert_seq t, 3
    assert_number t[0], 2

    c2,t2,e2 = assert_if t[1]

    assert_number c2, 3
    assert_number t2, 4
    assert_equal nil, e2

    assert_number t[2], 5

    assert_equal nil, e
  end

  def test_def
    node = parse "def foo\nend"
    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal nil, node.body
  end

  def test_def_with_return_type
    node = parse "def foo:int\nend"
    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal "int", node.return_type
    assert_equal nil, node.body
  end

  def test_def_with_body
    node = parse "def foo\n1\n2\nend"
    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_body_and_return_type
    node = parse "def foo:int\n1\n2\nend"
    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal "int", node.return_type

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_arg
    node = parse "def foo(a)\nend"

    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"

    assert_equal nil, node.body
  end

  def test_def_with_arg_and_return_type
    node = parse "def foo(a):int\nend"

    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal "int", node.return_type

    assert_ident node.arguments[0], "a"

    assert_equal nil, node.body
  end

  def test_def_with_arg_and_body
    node = parse "def foo(a)\n1\n2\nend"

    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_arg_and_body_and_return_type
    node = parse "def foo(a):int\n1\n2\nend"

    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal "int", node.return_type

    assert_ident node.arguments[0], "a"

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_many_args
    node = parse "def foo(a,b)\nend"

    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"
    assert_ident node.arguments[1], "b"

    assert_equal nil, node.body
  end

  def test_def_with_many_args_spaced
    node = parse "def foo(a, b)\nend"

    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"
    assert_ident node.arguments[1], "b"

    node = parse "def foo( a, b)\nend"
    assert_ident node.arguments[0], "a"
    assert_ident node.arguments[1], "b"

    node = parse "def foo( a, b )\nend"
    assert_ident node.arguments[0], "a"
    assert_ident node.arguments[1], "b"
  end

  def test_def_with_typed_arg
    node = parse "def foo(a:int)\nend"

    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_typed_ident node.arguments[0], "a", "int"

    assert_equal nil, node.body
  end

  def test_def_with_many_typed_args
    node = parse "def foo(a:int,b:float)\nend"

    assert_kind_of Falcon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_typed_ident node.arguments[0], "a", "int"
    assert_typed_ident node.arguments[1], "b", "float"

    assert_equal nil, node.body
  end

  def test_class
    node = parse "class foo\nend"

    assert_kind_of Falcon::AST::ClassDefinition, node
    assert_equal "foo", node.name
  end

  def test_class_with_superclass
    node = parse "class foo < bar\nend"

    assert_kind_of Falcon::AST::ClassDefinition, node
    assert_equal "foo", node.name
    assert_equal "bar", node.superclass_name
  end

  def test_class_with_body
    node = parse "class foo\ndef bar\nend\nend"
    assert_kind_of Falcon::AST::ClassDefinition, node
    assert_equal "foo", node.name

    assert_kind_of Falcon::AST::MethodDefinition, node.body
    assert_equal "bar", node.body.name
  end

  def test_class_with_superclass_and_body
    node = parse "class foo < bar\ndef bar\nend\nend"

    assert_kind_of Falcon::AST::ClassDefinition, node
    assert_equal "foo", node.name
    assert_equal "bar", node.superclass_name

    assert_kind_of Falcon::AST::MethodDefinition, node.body
    assert_equal "bar", node.body.name
  end


end
