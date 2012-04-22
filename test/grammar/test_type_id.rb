require 'test/helper'

class TestGrammarTypeID < Talon::TestCase
  def test_lowercase_word
    node = parse "int", "type_id"

    assert_kind_of Talon::AST::NamedType, node

    assert_equal "int", node.identifier
  end

  def test_pointer
    node = parse "int*", "type_id"

    assert_kind_of Talon::AST::PointerType, node
    assert_type "int*", node
  end

  def test_pointer_pointer
    node = parse "int**", "type_id"

    assert_kind_of Talon::AST::PointerType, node
    assert_type "int**", node
  end

  def test_array
    node = parse "int[]", "type_id"

    assert_kind_of Talon::AST::ArrayType, node
    assert_type "int[]", node
  end

  def test_array_of_arrays
    node = parse "int[][]", "type_id"

    assert_kind_of Talon::AST::ArrayType, node
    assert_type "int[][]", node
  end

  def test_array_of_pointers
    node = parse "int*[]", "type_id"

    assert_kind_of Talon::AST::ArrayType, node
    assert_type "int*[]", node
  end

  def test_pointer_to_array
    node = parse "int[]*", "type_id"

    assert_kind_of Talon::AST::PointerType, node
    assert_type "int[]*", node
  end

  def test_scoped_type
    node = parse "a::int", "type_id"

    assert_kind_of Talon::AST::ScopedType, node
    assert_type "a", node.parent

    assert_kind_of Talon::AST::NamedType, node.child
    assert_type "int", node.child
  end

  def test_multiple_parents
    node = parse "a::b::int", "type_id"

    assert_kind_of Talon::AST::ScopedType, node
    assert_type "a", node.parent

    node = node.child

    assert_kind_of Talon::AST::ScopedType, node
    assert_type "b", node.parent

    assert_kind_of Talon::AST::NamedType, node.child
    assert_type "int", node.child
  end

  def test_templated_type
    node = parse "a<b>", "type_id"

    assert_kind_of Talon::AST::TemplatedType, node
    assert_kind_of Talon::AST::NamedType, node.base
    assert_type "a", node.base

    args = node.arguments

    assert_equal 1, args.size

    assert_kind_of Talon::AST::NamedType, args[0]
    assert_type "b", args[0]
  end

  def test_scoped_templated_type
    node = parse "n::a<b>", "type_id"

    assert_kind_of Talon::AST::ScopedType, node
    assert_type "n", node.parent

    node = node.child

    assert_kind_of Talon::AST::TemplatedType, node
    assert_kind_of Talon::AST::NamedType, node.base

    args = node.arguments

    assert_equal 1, args.size

    assert_kind_of Talon::AST::NamedType, args[0]
    assert_type "b", args[0]
  end

  def test_scoped_template_argument
    node = parse "a<n::b>", "type_id"

    assert_kind_of Talon::AST::TemplatedType, node
    assert_kind_of Talon::AST::NamedType, node.base

    args = node.arguments

    assert_equal 1, args.size

    assert_kind_of Talon::AST::ScopedType, args[0]
    assert_type "n", args[0].parent

    assert_kind_of Talon::AST::NamedType, args[0].child
    assert_type "b", args[0].child
  end

  def test_scoped_under_templated_type
    scoped = parse "a<b>::c", "type_id"

    node = scoped.parent

    assert_kind_of Talon::AST::TemplatedType, node
    assert_kind_of Talon::AST::NamedType, node.base

    args = node.arguments

    assert_equal 1, args.size

    assert_kind_of Talon::AST::NamedType, args[0]
    assert_type "b", args[0]

    node = scoped.child

    assert_kind_of Talon::AST::NamedType, node
    assert_type "c", node
  end

  def test_multiple_template_args
    node = parse "a<b,c>", "type_id"

    assert_kind_of Talon::AST::TemplatedType, node
    assert_type "a", node.base

    args = node.arguments

    assert_type "b", args[0]
    assert_type "c", args[1]
  end

  def test_constant_int_template_arg
    node = parse "a<1>", "type_id"

    assert_kind_of Talon::AST::TemplatedType, node
    assert_type "a", node.base

    args = node.arguments

    assert_kind_of Talon::AST::Number, args[0]
    assert_equal 1, args[0].value
  end

  def test_true_template_arg
    node = parse  "a<true>", "type_id"

    assert_kind_of Talon::AST::TemplatedType, node
    assert_type "a", node.base

    args = node.arguments

    assert_kind_of Talon::AST::True, args[0]
  end

  def test_false_template_arg
    node = parse  "a<false>", "type_id"

    assert_kind_of Talon::AST::TemplatedType, node
    assert_type "a", node.base

    args = node.arguments

    assert_kind_of Talon::AST::False, args[0]
  end

end
