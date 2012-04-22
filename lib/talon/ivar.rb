module Talon
  class Ivar
    def initialize(name, type)
      @name = name
      @type = type
    end

    attr_reader :name, :type

    def type_check(env, val)
      vt = val.type(env)

      unless @type == vt
        raise TypeCheckError, "incompatibile types - #{@type.name} != #{vt.name}"
      end
    end
  end
end
