require 'test/unit'
require 'rubygems'
require 'kpeg'

require 'talon'

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
    assert_equal type, obj.type
  end

  def assert_seq(obj, size)
    assert_kind_of Talon::AST::Sequence, obj
    assert_equal size, obj.elements.size
  end

  def assert_if(obj)
    assert_kind_of Talon::AST::If, obj
    return [obj.condition, obj.then, obj.else]
  end

  def assert_call(obj, name)
    assert_kind_of Talon::AST::MethodCall, obj
    assert_equal obj.method_name, name
  end

  def test_integer_literal
    node = parse("1")
    assert_kind_of Talon::AST::Number, node
    assert_equal 1, node.value
  end

  def test_float_literal
    node = parse("1.1")
    assert_kind_of Talon::AST::Number, node
    assert_equal 1.1, node.value
  end

  def test_true_literal
    node = parse("true")
    assert_kind_of Talon::AST::True, node
  end

  def test_false_literal
    node = parse("false")
    assert_kind_of Talon::AST::False, node
  end

  def test_identifier
    node = parse("obj")
    assert_kind_of Talon::AST::Identifier, node
    assert_equal "obj", node.name
  end

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

  def test_method_call_with_args
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
    assert_equal "1.bar(2, (3.foo(2)))", parse("1.bar 2, (3.foo 2)").to_code
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

  def test_bracket_operator
    node = parse("a[1]")

    assert_kind_of Talon::AST::BracketOperator, node
    assert_ident node.receiver, "a"

    assert_equal 1, node.arguments.size
    assert_number node.arguments[0], 1
  end

  def test_bracket_operator_multiple
    node = parse("a[1,2]")

    assert_kind_of Talon::AST::BracketOperator, node
    assert_ident node.receiver, "a"

    assert_equal 2, node.arguments.size
    assert_number node.arguments[0], 1
    assert_number node.arguments[1], 2
  end

  def test_bracket_operator_chain
    node = parse("a[1][2]")

    assert_kind_of Talon::AST::BracketOperator, node

    recv = node.receiver
    assert_kind_of Talon::AST::BracketOperator, recv

    assert_ident recv.receiver, "a"

    assert_equal 1, recv.arguments.size
    assert_number recv.arguments[0], 1

    assert_equal 1, node.arguments.size
    assert_number node.arguments[0], 2
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

  def test_unary_operator
    node = parse("+1")

    assert_kind_of Talon::AST::UnaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1
  end

  def test_strange_unary_operator
    node = parse("`1")

    assert_kind_of Talon::AST::UnaryOperator, node
    assert_equal "`", node.operator

    assert_number node.receiver, 1
  end

  def test_binary_operator
    node = parse("1+2")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1
    assert_number node.argument, 2
  end

  def test_crazy_binary_operator
    node = parse("1 <+-+> 2")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "<+-+>", node.operator

    assert_number node.receiver, 1
    assert_number node.argument, 2
  end

  def test_chevron_operator
    node = parse("1 << 2 << 3")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "<<", node.operator

    recv = node.receiver
    assert_kind_of Talon::AST::BinaryOperator, recv
    assert_equal "<<", recv.operator

    assert_number recv.receiver, 1
    assert_number recv.argument, 2

    assert_number node.argument, 3
  end

  def test_right_assoc
    node = parse("1 << 2 << 3") { |x| x.set_assoc "<<", :right }

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "<<", node.operator

    assert_number node.receiver, 1

    arg = node.argument
    assert_kind_of Talon::AST::BinaryOperator, arg
    assert_equal "<<", arg.operator

    assert_number arg.receiver, 2
    assert_number arg.argument, 3
  end

  def test_binary_operator_precedence
    node = parse("1+2*3")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1

    arg = node.argument
    assert_kind_of Talon::AST::BinaryOperator, arg
    assert_equal "*", arg.operator

    assert_number arg.receiver, 2
    assert_number arg.argument, 3
  end

  def test_binary_operator_precedence_2
    node = parse("1*2+3")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    recv = node.receiver
    assert_kind_of Talon::AST::BinaryOperator, recv
    assert_equal "*", recv.operator

    assert_number recv.receiver, 1
    assert_number recv.argument, 2

    assert_number node.argument, 3
  end

  def test_binary_operator_precedence_3
    node = parse("1*2+3*4")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    recv = node.receiver
    assert_kind_of Talon::AST::BinaryOperator, recv
    assert_equal "*", recv.operator

    assert_number recv.receiver, 1
    assert_number recv.argument, 2

    arg = node.argument
    assert_kind_of Talon::AST::BinaryOperator, arg
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

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1

    assert_call node.argument, "b"
    assert_ident node.argument.receiver, "a"
  end

  def test_binary_operator_with_method_call2
    node = parse("a.b + 1")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_call node.receiver, "b"
    assert_ident node.receiver.receiver, "a"

    assert_number node.argument, 1
  end

  def test_binary_operator_with_method_call3
    node = parse("a.b.c + 1")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    recv = node.receiver
    assert_call recv, "c"
    assert_call recv.receiver, "b"
    assert_ident recv.receiver.receiver, "a"

    assert_number node.argument, 1
  end

  def test_binary_operator_with_method_call4
    node = parse("a.b + c.d")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_call node.receiver, "b"
    assert_ident node.receiver.receiver, "a"

    assert_call node.argument, "d"
    assert_ident node.argument.receiver, "c"
  end

  def test_binary_operator_with_method_call5
    node = parse("a.b(2) + c.d(3)")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_call node.receiver, "b"
    assert_ident node.receiver.receiver, "a"
    assert_number node.receiver.arguments[0], 2

    assert_call node.argument, "d"
    assert_ident node.argument.receiver, "c"
    assert_number node.argument.arguments[0], 3
  end

  def test_binary_operator_with_method_call6
    node = parse("a.b() + c.d()")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_call node.receiver, "b"
    assert_ident node.receiver.receiver, "a"
    assert_equal nil, node.receiver.arguments

    assert_call node.argument, "d"
    assert_ident node.argument.receiver, "c"
    assert_equal nil, node.argument.arguments
  end

  def test_binary_operator_in_noparen_args
    assert_equal "a.b((c + 1))", parse("a.b c + 1").to_code
  end

  def test_if_with_else
    node = parse "if 1\nyes\nelse\nno\nend"
    assert_kind_of Talon::AST::If, node

    cond = node.condition
    tb = node.then
    eb = node.else

    assert_number cond, 1
    assert_ident tb, "yes"
    assert_ident eb, "no"
  end

  def test_if_with_else_semicolon
    node = parse "if 1;yes;else;no;end"
    assert_kind_of Talon::AST::If, node

    cond = node.condition
    tb = node.then
    eb = node.else

    assert_number cond, 1
    assert_ident tb, "yes"
    assert_ident eb, "no"
  end

  def test_if_without_else
    node = parse "if 1\nyes\nend"
    assert_kind_of Talon::AST::If, node

    cond = node.condition
    tb = node.then

    assert_number cond, 1
    assert_ident tb, "yes"
    assert_equal nil, node.else
  end

  def test_sequence
    node = parse "1\n2"
    assert_kind_of Talon::AST::Sequence, node
    assert_equal 2, node.elements.size

    assert_number node.elements[0], 1
    assert_number node.elements[1], 2
  end

  def test_sequence_with_semicolon
    node = parse "1;2"
    assert_kind_of Talon::AST::Sequence, node
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
    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal nil, node.body
  end

  def test_def_with_semicolon
    node = parse "def foo;end"
    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal nil, node.body
  end

  def test_def_with_return_type
    node = parse "def foo:int\nend"
    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal "int", node.return_type
    assert_equal nil, node.body
  end

  def test_def_with_body
    node = parse "def foo\n1\n2\nend"
    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_body_with_semicolon
    node = parse "def foo;1;2;end"
    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_body_and_return_type
    node = parse "def foo:int\n1\n2\nend"
    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal "int", node.return_type

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_arg
    node = parse "def foo(a)\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"

    assert_equal nil, node.body
  end

  def test_def_with_arg_spacing
    node = parse "def foo( a)\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"

    assert_equal nil, node.body

    node = parse "def foo( a )\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"

    assert_equal nil, node.body
  end

  def test_def_with_arg_and_return_type
    node = parse "def foo(a):int\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal "int", node.return_type

    assert_ident node.arguments[0], "a"

    assert_equal nil, node.body
  end

  def test_def_with_arg_and_body
    node = parse "def foo(a)\n1\n2\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_arg_and_body_and_return_type
    node = parse "def foo(a):int\n1\n2\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name
    assert_equal "int", node.return_type

    assert_ident node.arguments[0], "a"

    assert_seq node.body, 2
    assert_number node.body[0], 1
    assert_number node.body[1], 2
  end

  def test_def_with_many_args
    node = parse "def foo(a,b)\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_ident node.arguments[0], "a"
    assert_ident node.arguments[1], "b"

    assert_equal nil, node.body
  end

  def test_def_with_many_args_spacing
    node = parse "def bar(c,\n\n        d)\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "bar", node.name

    assert_ident node.arguments[0], "c"
    assert_ident node.arguments[1], "d"

    assert_equal nil, node.body
  end

  def test_def_with_many_args_spaced
    node = parse "def foo(a, b)\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
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

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_typed_ident node.arguments[0], "a", "int"

    assert_equal nil, node.body
  end

  def test_def_with_many_typed_args
    node = parse "def foo(a:int,b:float)\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_typed_ident node.arguments[0], "a", "int"
    assert_typed_ident node.arguments[1], "b", "float"

    assert_equal nil, node.body
  end

  def test_def_with_template_args
    node = parse "def foo[a]\nend"
    assert_kind_of Talon::AST::MethodDefinition, node

    assert_kind_of Talon::AST::TemplatedName, node.name

    assert_equal "foo", node.name.name
    assert_equal 1, node.name.arguments.size
    assert_ident node.name.arguments[0], "a"
    assert_equal nil, node.body
  end

  def test_class
    node = parse "class foo\nend"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_equal "foo", node.name
  end

  def test_class_with_semicolor
    node = parse "class foo;end"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_equal "foo", node.name
  end

  def test_class_with_superclass
    node = parse "class foo < bar\nend"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_equal "foo", node.name
    assert_equal "bar", node.superclass_name
  end

  def test_class_with_body
    node = parse "class foo\ndef bar\nend\nend"
    assert_kind_of Talon::AST::ClassDefinition, node
    assert_equal "foo", node.name

    assert_kind_of Talon::AST::MethodDefinition, node.body
    assert_equal "bar", node.body.name
  end

  def test_class_with_body_with_semicolon
    node = parse "class foo;def bar\nend;end"
    assert_kind_of Talon::AST::ClassDefinition, node
    assert_equal "foo", node.name

    assert_kind_of Talon::AST::MethodDefinition, node.body
    assert_equal "bar", node.body.name
  end


  def test_class_with_superclass_and_body
    node = parse "class foo < bar\ndef bar\nend\nend"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_equal "foo", node.name
    assert_equal "bar", node.superclass_name

    assert_kind_of Talon::AST::MethodDefinition, node.body
    assert_equal "bar", node.body.name
  end

  def test_class_with_template_args
    node = parse "class foo[b]\nend"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_kind_of Talon::AST::TemplatedName, node.name

    assert_equal "foo", node.name.name
    assert_equal 1, node.name.arguments.size
    assert_ident node.name.arguments[0], "b"
  end

  def test_class_with_complex_template_args
    node = parse "class foo[b <: c, d !> e]\nend"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_kind_of Talon::AST::TemplatedName, node.name

    assert_equal "foo", node.name.name

    args = node.name.arguments

    assert_equal 2, args.size

    assert_kind_of Talon::AST::BinaryOperator, args[0]
    assert_equal "<:", args[0].operator
    assert_ident args[0].receiver, "b"
    assert_ident args[0].argument, "c"

    assert_kind_of Talon::AST::BinaryOperator, args[1]
    assert_equal "!>", args[1].operator
    assert_ident args[1].receiver, "d"
    assert_ident args[1].argument, "e"
  end

  def test_spacing
    assert_equal "1\n2", parse("1\n\n   \n2").to_code
  end


end
