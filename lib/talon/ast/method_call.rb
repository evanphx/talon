module Talon
  module AST
    class MethodCall
      def to_code
        args = @arguments.map { |x| x.to_code }.join(", ")
        "#{@receiver.to_code}.#{@method_name}(#{args})"
      end
    end
  end
end
