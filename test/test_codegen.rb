require 'test/helper'
require 'talon/code_gen'

class TestCodeGenImport < Talon::TestCase
  def test_emit_c_decl
    node = parse "%Import(name=\"atoi\")\ndec atoi(str:int) : int"

    cg = Talon::CodeGen.new node

    assert_equal "extern int atoi(int str);\n", cg.output.string
  end

  def test_hello_world
    node = parse <<-CODE
%Import(name="puts")
dec puts(str:char*) : void

def main(argc:int, argv:char**)
  puts "hello world"
end
    CODE
  end
end
