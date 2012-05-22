require 'rubygems'
require 'llvm/core'
require 'llvm/core/builder'

require 'llvm/transforms/scalar'

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
    def initialize(name)
      @name = name
      @pointer = nil
    end

    def pointer
      @pointer ||= PointerType.new(self)
    end

    def llvm_type
      case @name
      when "Char"
        LLVM::Int8
      when "Integer"
        LLVM::Int32
      end
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

  class TypeCalculator < GenVisitor
    def initialize
      @registery = {
        'Char' => Type.new("Char"),
        'Integer' => Type.new("Integer")
      }

      @funcs = {}
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
      else
        raise "unknown type - #{nt.identifier}"
      end
    end

    def gen_call(c)
      if t = @funcs[c.method_name]
        return t
      end

      raise "no"
    end
  end

  class LLVMVisitor < GenVisitor
  end

  class LLVMFunctionVisitor < LLVMVisitor
    def initialize(top, func, meth)
      @top = top
      @func = func
      @meth = meth

      @block = @func.basic_blocks.append("entry")
      @entry = @block

      @return_values = {}
      @return_blk = new_block "exit"

      @builder = LLVM::Builder.new
      @builder.position_at_end @block
      @scope = {}

      @alloca_point = @builder.alloca LLVM::Int32

      if meth.arguments
        meth.arguments.each_with_index do |a,i|
          pr = @func.params[i]
          pr.name = a.name

          lt = @top.llvm_type a
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

    def gen_call(call)
      if r = call.receiver
        t = @top.type_of(r)
        op = t.find_operation call.method_name

        op.run self, call
      else
        args = call.arguments.map { |a| g(a) }

        b.call @top.lookup(call.method_name), *args
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

      t =  @top.llvm_type @meth.return_type
      v = b.phi t, @return_values, "return_value"

      b.ret v

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
      lt = @top.llvm_type(v.expression)
      r = add_alloca lt, v.identifier

      @scope[v.identifier] = r

      e = g(v.expression)
      b.store e, r
      e
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

  class StringType
    def find_operation(name)
      if name == "c_str"
        return GetElement.new(1)
      else
        raise "unknown operation - #{name}"
      end
    end
  end

  class LLVMToplevelVisitor < LLVMVisitor
    def initialize
      @mod = LLVM::Module.new("talon")
      elems = [LLVM::Int32, LLVM::Type.pointer(LLVM::Int8)]
      @string_type = LLVM::Type.struct elems, false, "talon.String"
      @talon_string_type = StringType.new
      @functions = {}
      @uniq_names = 0

      @typer = TypeCalculator.new
    end

    def name(prefix="tmp")
      "#{prefix}#{@uniq_names += 1}"
    end

    def lookup(name)
      if n = @functions[name]
        return n
      else
        raise "unknown function - #{name}"
      end
    end

    def llvm_type(o)
      @typer.gen(o).llvm_type
    end

    def type_of(t)
      case t
      when AST::String
        @talon_string_type
      else
        p t
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

          args = dec.arguments.map { |a| llvm_type(a) }
          ret =  llvm_type dec.return_type

          func = @mod.functions.add name, args, ret
          @functions[name] = func
        end
      end
    end

    def gen_method_def(meth)
      if meth.arguments
        args = meth.arguments.map { |a| llvm_type(a) }
      else
        args = []
      end

      ret =  llvm_type meth.return_type

      func = @mod.functions.add meth.name, args, ret
      @functions[meth.name] = func

      @typer.add_func meth.name, meth.return_type

      inner = LLVMFunctionVisitor.new self, func, meth
      inner.gen_and_return meth.body

      # cleanup func
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

      # @mod.dump
      @mod.verify!
    end

  end
end
