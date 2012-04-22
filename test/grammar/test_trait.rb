require 'test/helper'

class TestTraitGrammar < Talon::TestCase
  def test_trait
    node = parse "trait bar\nend"

    assert_kind_of Talon::AST::TraitDefinition, node
    assert_equal "bar", node.name
  end

  def test_trait_with_def
    node = parse "trait bar\ndef foo\nend\nend"

    assert_kind_of Talon::AST::MethodDefinition, node.body
    assert_equal "foo", node.body.name
  end
end
