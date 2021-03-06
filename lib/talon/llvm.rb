require 'rubygems'
require 'llvm/core'
require 'llvm/core/builder'

require 'llvm/transforms/scalar'

require 'talon/llvm_type'

module Talon
  class CompileError < RuntimeError
  end

  class TypeMismatchError < CompileError
  end

  class MissingArgumentsError < CompileError
  end

  class UnitializedError < CompileError
  end

  class UnknownOperationError < CompileError
  end

  class BadCallError < CompileError
  end

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

  class Scope
    def initialize(parent=nil)
      @name = nil
      @type = nil
      @parent = parent

      @bare = {}
      @ivars = {}
      @ivar_order = []

      @traits = {}
      @templates = {}
    end

    attr_accessor :type, :traits, :templates, :name

    def find_trait(name)
      if t = @traits[name]
        return t
      end

      @parent.find_trait(name) if @parent
    end

    def find_template(name)
      if t = @templates[name]
        return t
      end

      @parent.find_template(name) if @parent
    end

    def [](e)
      v = @bare[e]
      return v if v

      @parent[e] if @parent
    end

    def []=(e,t)
      @bare[e] = t
    end

    def add_ivar(name, type)
      @bare["@#{name}"] = type
    end

    def ivar(name)
      self["@#{name}"]
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
      @return_type = ret
    end

    attr_reader :name, :arg_types, :return_type
  end

  class Template
    def initialize(ast)
      @ast = ast
      @instances = []
    end

    attr_reader :ast, :instances

    def name
      @ast.name
    end

    def arguments
      @ast.name.arguments
    end

    def body
      @ast.body
    end

    def find_expanded(type_args)
      @instances.detect { |et| et.concrete == type_args }
    end
  end

  class AbstractDataCase
    def initialize(ast, root)
      @ast = ast
      @root = root
    end

    def expand(name, type_args)
      concrete = @root.find_expanded(type_args)

      unless concrete
        raise "No expanded type for '#{name}'"
      end

      concrete.type.cases.find { |c| c.name == name }
    end
  end

  class TypeCalculator < GenVisitor
    def initialize(context, global)
      @ctx = context

      @global = global

      @scope = Scope.new global
      @types = {}
    end

    attr_reader :scope

    def self.global_scope(ctx)
      s = Scope.new

      bool = BooleanType.new("talon.Boolean")
      void = VoidType.new("talon.Void", LLVM::Type.void)
      int = IntegerType.new("talon.Integer", LLVM::Int32, bool)
      char = Type.new("talon.Char")
      string = StringType.new "talon.String", ctx.string_type, char.pointer

      tt  = TypeType.new("talon.Type", ctx.type_type, string)
      dyn = DynamicType.new("talon.Dynamic", ctx.dynamic_type, tt)

      s['Char'] = char
      s['Integer'] = int
      s['int'] = int
      s['Void'] = void
      s['Boolean'] = bool
      s['String'] = string
      s['dynamic'] = dyn

      s
    end

    def new_scope
      s = Scope.new @scope

      begin
        old_scope = @scope
        @scope = s

        yield s
      ensure
        @scope = old_scope
      end
    end

    def add(ast)
      @types[ast] = g(ast)
    end

    def add_type(ast, type)
      @types[ast] = type
    end

    def add_specific(name, type)
      @scope[name] = type
    end

    def type_of(ast)
      @types[ast] || raise("No type for a #{ast.class.name}")
    end

    def lookup(name)
      @scope[name]
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

      outer = @scope

      new_scope do |s|
        if args = meth.arguments
          args.each do |a|
            t = s[a.name] = add(a)
            arg_types << t
          end
        end

        outer.add_method Signature.new(meth.name, arg_types, 
                                      add(meth.return_type))

        add meth.body
      end

      @void
    end

    def gen_varargs(v)
      @void
    end

    def gen_typed_ident(ti)
      add ti.type
    end

    def expand_data_template(template, args)
      t = args.first

      # Copy so the type entries for the AST are unique
      ast = Marshal.load Marshal.dump(template.ast)

      name = @ctx.expanded_template_name(template.name, t)

      types = []

      dt = nil
      outer = @scope

      new_scope do |s|
        s[template.arguments.first.name] = t

        elems = [LLVM::Int32]
        lltype = LLVM::Type.struct elems, false, name

        dt = DataType.new(name, lltype)

        outer[name] = dt

        template.instances << ExpandedTemplate.new(template, dt, [t])

        s[name] = dt

        ast.cases.each do |c|
          body = [lltype]
          lt = LLVM::Type.struct [], false, c.name

          t = add_type c.name, dt.add_case(c.name, lt)
          s[c.name] = t

          if c.args
            i = 1

            c.args.each do |a|
              st = add(a)
              t.add_arg a.name, st, i
              body << st.value_type
              i += 1
            end
          end

          lt.element_types = body
        end
      end

      dt
    end


    def gen_templated_type(tt)
      t = @scope[tt.base.identifier]
      unless t.kind_of? Template
        raise "Attempted to expand non-template '#{tt.base.identifier}'"
      end

      type_args = tt.arguments.map { |x| add x }

      et = t.find_expanded(type_args)

      return et.type if et

      expand_data_template t, type_args
    end

    def templated_data(d)
      t = Template.new(d)
      @scope[d.name.name] = t

      d.cases.each do |c|
        adc = AbstractDataCase.new(c, t)
        @scope[c.name] = adc
      end

      @void
    end

    def gen_data(d)
      if d.name.kind_of? AST::TemplatedName
        return templated_data(d)
      end

      elems = [LLVM::Int32]
      lltype = LLVM::Type.struct elems, false, d.name

      dt = DataType.new(d.name, lltype)

      @scope[d.name] = dt

      d.cases.each do |c|
        body = [lltype]
        lt = LLVM::Type.struct [], false, c.name

        t = add_type c.name, dt.add_case(c.name, lt)
        @scope[c.name] = t

        if c.args
          i = 1

          c.args.each do |a|
            st = add(a)
            t.add_arg a.name, st, i
            body << st.value_type
            i += 1
          end
        end

        lt.element_types = body
      end

      dt
    end

    def gen_lambda_type(lt)
      args = lt.arg_types.map { |x| add(x) }
      ret  = add lt.ret_type

      @ctx.lambda_type(args, ret)
    end

    def gen_lambda_stmts(ls)
      ls.body.each { |x| add x }

      @scope['$return'] || @scope['Void']
    end

    def gen_lambda(l)
      if l.args
        args = l.args.map { |x|
                 case x
                 when AST::Identifier
                   add_type x, TypeVariable.new
                 else
                   add x
                 end
               }
      else
        args = [@scope['Void']]
      end

      ret  =  nil

      outer = @scope
      new_scope do |s|
        if l.args
          l.args.zip(args).each { |n,t| s[n.name] = t }
        end

        if l.captures
          l.captures.each do |c|
            s[c] = @scope[c]
          end
        end

        ret = add l.body
      end

      if l.captures
        types = l.captures.map { |x| @scope[x] }
        @ctx.specific_lambda_type args, ret, types
      else
        @ctx.lambda_type args, ret
      end
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
        @scope['Char']
      when "int"
        @scope['Integer']
      when "string"
        @scope['String']
      when "void"
        @scope["Void"]
      else
        if t = @scope[nt.identifier]
          return t
        end

        raise "unknown type - #{nt.identifier}"
      end
    end

    def gen_var(var)
      t = add var.expression
      if t.void?
        raise TypeMismatchError, "Attempted to use void as a value"
      end

      @scope[var.identifier] = t
      @void
    end

    def gen_named_arg(na)
      add na.expr
    end

    def gen_call(c)
      if args = c.arguments
        args.each { |a| add(a) }
      end

      if c.receiver.kind_of? AST::Identifier
        name = c.receiver.name
        s = @scope[name]
        if s.kind_of? LLVMToplevelVisitor
          obj = s.scope[c.method_name]
          return obj if obj.kind_of? Type
        end
      end

      if rec = c.receiver
        rt = add rec
        if sig = rt.find_signature(c.method_name)
          return sig.return_type
        else
          raise TypeMismatchError,
                "unable to find method '#{c.method_name}' on a '#{rt.name}'"
        end
      end

      if c.method_name == "reclaim"
        return @void
      end

      if t = @scope[c.method_name]
        if t.kind_of? LambdaType
          return t.ret_type
        end

        return t
      end

      if t = lookup(c.method_name)
        return t
      end

      raise TypeMismatchError, "unable to find a function '#{c.method_name}'"
    end

    class ExpandedTemplate
      def initialize(ast, type, concrete)
        @ast = ast
        @type = type
        @concrete = concrete
      end

      attr_reader :ast, :type, :concrete
    end

    def expand_template(template, concrete)
      if concrete == "int"
        t = @scope['Integer']
      else
        raise "unknown concrete type - #{concrete}"
      end

      # Copy so the type entries for the AST are unique
      ast = Marshal.load Marshal.dump(template.ast)

      name = @ctx.expanded_template_name(template.name, t)

      types = []

      cls_type = nil

      new_scope do |s|
        s[template.arguments.first.name] = t

        ivars = []

        template.body.elements.each do |e|
          if e.kind_of? AST::IVarDeclaration
            t = add e.type_decl
            types << t.value_type

            ivars << [e.identifier, t]
            s.add_ivar e.identifier, t
          end
        end

        lltype = LLVM::Type.struct types, false, name
        cls_type = ReferenceType.new(name, lltype)

        ivars.each do |i_name, type|
          cls_type.add_ivar i_name, type
        end

        s.type = cls_type

        s[name] = cls_type

        add template.body
      end

      @scope[name] = cls_type

      template.instances << ExpandedTemplate.new(template, cls_type, [t])

      cls_type
    end

    def gen_templated_instance(t)
      if args = t.arguments
        args.map { |a| add(a) }
      end

      obj = @scope[t.name]
      case obj
      when Template
        return expand_template(obj, t.type)
      when AbstractDataCase
        unless t.type == "int"
          raise "FIXME: ADC type not int"
        end

        type_args = [@scope["int"]]
        return obj.expand t.name, type_args
      else
        raise "Attempted to expand non-template '#{t.name}'"
      end

      raise "couldn't find a template to expand - #{t.name}"
    end

    def gen_strlit(s)
      @scope['String']
    end

    def gen_binary(op)
      l = add op.receiver
      r = add op.argument

      if l.kind_of? TypeVariable
        DeriveType.new l, op.operator, r
      else
        o = l.find_operation op.operator
        o.calc_type r
      end
    end

    def gen_ident(i)
      v = @scope[i.name]
      unless v
        raise UnitializedError, "nothing named '#{i.name}' found in scope"
      end

      v
    end

    def gen_number(n)
      @scope['Integer']
    end

    def gen_ret(n)
      t = add n.value

      @scope['$return'] = t

      @void
    end

    def gen_unary(op)
      if op.operator == "~"
        case op.receiver
        when AST::MethodCall
          unless op.receiver.receiver
            return add(op.receiver)
          end
        when AST::TemplatedInstance
          return add(op.receiver)
        end
      end

      raise "Unsupported unary op - #{op.operator}"
    end

    def gen_if_node(i)
      add i.condition
      add i.then_body

      if i.else_body
        add i.else_body
      end

      @void
    end

    def gen_while_node(i)
      add i.condition
      add i.body

      @void
    end

    def gen_case_node(i)
      t = add i.condition

      i.whens.each do |w|
        when_node w, i, t
      end

      @void
    end

    def when_node(i, c, ct)
      if ct.kind_of? DataType
        case_name = i.var.type.identifier

        st = ct.cases.detect { |t| t.name == case_name }
        unless st
          raise TypeMismatchError,
                "No subtype of '#{ct.name}' named '#{case_name}'"
        end

        @scope[i.var.name] = st
        add_type i.var, st
      else
        @scope[i.var.name] = add(i.var)
      end

      add i.body
      @void
    end

    def gen_trait_def(trait)
      add trait.body

      @scope.traits[trait.name] = trait
      @void
    end

    def gen_inc(inc)
      t = @scope.find_trait(inc.name)

      add t

      @void
    end

    def handle_class_template_def(cls)
      @scope[cls.name.name] = Template.new(cls)
      @void
    end

    def gen_class_def(cls)
      if cls.name.kind_of? AST::TemplatedName
        return handle_class_template_def(cls)
      end

      types = []

      cls_type = nil

      if pkg = @scope.name
        cls_name = "#{pkg}.#{cls.name}"
      else
        cls_name = cls.name
      end

      new_scope do |s|
        ivars = []

        elements = (AST::Sequence === cls.body ? 
                     cls.body.elements : 
                     [cls.body])

        elements.each do |e|
          if e.kind_of? AST::IVarDeclaration
            t = add e.type_decl
            types << t.value_type

            ivars << [e.identifier, t]
            s.add_ivar e.identifier, t
          end
        end

        lltype = LLVM::Type.struct types, false, cls_name
        cls_type = ReferenceType.new(cls_name, lltype)

        ivars.each do |name, type|
          cls_type.add_ivar name, type
        end

        s.type = cls_type

        s[cls.name] = cls_type

        @scope[cls.name] = cls_type

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
      when AST::Identifier
        cur = @scope[as.variable.name]
        if cur != t
          raise TypeMismatchError,
                "Unable to assign a '#{t.name}' to a declared '#{cur.name}'"
        end

        t
      else
        raise "Not supported assign - #{as.inspect}"
      end

      t
    end

    def import(path)
      str = File.read path
      parser = Talon::Parser.new str

      unless parser.parse
        parser.raise_error
      end

      lv = LLVMToplevelVisitor.new @ctx, @global

      lv.run parser.ast

      lv
    end

    def gen_import(imp)
      @ctx.import_paths.each do |root|
        path = File.join(root, *imp.segements) + ".tln"
        if File.file? path
          lv = import path

          name = imp.segements.first

          @scope[name] = lv
          # @top.imports[name] = lv

          return @void
        end
      end

      raise "Unable to find #{imp.segements.join('.')} to import"
    end

    def gen_package(pkg)
      @scope.name = pkg.segments.join(".")
      @void
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

      if meth.kind_of? AST::Lambda
        lself = @func.params[0]
        lself.name = "lambda"

        if meth.args
          i = 1

          meth.args.each do |x|
            pr = @func.params[i]
            pr.name = x.name

            lt = @top.value_type x
            @locals[x.name] = @top.type_of(x)
            @scope[x.name] = v = b.alloca(lt, x.name)

            b.store pr, v
            i += 1
          end
        end

        if meth.captures
          cap_types = @top.type_of(meth).capture_types

          i = 1
          meth.captures.zip(cap_types).each do |n,t|
            @locals[n] = t
            @scope[n] = b.gep(lself, [LLVM::Int(0), LLVM::Int(i)])
            i += 1
          end
        end

        return
      end

      if meth.arguments
        meth.arguments.each_with_index do |a,i|
          pr = @func.params[offset + i]
          pr.name = a.name

          lt = @top.value_type a
          @locals[a.name] = @top.type_of(a)
          @scope[a.name] = v = b.alloca(lt, a.name)

          b.store pr, v
        end
      end
    end

    def runtime_type(t)
      @top.runtime_type(t)
    end

    def specific_dynamic(t)
      @top.context.specific_dynamic t
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
        case op.receiver
        when AST::MethodCall
          mc = op.receiver
          if !mc.receiver
            return gen_call(mc, true)
          end
        when AST::TemplatedInstance
          return gen_templated_instance(op.receiver, true)
        end
      end

      raise "no"
    end

    def convert_args(target, call, method_name=call.method_name)
      args = call.arguments || []
      arg_types = args.map { |a| @top.type_of(a) }

      arg_num = 1

      need = target.arg_types.size
      got  = args.size

      if target.respond_to?(:varargs) and target.varargs
        if need > got
          raise MissingArgumentsError, "missing arguments to '#{method_name}' (needed #{need}, got #{got})"
        end
      else
        if need != got
          raise MissingArgumentsError, "missing arguments to '#{method_name}' (needed #{need}, got #{got})"
        end
      end

      # reorder args based on any named args
    
      positional = []

      seen_named = false

      args.each do |x|
        case x
        when AST::NamedArgument
          seen_named = true

          index = target.arguments.index(x.name)

          unless index
            raise MissingArgumentsError,
                  "Unknown argument '#{x.name}' for '#{method_name}'"
          end

          positional[index] = x.expr
        else
          if seen_named
            raise BadCallError,
                  "Unable to use positional arguments after named arguments"
          end

          positional << x
        end
      end

      args = positional

      args.zip(target.arg_types).map do |ast,req|
        is = @top.type_of(ast)

        if req.kind_of?(LambdaType) and is.kind_of?(LambdaType)
          is.unify(req)
        end

        val = g(ast)

        if req and req != is
          if req.kind_of? DynamicType
            val = req.wrap(self, val, is)
          elsif !is.respond_to? :convert_to?
            raise TypeMismatchError, "unable to pass a '#{is.name}' as a '#{req.name}' for argument #{arg_num} of '#{method_name}'"
          else
            val = is.convert_to?(self, val, req)
          end

          unless val
            raise TypeMismatchError, "unable to pass a '#{is.name}' as a '#{req.name}' for argument #{arg_num} of '#{method_name}'"
          end
        end

        arg_num += 1

        val
      end
    end

    def instantiate_type(call, t, alloca=false)
      if t.kind_of? SpecificDataType
        if s = t.singleton
          return s
        end
      end

      if alloca
        ptr = b.alloca t.alloca_type, "alloca.#{call.method_name}"
      else
        ptr = b.call @top.context.malloc, t.byte_size,
                     "alloc.#{call.method_name}"
      end

      obj = b.bit_cast ptr, t.value_type

      if m = t.find_operation("initialize")
        args = convert_args m, call, "#{t.name}#initialize"

        m.invoke self, obj, *args
      elsif t.kind_of? SpecificDataType
        b.store LLVM::Int(t.code),
                b.gep(obj, [LLVM::Int(0), LLVM::Int(0), LLVM::Int(0)])

        args = convert_args t, call, "#{t.name}#initialize"

        i = 1
        args.each do |a|
          b.store a, b.gep(obj, [LLVM::Int(0), LLVM::Int(i)])
          i += 1
        end
      end

      obj
    end

    def invoke_lambda(lam, call, lt)
      args = convert_args lt, call, "lambda"

      func = b.load b.gep(lam, [LLVM::Int(0), LLVM::Int(0)])

      b.call func, lam, *args
    end

    def gen_call(call, alloca=false)
      if r = call.receiver
        if r.kind_of? AST::Identifier
          s = @top.scope[r.name]
          if s.kind_of? LLVMToplevelVisitor
            obj = s.functions[call.method_name]

            if obj
              args = convert_args obj, call, "#{r.name}.#{call.method_name}"
              return b.call(obj.func, *args)
            end

            t = s.scope[call.method_name]

            if t.kind_of? Type
              return instantiate_type(call, t, alloca)
            end

            raise "Unable to resolve idenifier in package - #{call.method_name}"
          end
        end

        t = @top.type_of(r)
        op = t.find_operation call.method_name

        unless op
          raise "Unknow operation '#{call.method_name}' on '#{t.name}'"
        end

        op.run self, call
      else
        if t = @locals[call.method_name]
          if t.kind_of? LambdaType
            lam = b.load @scope[call.method_name]
            return invoke_lambda(lam, call, t)
          end
        end

        if call.method_name == "reclaim"
          args = call.arguments.map { |a| g(a) }

          ptr = args[0]

          b.call @top.context.free, b.bit_cast(ptr, @top.context.void_ptr)
          return nil
        end

        if target = @top.toplevel_function(call.method_name)
          args = convert_args target, call

          b.call target.func, *args
        else 
          t = @top.type_by_name(call.method_name)
          if t and t.kind_of? ReferenceType
            return instantiate_type(call, t, alloca)
          end
          raise "No call target found - #{call.method_name}"
        end
      end
    end

    def gen_lambda_stmts(ls)
      ls.body.each { |x| g x }

      nil
    end

    def gen_lambda(lam)
      t = @top.type_of(lam)

      largs = [t.value_type] + t.arg_types.map { |x| x.value_type }
      lret =  t.ret_type.value_type

      func = @top.mod.functions.add "lambda", largs, lret

      sub = LLVMFunctionVisitor.new @top, func, lam
      sub.gen_and_return lam.body

      r = add_alloca t.alloca_type, "lambda"
      b.store func, b.gep(r, [LLVM::Int(0), LLVM::Int(0)])

      if lam.captures

        i = 1
        lam.captures.each do |c|
          b.store b.load(@scope[c]), \
                  b.gep(r, [LLVM::Int(0), LLVM::Int(i)])

          i += 1
        end
      end

      r
    end

    def gen_templated_instance(ti, alloca=false)
      if t = @top.typer.type_of(ti)
        if t.kind_of? SpecificDataType
          if s = t.singleton
            return s
          end
        end

        if alloca
          ptr = b.alloca t.alloca_type
        else
          ptr = b.call @top.context.malloc, t.byte_size
        end

        obj = b.bit_cast ptr, t.value_type
        if m = t.find_operation("initialize")
          m.invoke self, obj, *args
        elsif t.kind_of? SpecificDataType

          b.store LLVM::Int(t.code),
                  b.gep(obj, [LLVM::Int(0), LLVM::Int(0), LLVM::Int(0)])

          args = convert_args t, ti, "#{t.name}#initialize"

          i = 1
          args.each do |a|
            b.store a, b.gep(obj, [LLVM::Int(0), LLVM::Int(i)])
            i += 1
          end
        end

        obj
      else
        raise "Unknown type - #{name}"
      end
    end

    def gen_strlit(sv)
      s = sv.value
      
      const = LLVM::ConstantArray.string s, true
      c_str = @top.mod.globals.add const.type, @top.name(".cstr")
      c_str.initializer = const
      c_str.linkage = :private
      c_str.global_constant = 1

      str = @top.mod.globals.add @top.context.string_type, @top.name("string")
      str.linkage = :internal
      siz = LLVM::ConstantInt32.from_i s.size
      dat = c_str.gep LLVM::ConstantInt32.from_i(0), LLVM::ConstantInt32.from_i(0)
      init = LLVM::ConstantStruct.const_named @top.context.string_type, [siz, dat]
      str.initializer = init
      str.alignment = 8

      str
    end

    def simple_if(i)
      c = g i.condition
      c = b.bit_cast c, LLVM::Int1, "to_cond"

      comp = b.icmp :ne, c, LLVM::Int1.from_i(0)

      then_block = new_block "then"
      cont = new_block "continue"

      b.cond comp, then_block, cont

      set_block then_block

      g i.then_body

      if reachable?
        b.br cont
      end

      set_block cont

      nil
    end

    def gen_if_node(i)
      return simple_if(i) unless i.else_body

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

    def gen_while_node(i)
      top = new_block "top"

      b.br top

      set_block top

      c = g i.condition
      c = b.bit_cast c, LLVM::Int1, "to_cond"

      comp = b.icmp :ne, c, LLVM::Int1.from_i(0)

      body = new_block "body"
      cont = new_block "continue"

      b.cond comp, body, cont

      set_block body

      g i.body

      if reachable?
        b.br top
      end

      set_block cont

      nil
    end

    def type_name(t)
      case t.kind
      when :pointer
        "#{type_name t.element_type}*"
      when :array
        "#{type_name t.element_type}[]"
      when :struct
        t.name
      else
        t.to_s
      end
    end

    def gen_case_node(i)
      et = @top.type_of(i.condition)

      if et.kind_of? DynamicType
        return gen_dynamic_case_node(i)
      end

      unless et.kind_of? DataType
        raise TypeMismatchError, "Unsupported variable for case"
      end

      ev = g i.condition

      code = b.load b.gep(ev, [LLVM::Int(0), LLVM::Int(0)])

      i.whens.each do |w|
        need = @top.type_of(w.var)

        unless need.generic == et
          raise TypeMismatchError,
                "Type '#{need.name}' not a variant of '#{et.name}'"
        end

        c = b.icmp :eq, code, LLVM::Int(need.code)

        cont = new_block "continue"
        body = new_block "body"

        b.cond c, body, cont

        set_block body

        cast = b.bit_cast ev, need.value_type

        r = add_alloca need.value_type

        @locals[w.var.name] = need
        @scope[w.var.name] = r

        b.store cast, r

        g w.body

        b.br cont
        set_block cont
      end

      nil
    end

    def gen_dynamic_case_node(i)
      et = @top.type_of(i.condition)
      ev = g i.condition

      rt_is = b.load b.gep(ev, [LLVM::Int(0), LLVM::Int(0)])

      i.whens.each do |w|
        need = @top.type_of(w.var)

        rt_need = runtime_type(need)

        c = b.icmp :eq, rt_need, rt_is

        cont = new_block "continue"
        body = new_block "body"

        b.cond c, body, cont

        set_block body

        cast = b.bit_cast ev, LLVM::Type.pointer(specific_dynamic(need))

        r = add_alloca need.value_type

        @locals[w.var.name] = need
        @scope[w.var.name] = r

        s = b.load b.gep(cast, [LLVM::Int(0), LLVM::Int(1)])
        b.store s, r

        g w.body

        b.br cont
        set_block cont
      end

      nil
    end

    def gen_binary(i)
      t = @top.type_of i.receiver
      if t and op = t.find_operation(i.operator)
        return op.run(self, i)
      end

      raise "Unsupported operator - #{i.operator}"
    end

    def gen_ident(i)
      if l = @scope[i.name]
        b.load l, "#{i.name}.loaded"
      elsif l = @top.variables[i.name]
        l
      else
        raise "uninitialized local '#{i.name}' used"
      end
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

      if @meth.kind_of? AST::Lambda
        lt = @top.type_of @meth
        t = lt.ret_type.value_type
      else
        t = @top.value_type @meth.return_type
      end

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

      raise "Unable to find ivar '#{name}'" unless pos

      b.gep @self_value, [LLVM::Int(0), LLVM::Int(pos)]
    end

    def gen_assign(as)
      vt = @top.type_of(as.value)

      val = g as.value
      case as.variable
      when AST::InstanceVariable
        pos = self_gep(as.variable.name)

        it = @self.ivar_type(as.variable.name)
        if it != vt
          raise TypeMismatchError, "unable to assign a '#{vt.name}' to '@#{as.variable.name}' (a '#{it.name}')"
        end

        b.store val, pos
      when AST::Identifier
        loc = @scope[as.variable.name]
        b.store val, loc
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
    def initialize(func, args, name)
      @func = func
      @arg_types = args
      @name = name
    end

    attr_reader :arg_types

    def run(visit, node)
      recv = visit.g(node.receiver)
      args = visit.convert_args self, node, @name

      visit.b.call @func, recv, *args
    end

    def invoke(visit, *args)
      visit.b.call @func, *args
    end
  end

  class LLVMClassVisitor < LLVMVisitor
    def initialize(top, ast, type=nil)
      @top = top
      @ast = ast

      if type
        @talon_type = type
      else
        @talon_type = @top.type_by_name(ast.name)
      end

      @type = @talon_type.llvm_type
    end

    attr_reader :type, :talon_type

    def name
      @type.name
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
        args = meth.arguments.map { |a| @top.type_of(a) }
      else
        args = []
      end

      impl_args = [@type.pointer] + args.map { |a| a.value_type }

      if rt = meth.return_type
        ret = @top.value_type rt
      else
        ret = LLVM::Type.void
      end

      func = @top.mod.functions.add method_name(meth.name), impl_args, ret

      name = "#{@type.name}##{meth.name}"

      @talon_type.methods[meth.name] = Method.new func, args, name

      inner = LLVMFunctionVisitor.new @top, func, meth, self
      inner.gen_and_return meth.body
    end

    def gen_inc(inc)
      t = @top.traits[inc.name]
      raise "no trait named #{inc.name}" unless t

      g t.body
    end

    def offset(looking_for)
      @talon_type.ivar_offset looking_for
    end

    def ivar_type(looking_for)
      @talon_type.ivar looking_for
    end
  end

  class LLVMContext
    def initialize
      @mod = LLVM::Module.new("talon")
      data_pointer = LLVM::Type.pointer(LLVM::Int8)
      elems = [LLVM::Int32, data_pointer]
      @string_type = LLVM::Type.struct elems, false, "talon.String"

      elems = [LLVM::Type.pointer(@string_type)]
      @type_type = LLVM::Type.struct elems, false, "talon.Type"

      elems = [LLVM::Type.pointer(@type_type)]
      @dynamic_type = LLVM::Type.struct elems, false, "talon.Dynamic"

      @void_ptr = LLVM::Pointer(LLVM::Int8)
      @malloc = @mod.functions.add "malloc", [LLVM::Int64], @void_ptr
      @free = @mod.functions.add "free", [@void_ptr], LLVM::Type.void

      @uniq_names = 0
      @import_paths = ["lib"]

      @runtime_types = {}
      @specific_dynamics = {}
      @lambda_types = {}
    end

    attr_reader :typer
    attr_reader :malloc, :free, :void_ptr, :traits, :import_paths, :mod
    attr_reader :string_type, :type_type, :dynamic_type

    def name(prefix="tmp")
      "#{prefix}#{@uniq_names += 1}"
    end

    def global_string(s)
      const = LLVM::ConstantArray.string s, true
      c_str = @mod.globals.add const.type, name(".cstr")
      c_str.initializer = const
      c_str.linkage = :private
      c_str.global_constant = 1

      str = @mod.globals.add @string_type, name("string")
      str.linkage = :internal
      siz = LLVM::ConstantInt32.from_i s.size
      dat = c_str.gep LLVM::ConstantInt32.from_i(0), LLVM::ConstantInt32.from_i(0)
      init = LLVM::ConstantStruct.const_named @string_type, [siz, dat]
      str.initializer = init
      str.alignment = 8

      str
    end

    def runtime_type(type)
      cur = @runtime_types[type]

      unless cur
        s = global_string(type.name)

        t = @mod.globals.add @type_type, name(type.name)
        t.linkage = :internal
        t.initializer = LLVM::ConstantStruct.const_named @type_type, [s]
        t.alignment = 8

        @runtime_types[type] = t

        cur = t
      end

      cur
    end

    def specific_dynamic(t)
      cur = @specific_dynamics[t]

      unless cur
        elems = [@dynamic_type, t.value_type]
        cur = LLVM::Type.struct elems, false, "talon.Dynamic[#{t.name}]"

        @specific_dynamics[t] = cur
      end

      cur
    end

    def specific_lambda_type(args, ret, captures)
      LambdaType.new "lambda", args, ret, captures
    end

    def lambda_type(args, ret)
      key = [args, ret]

      if t = @lambda_types[key]
        return t
      end

      @lambda_types[key] = specific_lambda_type(args, ret, [])
    end

    def expanded_template_name(name, *concrete)
      case name
      when String
        name
      when AST::TemplatedName
        args = concrete.map { |e| e.name }
        "#{name.name}<#{args.join(',')}>"
      when AST::TemplatedInstance
        "#{name.name}<#{name.type}>"
      when AST::Identifier
        name.name
      else
        raise "Can't handle a #{name}"
      end
    end
  end

  class LLVMToplevelVisitor < LLVMVisitor
    def initialize(ctx, global_scope)
      @context = ctx
      @global_scope = global_scope

      @mod = @context.mod

      @typer = TypeCalculator.new ctx, global_scope

      @traits = {}

      @functions = {}
      @imports = {}

      @variables = {}
    end

    attr_reader :context, :imports, :mod, :typer, :traits, :functions
    attr_reader :variables

    def scope
      @typer.scope
    end

    def toplevel_function(name)
      if n = @functions[name]
        return n
      end
    end

    def runtime_type(t)
      @context.runtime_type(t)
    end

    def name(prefix="tmp")
      @context.name prefix
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
      t = @typer.lookup name
      return t if t.kind_of? Type
      nil
    end

    def template_name(name)
      case name
      when String
        name
      when AST::TemplatedName
        args = name.arguments.map { |a| template_name(a) }
        "#{name.name}<#{args.join(',')}>"
      when AST::TemplatedInstance
        "#{name.name}<#{@typer.lookup(name.type).name}>"
      when AST::Identifier
        name.name
      else
        raise "Can't handle a #{name}"
      end
    end

    def gen_seq(seq)
      seq.elements.each do |e|
        g e
      end
    end

    class Function
      def initialize(func, arg_types, ret_type, opts=nil, names=[])
        @func = func
        @arg_types = arg_types
        @ret_type = ret_type

        if opts and opts[:varargs]
          @varargs = true
        else
          @varargs = false
        end

        @arguments = names
      end

      attr_reader :func, :arg_types, :ret_type, :varargs, :arguments
    end

    def gen_method_dec(dec)
      if attr = dec.attribute
        if attr.name == "Import"
          name = attr.values["name"]
          
          opts = {}

          if dec.arguments.last.kind_of? AST::VariableArguments
            args = dec.arguments.dup
            opts[:varargs] = true
            args.pop
          else
            args = dec.arguments
          end

          names = args.map { |a| a.name }

          arg_types = args.map { |a| type_of(a) }

          args = arg_types.map { |a| a.value_type }

          ret_type = type_of dec.return_type
          ret = ret_type.value_type

          func = @mod.functions.add name, args, ret, opts
          @functions[dec.name] = Function.new(func, arg_types,
                                              ret_type, opts, names)
        end
      end
    end

    def gen_method_def(meth)
      if meth.arguments
        arg_types = meth.arguments.map { |a| type_of(a) }
        names = meth.arguments.map { |a| a.name }
      else
        arg_type = []
        names = []
      end

      opts = {}

      args = arg_types.map { |a| a.value_type }

      ret_type = type_of meth.return_type
      ret =  ret_type.value_type

      if pkg = @typer.scope.name
        meth_name = "#{pkg}.#{meth.name}"
      else
        meth_name = meth.name
      end

      func = @mod.functions.add meth_name, args, ret
      @functions[meth.name] = Function.new(func, arg_types, ret_type,
                                           opts, names)

      inner = LLVMFunctionVisitor.new self, func, meth
      inner.gen_and_return meth.body
    end

    def make_data(d, t, name)
      if pkg = @typer.scope.name
        name = "#{pkg}.#{name}"
      end

      t.cases.each do |c|
        if c.no_args?
          i1 = LLVM::ConstantStruct.const_named t.llvm_type, [LLVM::Int(c.code)]
          init = LLVM::ConstantStruct.const_named c.llvm_type, [i1]

          x = @mod.globals.add c.llvm_type, name(c.name)
          x.initializer = init
          x.linkage = :private
          x.global_constant = 1

          c.singleton = x

          @variables[c.name] = x
        end
      end
    end

    def gen_data(d)
      if d.name.kind_of? AST::TemplatedName
        t = @typer.scope[d.name.name]
        unless t.kind_of? Template
          raise "Phase 1 failure, didn't setup Template object"
        end

        t.instances.each do |st|
          make_data(d, st.type, st.type.name)
        end
      else
        make_data d, @typer.type_of(d), d.name
      end

    end

    def gen_class_def(cls)
      if cls.name.kind_of? AST::TemplatedName
        t = @typer.scope[cls.name.name]
        unless t.kind_of? Template
          raise "Phase 1 failure, didn't setup Template object"
        end

        t.instances.each do |temp|
          vis = LLVMClassVisitor.new self, temp.ast, temp.type
          vis.gen temp.ast.body
        end
      else
        vis = LLVMClassVisitor.new self, cls
        @typer.add_specific vis.name, vis.talon_type
        vis.gen cls.body
      end
    end

    def gen_trait_def(trait)
      @traits[trait.name] = trait
    end

    def gen_import(imp)
      name = imp.segements.first

      lv = scope[name]

      raise "Typer didn't inject sub-file properly" unless lv

      nil
    end

    def gen_package(pkg)
      nil
    end

    def run(ast)
      @typer.add ast

      gen ast

      @mod.dump if ENV["TALON_DEBUG"]
      @mod.verify!
    end

  end
end
