require 'rubygems'
require 'kpeg'

module Talon; end

KPeg.load File.expand_path("../../../grammar.kpeg", __FILE__), "Talon::Parser"

require 'talon/code_gen'

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

      cg = Talon::CodeGen.new parser.ast

      c_temp = "#{@file}.c"

      File.open c_temp, "w" do |f|
        cg.output(f)
      end

      sh "gcc -o #{@output} #{c_temp}"
    end
  end
end
