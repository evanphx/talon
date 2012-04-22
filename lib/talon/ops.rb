module Talon
  module Op
    class SetIvar
      def initialize(ivar, val)
        @ivar = ivar
        @value = val
      end

      attr_reader :name, :value

      def name
        @ivar.name
      end

      def type
        @ivar.type
      end
    end

    class GetIvar
      def initialize(name)
        @name = name
      end

      attr_reader :name
    end

    class ConstantInt
      def initialize(val)
        @value = val
      end

      attr_reader :value

      def type(env)
        env.lookup "int"
      end
    end

    class AccessType
      def initialize(type)
        @type = type
      end

      attr_reader :type
    end

    class InvokeFunction
      def initialize(func, args)
        @function = func
        @arguments = args
      end

      def type(env)
        @function.return_type env
      end
    end

    class ArrayNew
      def return_type(env)

      end
    end

    class StaticString
      def initialize(value)
        @value = value
      end

      def type(env)
        env.lookup "String"
      end
    end
  end

  class AST::Assignment
    def render(meth)
      case @variable
      when AST::InstanceVariable
        ivar = meth.find_ivar @variable.name
        val = @value.render(meth)

        ivar.type_check(meth.env, val)

        Op::SetIvar.new @variable.name, @value.render(meth)
      else
        raise "nope"
      end
    end
  end

  class AST::Number
    def render(meth)
      case @value
      when Fixnum
        Op::ConstantInt.new @value
      else
        raise "nope"
      end
    end
  end

  class AST::BracketOperator
    def render(meth)
      obj = meth.env.lookup @receiver.name
      if obj.kind_of? TemplateType
        Op::AccessType.new obj.instance(@arguments)
      else
        raise "nope"
      end
    end
  end

  class AST::InstanceVariable
    def render(meth)
      Op::GetIvar.new @name
    end
  end

  class AST::MethodCall
    def render(meth)
      recv = @receiver.render(meth)
      op = recv.type.find_operation meth.env, @method_name
      args = @arguments.map { |a| a.render(meth) }

      Op::InvokeFunction.new op, [recv] + args
    end
  end

  class AST::String
    def render(meth)
      Op::StaticString.new @value
    end
  end
end
