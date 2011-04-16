module Talon
  module AST
    class Identifier
      def to_code
        @name
      end
    end

    class Number
      def to_code
        @value.to_s
      end
    end

    class MethodCall
      def to_code
        args = @arguments.map { |x| x.to_code }.join(", ")
        "#{@receiver.to_code}.#{@method_name}(#{args})"
      end
    end

    class BinaryOperator
      def to_code
        "(#{@receiver.to_code} #{@operator} #{@argument.to_code})"
      end
    end

    class Grouped
      def to_code
        "(#{@expression.to_code})"
      end
    end

    class Sequence
      def to_code
        @elements.map { |i| i.to_code }.join("\n")
      end
    end
  end
end
