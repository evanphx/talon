require 'rubygems'
require 'llvm/core'
require 'llvm/core/builder'

require 'llvm/transforms/scalar'

module Kernel
  remove_method :type
end

module Talon
  class GenVisitor
    Dispatch = {}

    AST::Types.each do |short, cls|
      Dispatch[cls] = short
    end

    def g(obj)
      unless short = Dispatch[obj.class]
        raise "Unsupported object - #{obj} (#{obj.class})"
      end

      __send__ "gen_#{short}", obj
    end

    alias_method :gen, :g
  end

  class Type
    def initialize(name, type=nil)
      @name = name
      @pointer = nil
      @type = type
    end

    def pointer
      @pointer ||= PointerType.new(self)
    end

    def llvm_type
      return @type if @type

      case @name
      when "Char"
        LLVM::Int8
      when "Integer"
        LLVM::Int32
      when "Boolean"
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
  end

  class PointerType < Type
    def initialize(inner)
      super nil
      @inner = inner
    end

    def llvm_type
      LLVM::Type.pointer @inner.llvm_type
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

      raise "unknown operation/method - #{name}"
    end

    def find_signature(name)
      @method_signatures[name]
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
        raise "unknown operatior - #{name}"
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
        raise "no"
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
        raise "no"
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
      else
        raise "Can't handle #{@name}"
      end
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
      when "<", ">"
        MathCompareOperation.new(name, self, @bool_type)
      else
        raise "unknown math op - #{name}"
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

  class Scope
    def initialize(parent=nil)
      @type = nil
      @parent = parent

      @bare = {}
      @ivars = {}
      @ivar_order = []
    end

    attr_accessor :type

    def [](e)
      v = @bare[e]
      return v if v

      @parent[e] if @parent
    end

    def []=(e,t)
      @bare[e] = t
    end

    def add_ivar(name, type)
      @ivars[name] = type
    end

    def ivar(name)
      @ivars[name]
    end

    def add_method(sig)
      @bare[sig.name] = sig.return_type

      if @type
        @type.method_signatures[sig.name] = sig
      end
    end
  end

  class Signature
    def initialize(name, args, ret)
      @name = name
      @arg_types = args
      @return_type = ret;
    end

    attr_reader :name, :arg_types, :return_type
  end

  class TypeCalculator < GenVisitor
    def initialize(top)
      @top = top

      bool = BooleanType.new("Boolean")
      @void = Type.new("Void", LLVM::Type.void)

      @registery = {
        'Char' => Type.new("Char"),
        'Integer' => IntegerType.new("Integer", LLVM::Int32, bool),
        'Void' => @void,
        'Boolean' => bool
      }

      @scope = Scope.new
      @types = {}
    end

    def new_scope
      s = Scope.new @scope

      begin
        old_scope, @scope = @scope, s
        yield s
      ensure
        @scope = old_scope
      end
    end

    def add(ast)
      @types[ast] = g(ast)
    end

    def add_specific(name, type)
      @registery[name] = type
    end

    def type_of(ast)
      @types[ast] || fail
    end

    def lookup(name)
      @registery[name]
    end

    def gen_seq(seq)
      t = nil

      seq.elements.each do |e|
        t = add(e)
      end

      t
    end

    def gen_method_dec(meth)
      @scope[meth.name] = add(meth.return_type)
      meth.arguments.each { |a| add(a) }
      @void
    end

    def gen_method_def(meth)
      arg_types = []

      if args = meth.arguments
        args.each do |a|
          t = @scope[a.name] = add(a)
          arg_types << t
        end
      end

      @scope.add_method Signature.new(meth.name, arg_types, 
                                      add(meth.return_type))

      add meth.body

      @void
    end

    def gen_typed_ident(ti)
      add ti.type
    end

    def gen_ivar(i)
      @scope.ivar(i.name)
    end

    def gen_pointer_type(pt)
      sub = add pt.inner
      sub.pointer
    end

    def gen_named_type(nt)
      case nt.identifier
      when "char"
        @registery['Char']
      when "int"
        @registery['Integer']
      when "string"
        @registery['String']
      when "void"
        @registery["Void"]
      else
        raise "unknown type - #{nt.identifier}"
      end
    end

    def gen_var(var)
      t = add var.expression
      @scope[var.identifier] = t
      @void
    end

    def gen_call(c)
      if args = c.arguments
        args.each { |a| add(a) }
      end

      if rec = c.receiver
        rt = add rec
        return rt.find_signature(c.method_name).return_type
      end

      if c.method_name == "reclaim"
        return @void
      end

      if t = @scope[c.method_name]
        return t
      end

      if t = @top.type_by_name(c.method_name)
        return t
      end

      raise "no - #{c.method_name}"
    end

    def gen_strlit(s)
      @registery['String']
    end

    def gen_binary(op)
      l = add op.receiver
      r = add op.argument

      o = l.find_operation op.operator
      o.calc_type r
    end

    def gen_ident(i)
      @scope[i.name]
    end

    def gen_number(n)
      @registery['Integer']
    end

    def gen_ret(n)
      add n.value
      @void
    end

    def gen_unary(op)
      if op.operator == "~"
        if op.receiver.kind_of? AST::MethodCall
          unless op.receiver.receiver
            return add(op.receiver)
          end
        end
      end

      raise "no"
    end

    def gen_if_node(i)
      add i.condition
      add i.then_body
      add i.else_body

      @void
    end

    def gen_class_def(cls)
      types = []

      cls_type = nil

      new_scope do |s|
        ivars = []

        cls.body.elements.each do |e|
          if e.kind_of? AST::IVarDeclaration
            t = add e.type_decl
            types << t.value_type

            ivars << [e.identifier, t]
            s.add_ivar e.identifier, t
          end
        end

        lltype = LLVM::Type.struct types, false, cls.name
        cls_type = ReferenceType.new(cls.name, lltype)

        ivars.each do |name, type|
          cls_type.add_ivar name, type
        end

        s.type = cls_type

        s[cls.name] = cls_type

        @registery[cls.name] = cls_type

        add cls.body
      end

      @scope[cls.name] = cls_type

      @void
    end

    def gen_ivar_decl(d)
      @void
    end

    def gen_assign(as)
      t = add as.value
      case as.variable
      when AST::InstanceVariable
        @scope.add_ivar as.variable.name, t
      else
        raise "Not supported assign - #{as.inspect}"
      end

      t
    end
  end

  class LLVMVisitor < GenVisitor
  end

  class LLVMFunctionVisitor < LLVMVisitor
    def initialize(top, func, meth, _self=nil)
      @top = top
      @func = func
      @meth = meth
      @self = _self

      @block = @func.basic_blocks.append("entry")
      @entry = @block

      @return_values = {}
      @return_blk = new_block "exit"

      @builder = LLVM::Builder.new
      @builder.position_at_end @block
      @scope = {}
      @locals = {}

      @alloca_point = @builder.alloca LLVM::Int32

      offset = 0

      if @self
        pr = @func.params[0]
        pr.name = "self.in"

        @self_value = pr

        offset = 1
      end

      if meth.arguments
        meth.arguments.each_with_index do |a,i|
          pr = @func.params[offset + i]
          pr.name = a.name

          lt = @top.value_type a
          @scope[a.name] = v = b.alloca(lt, a.name)

          b.store pr, v
        end
      end
    end

    def b
      @builder
    end

    def reachable?
      @builder.insert_block != nil
    end

    def unreachable!
      @builder.clear_insert_block
    end

    def new_block(name="bb")
      @func.basic_blocks.append name
    end

    def set_block(blk)
      @block = blk
      @builder.position_at_end blk
    end

    def add_alloca(lt, name="var")
      b.position @entry, @alloca_point
      e = b.alloca lt, name
      b.position_at_end @block
      e
    end

    def gen_unary(op)
      if op.operator == "~"
        if op.receiver.kind_of? AST::MethodCall
          mc = op.receiver
          if !mc.receiver
            return gen_call(mc, true)
          end
        end
      end

      raise "no"
    end

    def gen_call(call, alloca=false)
      if r = call.receiver
        t = @top.type_of(r)
        op = t.find_operation call.method_name

        op.run self, call
      else

        if call.method_name == "reclaim"
          args = call.arguments.map { |a| g(a) }

          ptr = args[0]

          b.call @top.free, b.bit_cast(ptr, @top.void_ptr)
          return nil
        end

        if target = @top.toplevel_function(call.method_name)
          arg_types = call.arguments.map { |a| @top.type_of(a) }

          args = target.arg_types.zip(call.arguments).map do |req,ast|
            is = @top.type_of(ast)
            val = g(ast)

            unless req == is
              val = is.convert_to?(self, val, req)

              unless val
                raise "Type mismatch - #{is} can't be a #{req}"
              end
            end

            val
          end

          b.call target.func, *args
        elsif t = @top.type_by_name(call.method_name)
          args = call.arguments.map { |a| g(a) }

          if alloca
            ptr = b.alloca t.alloca_type, "alloca.#{call.method_name}"
          else
            ptr = b.call @top.malloc, t.byte_size, "alloc.#{call.method_name}"
          end

          obj = b.bit_cast ptr, t.value_type
          if m = t.find_operation("initialize")
            m.invoke self, obj, *args
          end
          obj
        else
          raise "No call target found - #{call.method_name}"
        end
      end
    end

    def gen_strlit(sv)
      s = sv.value
      
      const = LLVM::ConstantArray.string s, true
      c_str = @top.mod.globals.add const.type, @top.name(".cstr")
      c_str.initializer = const
      c_str.linkage = :private
      c_str.global_constant = 1

      str = @top.mod.globals.add @top.string_type, @top.name("string")
      str.linkage = :internal
      siz = LLVM::ConstantInt32.from_i s.size
      dat = c_str.gep LLVM::ConstantInt32.from_i(0), LLVM::ConstantInt32.from_i(0)
      init = LLVM::ConstantStruct.const_named @top.string_type, [siz, dat]
      str.initializer = init
      str.alignment = 8

      str
    end

    def gen_if_node(i)
      c = g i.condition
      c = b.bit_cast c, LLVM::Int1, "to_cond"

      comp = b.icmp :ne, c, LLVM::Int1.from_i(0)

      then_block = new_block "then"
      else_block = new_block "else"
      cont = nil

      b.cond comp, then_block, else_block

      set_block then_block

      g i.then_body

      if reachable?
        cont = new_block "continue"
        b.br cont
      end

      set_block else_block

      g i.else_body

      if reachable?
        cont ||= new_block "continue"
        b.br cont
      end

      if cont
        set_block cont
      else
        unreachable!
      end

      nil
    end

    def gen_binary(i)
      case i.operator
      when "<"
        l = g i.receiver
        r = g i.argument

        b.icmp :slt, l, r
      else
        t = @top.type_of i.receiver
        if t and op = t.find_operation(i.operator)
          return op.run(self, i)
        end

        raise "Unsupported operator - #{i.operator}"
      end
    end

    def gen_ident(i)
      b.load @scope[i.name], "#{i.name}.loaded"
    end

    def gen_number(n)
      LLVM::Int(n.value)
    end

    def gen_ret(r)
      @return_values[@block] = g(r.value)
      b.br @return_blk

      unreachable!

      nil
    end

    def gen_and_return(top)
      val = gen top

      if reachable?
        @return_values[@block] = val if val
        b.br @return_blk
      end

      @return_blk.move_after @block

      set_block @return_blk

      v = LLVM::Type.void

      t =  @top.value_type @meth.return_type

      if t == v
        b.ret_void
      else
        v = b.phi t, @return_values, "return_value"
        b.ret v
      end

      b.dispose
    end

    def gen_seq(x)
      fin = nil

      x.elements.each do |e|
        fin = g e
        break unless reachable?
      end

      fin
    end

    def gen_var(v)
      t = @top.type_of(v.expression)
      r = add_alloca t.value_type, v.identifier

      @locals[v.identifier] = t
      @scope[v.identifier] = r

      e = g(v.expression)
      b.store e, r
      e
    end

    def self_gep(name)
      raise "No self" unless @self
      pos = @self.offset(name)

      b.gep @self_value, [LLVM::Int(0), LLVM::Int(pos)]
    end

    def gen_assign(as)
      val = g as.value
      case as.variable
      when AST::InstanceVariable
        pos = self_gep(as.variable.name)
        b.store val, pos
      else
        raise "Not supported assign - #{as.inspect}"
      end

      nil
    end

    def gen_ivar(i)
      b.load self_gep(i.name)
    end

  end

  class GetElement
    def initialize(type, pos, name="")
      @return_type = type
      @pos = pos
      @name = name
    end

    attr_reader :return_type

    def run(visit, node)
      raise "no arguments supported" if node.arguments

      val = visit.g(node.receiver)

      indices = [LLVM::Int(0), LLVM::Int(@pos)]

      visit.b.load visit.b.gep(val, indices, @name)
    end
  end

  class Method
    def initialize(func)
      @func = func
    end

    def run(visit, node)
      recv = visit.g(node.receiver)
      if args = node.arguments
        args = node.arguments.map { |a| g(a) }
      else
        args = []
      end

      visit.b.call @func, recv, *args
    end

    def invoke(visit, *args)
      visit.b.call @func, *args
    end
  end

  class LLVMClassVisitor < LLVMVisitor
    def initialize(top, ast)
      @top = top
      @ast = ast

      @talon_type = @top.type_by_name(ast.name)
      @type = @talon_type.llvm_type
    end

    attr_reader :type, :talon_type

    def name
      @ast.name
    end

    def gen_seq(seq)
      seq.elements.each do |e|
        g e
      end
    end

    def gen_ivar_decl(decl)
      # noop, handled up front
    end

    def method_name(method_name)
      "_Tc_#{name}_#{method_name}"
    end
    
    def gen_method_def(meth)
      if meth.arguments
        args = meth.arguments.map { |a| @top.value_type(a) }
      else
        args = []
      end

      args.unshift @type.pointer

      if rt = meth.return_type
        ret = @top.value_type rt
      else
        ret = LLVM::Type.void
      end

      func = @top.mod.functions.add method_name(meth.name), args, ret

      @talon_type.methods[meth.name] = Method.new func

      inner = LLVMFunctionVisitor.new @top, func, meth, self
      inner.gen_and_return meth.body
    end

    def offset(looking_for)
      @talon_type.ivar_offset looking_for
    end

    def ivar_type(looking_for)
      @talon_type.ivar looking_for
    end
  end

  class LLVMToplevelVisitor < LLVMVisitor
    def initialize
      @mod = LLVM::Module.new("talon")
      data_pointer = LLVM::Type.pointer(LLVM::Int8)
      elems = [LLVM::Int32, data_pointer]
      @string_type = LLVM::Type.struct elems, false, "talon.String"
      @functions = {}
      @uniq_names = 0

      @void_ptr = LLVM::Pointer(LLVM::Int8)
      @malloc = @mod.functions.add "malloc", [LLVM::Int64], @void_ptr
      @free = @mod.functions.add "free", [@void_ptr], LLVM::Type.void

      @typer = TypeCalculator.new self

      @talon_string_type = StringType.new "talon.String", @string_type, \
                           @typer.lookup("Char").pointer
      
      @typer.add_specific "String", @talon_string_type
    end

    attr_reader :malloc, :free, :void_ptr

    def name(prefix="tmp")
      "#{prefix}#{@uniq_names += 1}"
    end

    def toplevel_function(name)
      if n = @functions[name]
        return n
      end
    end

    def llvm_type(o)
      @typer.type_of(o).llvm_type
    end

    def value_type(o)
      @typer.type_of(o).value_type
    end

    def type_of(o)
      @typer.type_of(o)
    end

    def type_by_name(name)
      @typer.lookup name
    end

    attr_reader :mod, :string_type

    def gen_seq(seq)
      seq.elements.each do |e|
        g e
      end
    end

    class Function
      def initialize(func, arg_types, ret_type)
        @func = func
        @arg_types = arg_types
        @ret_type = ret_type
      end

      attr_reader :func, :arg_types, :ret_type
    end

    def gen_method_dec(dec)
      if attr = dec.attribute
        if attr.name == "Import"
          name = attr.values["name"]

          arg_types = dec.arguments.map { |a| type_of(a) }

          args = arg_types.map { |a| a.value_type }

          ret_type = type_of dec.return_type
          ret = ret_type.value_type

          func = @mod.functions.add name, args, ret
          @functions[name] = Function.new(func, arg_types, ret_type)
        end
      end
    end

    def gen_method_def(meth)
      if meth.arguments
        arg_types = meth.arguments.map { |a| type_of(a) }
      else
        arg_type = []
      end

      args = arg_types.map { |a| a.value_type }

      ret_type = type_of meth.return_type
      ret =  ret_type.value_type

      func = @mod.functions.add meth.name, args, ret
      @functions[meth.name] = Function.new(func, arg_types, ret_type)

      inner = LLVMFunctionVisitor.new self, func, meth
      inner.gen_and_return meth.body
    end

    def gen_class_def(cls)
      vis = LLVMClassVisitor.new self, cls
      @typer.add_specific vis.name, vis.talon_type
      vis.gen cls.body
    end

    def run(ast)
      @typer.add ast

      gen ast

      @mod.dump if ENV["TALON_DEBUG"]
      @mod.verify!
    end

  end
end
