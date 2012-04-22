require 'test/helper'

class TestGrammar < Talon::TestCase
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

  def test_ivar
    node = parse "@blah"
    assert_kind_of Talon::AST::InstanceVariable, node
    assert_equal "blah", node.name
  end

  def test_string
    node = parse("\"hello\"")
    assert_kind_of Talon::AST::String, node
    assert_equal "hello", node.value
  end

  def test_func_call_with_args
    node = parse "foo(2,3)"

    assert_call node, "foo"
    assert_equal nil, node.receiver
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
  def test_if_with_else
    node = parse "if 1\nyes\nelse\nno\nend"
    assert_kind_of Talon::AST::If, node

    cond = node.condition
    tb = node.then_body
    eb = node.else_body

    assert_number cond, 1
    assert_ident tb, "yes"
    assert_ident eb, "no"
  end

  def test_if_with_else_semicolon
    node = parse "if 1;yes;else;no;end"
    assert_kind_of Talon::AST::If, node

    cond = node.condition
    tb = node.then_body
    eb = node.else_body

    assert_number cond, 1
    assert_ident tb, "yes"
    assert_ident eb, "no"
  end

  def test_if_without_else
    node = parse "if 1\nyes\nend"
    assert_kind_of Talon::AST::If, node

    cond = node.condition
    tb = node.then_body

    assert_number cond, 1
    assert_ident tb, "yes"
    assert_equal nil, node.else_body
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
    tb = node.then_body

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

  def test_spacing
    o = StringIO.new
    parse("1\n\n   \n2").to_code(o)

    assert_equal "1;\n2;\n", o.string
  end

  def test_comment
    node = parse("1\n-- this is a one line comment\n2")

    assert_seq node, 3
    assert_number node.elements[0], 1
    com = node.elements[1]
    assert_kind_of Talon::AST::Comment, com
    assert_equal " this is a one line comment", com.text
    assert_number node.elements[2], 2
  end

  def test_var_decl
    node = parse "var a = 1"

    assert_kind_of Talon::AST::VariableCreation, node
    assert_equal "a", node.identifier
    assert_equal nil, node.type_decl
    assert_number node.expression, 1
  end

  def test_var_decl_with_type
    node = parse "var a : int = 1"

    assert_kind_of Talon::AST::VariableCreation, node
    assert_equal "a", node.identifier
    assert_type "int", node.type_decl
    assert_number node.expression, 1
  end

  def test_var_decl_with_pointer
    node = parse "var a : int*"

    assert_kind_of Talon::AST::VariableDeclaration, node
    assert_equal "a", node.identifier
    assert_type "int*", node.type_decl
  end

  def test_var_decl_with_brackets
    node = parse "var a : int[]"

    assert_kind_of Talon::AST::VariableDeclaration, node
    assert_equal "a", node.identifier
    assert_type "int[]", node.type_decl
  end

  def test_ivar_decl
    node = parse "var @a : int"

    assert_kind_of Talon::AST::IVarDeclaration, node
    assert_equal "a", node.identifier
    assert_type "int", node.type_decl
  end

  def test_indent
    node = parse "  blah"
    assert_kind_of Talon::AST::Identifier, node
    assert_equal "blah", node.name
  end
end
