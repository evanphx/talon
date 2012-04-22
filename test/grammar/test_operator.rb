require 'test/helper'

class TestOperatorGrammar < Talon::TestCase

  def test_assignment
    node = parse "a = 1"

    assert_kind_of Talon::AST::Assignment, node

    assert_ident node.variable, "a"
    assert_number node.value, 1
  end

  def test_assignment_is_lowest
    node = parse "a = 1 + 2"

    assert_kind_of Talon::AST::Assignment, node

    assert_ident node.variable, "a"

    arg = node.value

    assert_equal "+", arg.operator

    assert_number arg.receiver, 1
    assert_number arg.argument, 2
  end

  def test_assignment_is_right_assoc
    node = parse "a = b = 1 + 2"

    assert_kind_of Talon::AST::Assignment, node

    assert_ident node.variable, "a"

    arg = node.value
    assert_kind_of Talon::AST::Assignment, node

    assert_ident arg.receiver, "b"

    arg = arg.argument

    assert_equal "+", arg.operator

    assert_number arg.receiver, 1
    assert_number arg.argument, 2
  end

  def test_assigment_from_noparen
    node = parse "a = b.c d"

    expected = [:assign,
                 [:ident, "a"],
                 [:call,
                   [:ident, "b"],
                   "c",
                   [[:ident, "d"]]]]

    assert_equal expected, node.to_sexp
  end

  def test_assignment_to_ivar
    node = parse "@a = 1"

    expected = [:assign,
                 [:ivar, "a"],
                 [:number, 1]]

    assert_equal expected, node.to_sexp
  end

  def test_assignment_to_bracket
    node = parse "a[b] = c"

    expected = [:assign,
                 [:bracket,
                   [:ident, "a"],
                   [[:ident, "b"]]],
                 [:ident, "c"]]

    assert_equal expected, node.to_sexp
  end

  def test_assigment_to_attribute
    node = parse "a.b = c"

    expected = [:assign,
                 [:call,
                   [:ident, "a"],
                   "b",
                   nil],
                 [:ident, "c"]]

    assert_equal expected, node.to_sexp
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

  def test_binary_operator_spacing
    node = parse("1 +2")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1
    assert_number node.argument, 2

    node = parse("1 + 2")

    assert_kind_of Talon::AST::BinaryOperator, node
    assert_equal "+", node.operator

    assert_number node.receiver, 1
    assert_number node.argument, 2

    node = parse("1 +\n  2")

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

    o = StringIO.new
    node.to_code(o)

    assert_equal "(((a == b) && (c == d)) || (e == f))", o.string
  end

  def test_binary_operator_5
    node = parse "a = b && c == d || e == f"

    o = StringIO.new
    node.to_code(o)

    assert_equal "(a = ((b && (c == d)) || (e == f)))", o.string
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
    o = StringIO.new
    parse("a.b c + 1").to_code(o)

    assert_equal "a.b((c + 1))", o.string
  end

  def test_noparen_call_as_argument
    node = parse "e = a.b 1"

    expected = [:assign,
                 [:ident, "e"],
                 [:call,
                   [:ident, "a"],
                   "b",
                   [[:number, 1]]]]

    assert_equal expected, node.to_sexp
  end


end
