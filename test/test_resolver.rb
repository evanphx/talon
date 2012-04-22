require 'test/helper'
require 'talon/resolver'

class TestResolver < Talon::TestCase
  def test_local
    node = parse "a"

    t = Talon::Type.new("int")

    res = Talon::Resolver.new
    res.add_local "a", t

    res.resolve node

    target = node.target

    assert_kind_of Talon::LocalVariable, target
    assert_equal t, target.type
    assert_equal "a", target.name
  end

  def test_local_assignment
    node = parse "a = 1"

    res = Talon::Resolver.new

    res.resolve node

    lv = res.find "a"

    assert_kind_of Talon::LocalVariable, lv
    assert_equal res.find('talon.lang.Integer'), lv.type
    assert_equal "a", lv.name
  end
end
