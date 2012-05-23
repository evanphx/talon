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
    end

    attr_reader :methods

    def value_type
      LLVM::Type.pointer llvm_type
    end

    def find_operation(name)
      if m = @methods[name]
        return m
      end

      raise "unknown operation/method - #{name}"
    end
  end

  class StringType < ReferenceType
    def find_operation(name)
      if name == "c_str"
        return GetElement.new(1)
      else
        raise "unknown operation - #{name}"
      end
    end
  end

  class TypeCalculator < GenVisitor
    def initialize(top)
      @top = top

      @registery = {
        'Char' => Type.new("Char"),
        'Integer' => Type.new("Integer"),
        'Void' => Type.new("Void", LLVM::Type.void)
      }

      @funcs = {}
    end

    def lookup(name)
      @registery[name]
    end

    def add(name, type_name, type=nil)
      @registery[name] = Type.new(type_name, type)
    end

    def add_specific(name, type)
      @registery[name] = type
    end

    def add_func(name, type)
      @funcs[name] = g type
    end

    def gen_typed_ident(ti)
      g ti.type
    end

    def gen_pointer_type(pt)
      sub = g pt.inner
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

    def gen_call(c)
      if t = @funcs[c.method_name]
        return t
      end

      if t = @top.find_type(c.method_name)
        return t
      end

      raise "no"
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

    def type_of(r)
      if r.kind_of? AST::InstanceVariable and @self
        return @self.ivar_type(r.name)
      elsif r.kind_of? AST::Identifier
        if v = @locals[r.name]
          return v
        end
      else
        @top.type_of(r)
      end
    end

    def gen_call(call)
      if r = call.receiver
        t = type_of(r)
        op = t.find_operation call.method_name

        op.run self, call
      else
        args = call.arguments.map { |a| g(a) }

        if target = @top.lookup(call.method_name)
          b.call @top.lookup(call.method_name), *args
        elsif t = @top.find_type(call.method_name)
          ptr = b.call @top.malloc, t.byte_size, "alloc.#{call.method_name}"
          obj = b.bit_cast ptr, t.value_type
          if m = t.find_operation("initialize")
            m.invoke self, obj, *args
          end
          obj
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
      when "+"
        l = g i.receiver
        r = g i.argument

        b.add l, r
      when "-"
        l = g i.receiver
        r = g i.argument

        b.sub l, r
      else
        raise "Unsupported operator - #{i.operator}"
      end
    end

    def gen_ident(i)
      b.load @scope[i.name]
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
      t = @top.find_type(v.expression)
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
    def initialize(pos, name="")
      @pos = pos
      @name = name
    end

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

      @ivars = []
      @methods = {}

      types = []

      @ast.body.elements.each do |e|
        if e.kind_of? AST::IVarDeclaration
          t = @top.find_type(e.type_decl)
          types << t.value_type
          @ivars << [e.identifier, t]
        end
      end

      @type = LLVM::Type.struct types, false, ast.name

      @talon_type = ReferenceType.new(name, type)
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

      func = @top.mod.functions.add meth.name, args, ret
      @methods[meth.name] = func

      @talon_type.methods[meth.name] = Method.new func

      # @top.typer.add_func meth.name, meth.return_type

      inner = LLVMFunctionVisitor.new @top, func, meth, self
      inner.gen_and_return meth.body

      # cleanup func
    end

    def offset(looking_for)
      o = 0
      @ivars.each do |name, type|
        return o if name == looking_for
        o += 1
      end

      raise "no ivar named #{looking_for}"
    end

    def ivar_type(looking_for)
      @ivars.each do |name, type|
        return type if looking_for == name
      end

      raise "no ivare named #{looking_for}"
    end
  end

  class LLVMToplevelVisitor < LLVMVisitor
    def initialize
      @mod = LLVM::Module.new("talon")
      elems = [LLVM::Int32, LLVM::Type.pointer(LLVM::Int8)]
      @string_type = LLVM::Type.struct elems, false, "talon.String"
      @talon_string_type = StringType.new "talon.String", @string_type
      @functions = {}
      @uniq_names = 0

      @malloc = @mod.functions.add "malloc", [LLVM::Int64], LLVM::Pointer(LLVM::Int8)
      @free = @mod.functions.add "free", [LLVM::Pointer(LLVM::Int8)], LLVM::Type.void

      @typer = TypeCalculator.new self

      @typer.add_specific "String", @talon_string_type
    end

    attr_reader :malloc

    def name(prefix="tmp")
      "#{prefix}#{@uniq_names += 1}"
    end

    def lookup(name)
      if n = @functions[name]
        return n
      end
    end

    def llvm_type(o)
      @typer.gen(o).llvm_type
    end

    def value_type(o)
      @typer.gen(o).value_type
    end

    def find_type(o)
      if o.kind_of? String
        @typer.lookup o
      else
        @typer.gen(o)
      end
    end

    def type_of(t)
      case t
      when AST::String
        @talon_string_type
      when AST::Identifier
        find_type t.name
      else
        raise "can't handle type - #{t.class}"
      end
    end

    attr_reader :mod, :string_type

    def gen_seq(seq)
      seq.elements.each do |e|
        g e
      end
    end

    def gen_method_dec(dec)
      if attr = dec.attribute
        if attr.name == "Import"
          name = attr.values["name"]

          args = dec.arguments.map { |a| value_type(a) }
          ret =  value_type dec.return_type

          func = @mod.functions.add name, args, ret
          @functions[name] = func
        end
      end
    end

    def gen_method_def(meth)
      if meth.arguments
        args = meth.arguments.map { |a| value_type(a) }
      else
        args = []
      end

      ret =  value_type meth.return_type

      func = @mod.functions.add meth.name, args, ret
      @functions[meth.name] = func

      @typer.add_func meth.name, meth.return_type

      inner = LLVMFunctionVisitor.new self, func, meth
      inner.gen_and_return meth.body

      # cleanup func
    end

    def gen_class_def(cls)
      vis = LLVMClassVisitor.new self, cls
      @typer.add_specific vis.name, vis.talon_type
      vis.gen cls.body
    end

    def cleanup(func)
     engine = LLVM::JITCompiler.new(@mod)
     passm  = LLVM::FunctionPassManager.new(engine, @mod)

     passm.simplifycfg!
     passm.instcombine!

     passm.run func
    end

    def run(ast)
      gen ast

      @mod.dump if ENV["TALON_DEBUG"]
      @mod.verify!
    end

  end
end
