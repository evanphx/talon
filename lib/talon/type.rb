module Talon
  class Type
    def initialize(name)
      @name = name
      @operations = {}
    end

    attr_reader :name

    def =~(other)
      equal? other
    end

    def pointer
      @pointer ||= Type.new("#{@name}*")
    end

    def find_operation(env, name)
      @operations[name]
    end

    def add_operation(name, op)
      @operations[name] = op
    end
  end

  class TemplateType < Type
    def initialize(name)
      super
      @instances = {}
    end

    def instance(args)
      @instances[args] ||= TemplateInstanceType.new(self, args)
    end
  end

  class TemplateInstanceType < Type
    def initialize(base, args)
      super nil

      @base = base
      @arguments = args
    end

    attr_reader :base, :arguments

    def find_operation(env, name)
      @base.find_operation(env, name)
    end
  end

  class TemplateArgumentType < Type
  end
end
