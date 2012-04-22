module Talon
  module AST
    class Identifier
      def to_code(o)
        o << @name
      end
    end

    class Number
      def to_code(o)
        o << @value.to_s
      end
    end

    class MethodCall
      def to_code(o)
        if @receiver
          @receiver.to_code(o)
          o << ".#{@method_name}("
        else
          o << "#{@method_name}("
        end

        @arguments.each_with_index do |x,i|
          o << ", " unless i == 0
          x.to_code(o)
        end

        o << ")"
      end
    end

    class String
      def to_code(o)
        o << "\"#{@value}\""
      end
    end

    class BinaryOperator
      def to_code(o)
        o << "("
        @receiver.to_code(o)
        o << " #{@operator} "
        @argument.to_code(o)
        o << ")"
      end
    end

    class Assignment
      def to_code(o)
        o << "("
        @variable.to_code(o)
        o << " = "
        @value.to_code(o)
        o << ")"
      end
    end

    class Grouped
      def to_code(o)
        o << "("
        @expression.to_code(o)
        o << ")"
      end
    end

    class Sequence
      def to_code(o)
        @elements.each do |i|
          i.to_code(o)
          o << ";\n"
        end
      end
    end

    class MethodDeclaration
      def to_code(o)
        if @attribute
          if @attribute.name == "Import"
            name = @attribute.values["name"]

            args = @arguments.map { |a| "#{a.type} #{a.name}" }

            o << "extern #{@return_type} #{name}(#{args.join(', ')});\n"
          end
        end
      end
    end

    class MethodDefinition
      def to_code(o)
        args = @arguments.map { |a| "#{a.type} #{a.name}" }
        o << "#{@return_type || "void"} #{@name}(#{args.join ', '}) {\n"
        @body.to_code(o)
        o << "; }\n"
      end
    end
  end
end
