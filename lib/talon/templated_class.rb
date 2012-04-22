require 'talon/class'

module Talon
  class TemplatedClass < Class
    def body_environment(env)
      e = Talon::Environment.new(env)
      @ast.name.arguments.each do |a|
        e.add a.name, TemplateArgumentType.new(a.name)
      end
      e
    end
  end
end
