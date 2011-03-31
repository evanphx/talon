module Falcon
  module AST
    class MethodCall
      def initialize(receiver, name, args)
        @receiver = receiver
        @method_name = name
        @arguments = args
      end

      attr_reader :receiver, :method_name, :arguments

      def to_code
        args = @arguments.map { |x| x.to_code }.join(", ")
        "#{@receiver.to_code}.#{@method_name}(#{args})"
      end
    end
  end
end
