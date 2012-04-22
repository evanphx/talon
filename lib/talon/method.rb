require 'talon/ops'

module Talon
  class Method
    def initialize(env, ast)
      @env = env
      @ast = ast
    end

    attr_reader :env

    def render
      body = @ast.body

      if body.kind_of? AST::Sequence
        body.elements.map { |e| e.render(self) }
      else
        [body.render(self)]
      end
    end

    def find_ivar(name)
      name = "@#{name}"
      i = @env.lookup name
      raise "unknown ivar: #{name}" unless i

      i
    end
  end
end

