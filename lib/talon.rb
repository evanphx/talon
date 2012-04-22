class Object
  if method_defined? :type
    undef_method :type
  end
end

require 'talon/code'

module Talon
  module AST
    class Sequence
      def [](idx)
        @elements[idx]
      end
    end

    class NamedType
      def ==(other)
        case other
        when String
          to_s == other
        when AST::NamedType
          to_s == other.to_s
        else
          super other
        end
      end

      def to_s
        @identifier
      end
    end

    class PointerType
      def to_s
        "#{@inner}*"
      end
    end

    class ArrayType
      def to_s
        "#{@inner}[]"
      end
    end
  end
end
