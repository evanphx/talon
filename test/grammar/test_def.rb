require 'test/helper'

class TestDefGrammar < Talon::TestCase
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
    assert_type "int", node.return_type
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
    assert_type "int", node.return_type

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
    assert_type "int", node.return_type

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
    assert_type "int", node.return_type

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
    node = parse "def foo<a>\nend"
    assert_kind_of Talon::AST::MethodDefinition, node

    assert_kind_of Talon::AST::TemplatedName, node.name

    assert_equal "foo", node.name.name
    assert_equal 1, node.name.arguments.size
    assert_ident node.name.arguments[0], "a"
    assert_equal nil, node.body
  end

  def test_def_with_char_star
    node = parse "def foo(a:char*)\nend"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "foo", node.name

    assert_typed_ident node.arguments[0], "a", "char*"

    assert_equal nil, node.body
  end

  def test_simple_main
    node = parse "def main(argc:int, argv:char**)\nputs \"hello world\"\nend\n"

    assert_kind_of Talon::AST::MethodDefinition, node
    assert_equal "main", node.name

    assert_typed_ident node.arguments[0], "argc", "int"
    assert_typed_ident node.arguments[1], "argv", "char**"
  end

  def test_dec
    node = parse "dec foo(a:int) : int"

    assert_kind_of Talon::AST::MethodDeclaration, node
    assert_equal "foo", node.name

    assert_type "int", node.return_type
    assert_typed_ident node.arguments[0], "a", "int"
  end

  def test_dec_no_args
    node = parse "dec foo : int"

    assert_kind_of Talon::AST::MethodDeclaration, node
    assert_equal "foo", node.name

    assert_type "int", node.return_type
  end

  def test_dec_empty_parens
    node = parse "dec foo() : int"

    assert_kind_of Talon::AST::MethodDeclaration, node
    assert_equal "foo", node.name

    assert_type "int", node.return_type
  end

  def test_dec_with_attribute
    node = parse "%Import(name=\"atoi\")\ndec atoi(str:int) : int"

    assert_kind_of Talon::AST::MethodDeclaration, node
    assert_equal "atoi", node.name

    assert_type "int", node.return_type

    at = node.attribute
    assert_equal "Import", at.name
    assert_equal({ "name" => "atoi" }, at.values)
  end
end

