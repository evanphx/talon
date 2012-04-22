require 'test/helper'

class TestClassGrammar < Talon::TestCase
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
    node = parse "class foo : bar\nend"

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
    node = parse "class foo : bar\ndef bar\nend\nend"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_equal "foo", node.name
    assert_equal "bar", node.superclass_name

    assert_kind_of Talon::AST::MethodDefinition, node.body
    assert_equal "bar", node.body.name
  end

  def test_class_with_template_args
    node = parse "class foo<b>\nend"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_kind_of Talon::AST::TemplatedName, node.name

    assert_equal "foo", node.name.name
    assert_equal 1, node.name.arguments.size
    assert_ident node.name.arguments[0], "b"
  end

  def test_class_with_multiple_template_args
    node = parse "class foo<a,b>\nend"

    assert_kind_of Talon::AST::ClassDefinition, node
    assert_kind_of Talon::AST::TemplatedName, node.name

    assert_equal "foo", node.name.name

    args = node.name.arguments

    assert_equal 2, args.size

    assert_ident args[0], "a"
    assert_ident args[1], "b"
  end
end
