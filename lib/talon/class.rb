require 'talon/ivar'
require 'talon/method'

module Talon
  class Class
    def initialize(env, ast)
      @ast = ast

      @ivars = []

      @env = body_environment(env)

      @ast.body.elements.each do |e|
        case e
        when AST::IVarDeclaration
          ivar = Ivar.new(e.identifier, @env.resolve(e.type_decl))
          @ivars << ivar
          @env.add "@#{e.identifier}", ivar
        when AST::MethodDefinition
          @env.add e.name, Talon::Method.new(@env, e)
        end
      end
    end

    attr_reader :ivars

    def body_environment(env)
      Talon::Environment.new(env)
    end

    def find(name)
      @env.find(name)
    end
  end
end
