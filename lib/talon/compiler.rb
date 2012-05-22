require 'rubygems'
require 'kpeg'

module Talon; end

KPeg.load File.expand_path("../../../grammar.kpeg", __FILE__), "Talon::Parser"

require 'talon/code_gen'

require 'talon/llvm'
require 'llvm/execution_engine'

LLVM.init_x86

module Talon
  class Compiler
    def initialize(file, opts)
      @file = file
      @options = opts

      @output = opts[:output] || "#{File.basename(@file, '.tln')}.o"
    end

    def sh(cmd)
      puts cmd
      system cmd
    end

    def compile
      str = File.read @file
      parser = Talon::Parser.new str

      unless parser.parse
        parser.raise_error
      end

      lv = LLVMToplevelVisitor.new

      lv.run parser.ast

      base = File.basename @file, ".tln"

      lv.mod.write_bitcode "#{base}.bc"

      system "opt -std-compile-opts #{base}.bc | llc -o #{base}.s"
      system "clang -o #{base} #{base}.s"
    end
  end
end
