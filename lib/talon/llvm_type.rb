module Kernel
  remove_method :type
end

module Talon
  class Type
    def initialize(name, type=nil)
      @name = name
      @pointer = nil
      @type = type
    end

    attr_reader :name

    def pointer
      @pointer ||= PointerType.new(self)
    end

    def void?
      false
    end

    def llvm_type
      return @type if @type

      case @name
      when "talon.Char"
        LLVM::Int8
      when "talon.Integer"
        LLVM::Int32
      when "talon.Boolean"
        LLVM::Int1
      else
        raise "Unknown type - #{@name}"
      end
    end

    def value_type
      llvm_type
    end

    def byte_size
      llvm_type.size
    end

    def ==(other)
      return self == other.forward if other.kind_of? TypeVariable
      super
    end
  end

  class VoidType < Type
    def void?
      true
    end
  end

  class PointerType < Type
    def initialize(inner)
      super nil
      @inner = inner
    end

    def llvm_type
      LLVM::Type.pointer @inner.llvm_type
    end

    def name
      "#{@inner.name}*"
    end
  end

  class ReferenceType < Type
    def initialize(name, type=nil)
      super

      @methods = {}
      @method_signatures = {}

      @ivars = {}
      @ivar_order = []
    end

    attr_reader :methods, :method_signatures

    def add_ivar(name, type)
      @ivar_order << name
      @ivars[name] = type
    end

    def ivar(name)
      @ivars[name]
    end

    def ivar_offset(name)
      @ivar_order.index name
    end

    def value_type
      LLVM::Type.pointer llvm_type
    end

    def alloca_type
      llvm_type
    end

    def find_operation(name)
      if m = @methods[name]
        return m
      end
    end

    def find_signature(name)
      if sig = @method_signatures[name]
        return sig
      end

      nil
    end
  end

  class StringType < ReferenceType
    def initialize(name, llvm_type, data_type)
      super name, llvm_type

      @data_type = data_type
    end

    def find_operation(name)
      if name == "c_str"
        return GetElement.new(@data_type, 1, name)
      else
        raise "unknown operation - #{name}"
      end
    end

    def find_signature(name)
      if name == "c_str"
        return Signature.new("c_str", [], @data_type)
      else
        nil
      end
    end
  end

  class MathOperation
    def initialize(name, type)
      @name = name
      @type = type
    end

    def calc_type(other)
      unless @type == other
        raise TypeMismatchError,
              "no operation '#{@name}' between '#{@type.name}' and '#{other.name}'"
      end

      @type
    end

    def run(visit, op)
      l = visit.g op.receiver
      r = visit.g op.argument

      case @name
      when "+"
        visit.b.add l, r
      when "-"
        visit.b.sub l, r
      when "*"
        visit.b.mul l, r
      when "/"
        visit.b.sdiv l, r
      when "%"
        visit.b.srem l, r
      when "<<"
        visit.b.shl l, r
      when ">>"
        visit.b.ashr l, r
      else
        raise "Can't handle #{@name}"
      end
    end
  end

  class MathCompareOperation
    def initialize(name, type, bool_type)
      @name = name
      @type = type
      @bool_type = bool_type
    end

    def calc_type(other)
      unless @type == other
        raise TypeMismatchError,
              "no operation '#{@name}' between '#{@type.name}' and '#{other.name}'"
      end

      @bool_type
    end

    def run(visit, op)
      l = visit.g op.receiver
      r = visit.g op.argument

      case @name
      when "<"
        visit.b.icmp :slt, l, r
      when ">"
        visit.b.icmp :sgt, l, r
      when "=="
        visit.b.icmp :eq, l, r
      else
        raise "Can't handle #{@name}"
      end
    end
  end

  class TypeType < ReferenceType
    def initialize(name, llvm_type, name_type)
      super name, llvm_type
      @name_type = name_type
    end

    def find_operation(name)
      case name
      when "name"
        return GetElement.new(@name_type, 0, "name")
      else
        raise UnknownOperationError, "unknown operation '#{name}' on a type"
      end
    end

    def find_signature(name)
      if name == "name"
        return Signature.new("name", [], @name_type)
      else
        nil
      end
    end
  end

  class DynamicType < ReferenceType
    def initialize(name, llvm_type, tt)
      super name, llvm_type
      @tt = tt
    end

    def find_operation(name)
      case name
      when "type"
        return GetElement.new(@tt, 0, "type")
      else
        raise UnknownOperationError, "unknown dynamic operation '#{name}'"
      end
    end

    def find_signature(name)
      case name
      when "type"
        return Signature.new("type", [], @tt)
      end
    end

    def wrap(visit, val, o)
      rt = visit.runtime_type(o)

      st = visit.specific_dynamic(o)

      t = visit.b.alloca st, "alloca.dynamic"
      visit.b.store rt,  visit.b.gep(t, [LLVM::Int(0), LLVM::Int(0),
                                         LLVM::Int(0)])
      visit.b.store val, visit.b.gep(t, [LLVM::Int(0), LLVM::Int(1)])

      visit.b.bit_cast t, value_type
    end
  end

  class LambdaType < ReferenceType
    def initialize(name, arg_types, ret_type, cap_types)
      super name, nil

      if arg_types.size == 1 and arg_types[0].void?
        arg_types = []
      end

      @arg_types = arg_types
      @ret_type = ret_type
      @capture_types = cap_types
    end

    attr_reader :arg_types, :ret_type, :capture_types

    def find_operation(name)
      raise "no - #{name}"
      case name
      when "type"
        return GetElement.new(@tt, 0, "type")
      else
        raise UnknownOperationError, "unknown dynamic operation '#{name}'"
      end
    end

    def find_signature(name)
      raise "no - #{name}"
      case name
      when "type"
        return Signature.new("type", [], @tt)
      end
    end

    def convert_to?(visit, val, req)
      if req.kind_of?(LambdaType)
        if @arg_types == req.arg_types
          if @ret_type == req.ret_type or req.ret_type.void?
            visit.b.bit_cast val, req.value_type
          end
        end
      end
    end

    def unify(req)
      @arg_types.zip(req.arg_types) do |i,r|
        if i.kind_of? TypeVariable
          i.update r
        end
      end
    end

    def llvm_type
      @type ||= lower
    end

    def lower
      args = @arg_types
      ret = @ret_type
      captures = @capture_types

      args.each do |x|
        if x.kind_of? TypeVariable and x.unresolved?
          raise TypeMismatchError, "Unable to intuit lambda argument type from usage"
        end
      end

      largs = args.map { |x| x.value_type }

      arg_names = args.map { |x| x.name }.join(",")

      if captures.empty?
        n = "lambda<(#{arg_names} => #{ret.name})>"
      else
        cap_names = captures.map { |x| "*#{x.name}" }.join(",")
        n = "lambda<(#{arg_names} => #{ret.name}), #{cap_names}>"
      end

      @name = n

      lt = LLVM::Type.struct [], false, n

      largs.unshift LLVM::Type.pointer(lt)

      lret =  ret.value_type

      ft = LLVM::Type.function largs, lret

      elems = [LLVM::Type.pointer(ft)]

      elems += captures.map { |x| x.value_type }

      lt.element_types = elems

      lt
    end
  end

  class IntegerType < Type
    def initialize(name, llvm_type, bool_type)
      super name, llvm_type
      @bool_type = bool_type
    end

    def find_operation(name)
      case name
      when "+", "-", "*", "/", "%", "<<", ">>"
        MathOperation.new(name, self)
      when "<", ">", "=="
        MathCompareOperation.new(name, self, @bool_type)
      else
        raise UnknownOperationError,
              "unknown operator '#{name}' on a '#{self.name}'"
      end
    end
  end

  class BooleanType < Type
    def convert_to?(visit, val, o)
      if o.kind_of? IntegerType
        visit.b.zext val, o.value_type
      end
    end
  end

  class TypeVariable
    def initialize
      @forward = nil
    end

    attr_reader :forward

    def void?
      false
    end

    def unresolved?
      @forward == nil
    end

    def resolve
      raise "Using unresolved TypeVariable" unless @forward
      @forward
    end

    def ==(other)
      resolve == other
    end

    def update(o)
      @forward = o
    end

    def name
      resolve.name
    end

    def llvm_type
      resolve.llvm_type
    end

    def value_type
      resolve.value_type
    end

    def find_operation(op)
      resolve.find_operation(op)
    end
  end

  class DeriveType < TypeVariable
    def initialize(root, operator, right)
      @root = root
      @operator = operator
      @right = right
    end

    def resolve
      o = @root.resolve.find_operation @operator
      update o.calc_type(@right)
    end

    def find_operation(op)
      resolve.find_operation(op)
    end
  end
end
