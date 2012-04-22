require 'test/helper'
require 'talon/code_gen'

class TestCodeGenImport < Talon::TestCase
  def test_emit_c_decl
    node = parse "%Import(name=\"atoi\")\ndec atoi(str:int) : int"

    cg = Talon::CodeGen.new node

    assert_equal "extern int atoi(int str);\n", cg.output.string
  end
end
