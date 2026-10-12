# DefinitionProxy — порт factory_bot/definition_proxy.rb.
#
# Сахар атрибутов (`email { |e| ... }`, `admin`, `author factory: :user`)
# диспетчеризуется method_missing-макросом, генерирующим перегрузку def
# под форму вызова (см. HEAD-комментарий factory_bot_cr.cr). В отличие от
# Ruby, статические значения атрибутов не поддержаны и в 6.x гема — любое
# значение задаётся блоком.

module FactoryBot
  class DefinitionProxy
    def initialize(@definition : Definition, @ignore : Bool = false,
                   @factory : Factory? = nil)
    end

    # add_attribute(:name) { ... } — с evaluator-ом или без.
    def add_attribute(name : String | Symbol, &block : Proc(FBValue)) : Nil
      @definition.declare_attribute(
        Declaration::Dynamic.new(name.to_s, @ignore, block))
    end

    def add_attribute(name : String | Symbol, &block : Proc(Evaluator, FBValue)) : Nil
      @definition.declare_attribute(
        Declaration::Dynamic.new(name.to_s, @ignore, block))
    end

    def transient(&) : Nil
      proxy = DefinitionProxy.new(@definition, true, @factory)
      with proxy yield
    end

    # sequence(:email) { |n| "person#{n}@example.com" } — inline-версия
    # внутри фабрики; глобальная последовательность НЕ регистрируется.
    def sequence(name : String | Symbol, initial : Int64 | Int32 | Array(String) | Array(Symbol) = 1_i64,
                 *, aliases : Array(String | Symbol) = [] of String, &block : Proc(Int64, FBValue)) : Nil
      seq = Sequence.new(name, initial, aliases: aliases)
      seq.sequence(&block)
      __register_inline_sequence(seq, name)
    end

    def sequence(name : String | Symbol, initial : Int64 | Int32 | Array(String) | Array(Symbol) = 1_i64,
                 *, aliases : Array(String | Symbol) = [] of String) : Nil
      seq = Sequence.new(name, initial, aliases: aliases)
      __register_inline_sequence(seq, name)
    end

    # association :author, factory: :user, strategy: :build
    # (сплат без аннотации: аннотированный сплат вместе с **nargs не
    # матчит вызовы — см. PLAN.md)
    def association(name : String | Symbol, *traits, **nargs) : Nil
      opts = FactoryBot.__opts_hash(nargs)
      factory_opt = opts.delete("factory")
      opts.delete("strategy")
      ts = [] of String
      traits.each { |t| ts << t.to_s }
      overrides = {} of String => FBValue
      opts.each do |k, v|
        overrides[k] = FactoryBot.__normalize(v)
      end
      __declare_association(name.to_s, factory_opt || name, ts, overrides)
    end

    # association :author, {"factory" => :user, ...} — форма method_missing.
    def association(name : String | Symbol, opts : Hash(String, OptValue)) : Nil
      factory_opt = opts["factory"]?
      overrides = {} of String => FBValue
      opts.each do |k, v|
        next if k == "factory" || k == "strategy"
        overrides[k] = FactoryBot.__normalize(v)
      end
      __declare_association(name.to_s, factory_opt || name, [] of String, overrides)
    end

    def to_create(&block : Proc(ActiveRecord::Base, Nil)) : Nil
      @definition.define_to_create(block)
    end

    def to_create(&block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      @definition.define_to_create(block)
    end

    def skip_create : Nil
      @definition.skip_create
    end

    # initialize_with { |e| e.new_instance } — аналог Ruby
    # `initialize_with { new }` (конструктор делегируется build_class).
    def initialize_with(&block : Proc(Evaluator, ActiveRecord::Base)) : Nil
      @definition.define_constructor(block)
    end

    # Вложенная фабрика: в отличие от Ruby (отложенная регистрация
    # child_factories после родителя) регистрируется немедленно —
    # блок должен выполниться на прокси ребёнка сразу (uncaptured yield).
    def factory(name : String | Symbol, **opts) : Nil
      parent = @factory.not_nil!
      opts_h = FactoryBot.__opts_hash(opts)
      child = Factory.new(name.to_s,
        parent: FactoryBot.__opt_string?(opts_h["parent"]?) || parent.name,
        class_name: FactoryBot.__opt_class?(opts_h["class"]?),
        aliases: FactoryBot.__string_list?(opts_h["aliases"]?),
        traits: FactoryBot.__string_list?(opts_h["traits"]?))
      Internal.register_factory(child)
    end

    def factory(name : String | Symbol, **opts, &) : Nil
      parent = @factory.not_nil!
      opts_h = FactoryBot.__opts_hash(opts)
      parent_name = FactoryBot.__opt_string?(opts_h["parent"]?) || parent.name
      child = Factory.new(name.to_s,
        parent: parent_name,
        class_name: FactoryBot.__opt_class?(opts_h["class"]?),
        aliases: FactoryBot.__string_list?(opts_h["aliases"]?),
        traits: FactoryBot.__string_list?(opts_h["traits"]?))
      Internal.register_factory(child)
      child_proxy = DefinitionProxy.new(child.definition, false, child)
      with child_proxy yield
    end

    def trait(name : String | Symbol, &) : Nil
      t = Trait.new(name.to_s)
      proxy = DefinitionProxy.new(t.definition, false, @factory)
      with proxy yield
      @definition.define_trait(t)
    end

    # traits_for_enum :status, ["started", "finished"] / {"started" => 1}
    def traits_for_enum(attribute_name : String | Symbol,
                        values : Array(String | Symbol) | Hash(String, FBValue)) : Nil
      @definition.register_enum(Enum.new(attribute_name.to_s, values))
    end

    def before(*names : String | Symbol, &block : Proc(Nil)) : Nil
      @definition.before(*names, &block)
    end

    def before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
      @definition.before(*names, &block)
    end

    def before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      @definition.before(*names, &block)
    end

    def after(*names : String | Symbol, &block : Proc(Nil)) : Nil
      @definition.after(*names, &block)
    end

    def after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
      @definition.after(*names, &block)
    end

    def after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      @definition.after(*names, &block)
    end

    def callback(*names : String | Symbol, &block : Proc(Nil)) : Nil
      @definition.callback(*names, &block)
    end

    def callback(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
      @definition.callback(*names, &block)
    end

    def callback(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      @definition.callback(*names, &block)
    end

    # --- method_missing: сахар атрибутов ------------------------------------

    macro method_missing(call)
      {% if call.block %}
        {% if call.block.args.empty? %}
          def {{call.name.id}}({% unless call.args.empty? %}{{ call.args.splat }}, {% end %}&block : Proc(FBValue))
            __declare_dynamic0({{call.name.stringify}}, block)
          end
        {% else %}
          def {{call.name.id}}({% unless call.args.empty? %}{{ call.args.splat }}, {% end %}&block : Proc(Evaluator, FBValue))
            __declare_dynamic1({{call.name.stringify}}, block)
          end
        {% end %}
      {% else %}
        def {{call.name.id}}(*args, **nargs)
          __declare_plain({{call.name.stringify}}, args, nargs)
        end
      {% end %}
    end

    def __declare_dynamic0(name : String, block : Proc(FBValue)) : Nil
      @definition.declare_attribute(
        Declaration::Dynamic.new(name, @ignore, block))
    end

    def __declare_dynamic1(name : String, block : Proc(Evaluator, FBValue)) : Nil
      @definition.declare_attribute(
        Declaration::Dynamic.new(name, @ignore, block))
    end

    def __declare_plain(name : String, args : Tuple, nargs : NamedTuple) : Nil
      opts = {} of String => OptValue
      nargs.to_a.each { |pair| opts[pair[0].to_s] = pair[1].as(OptValue) }
      if opts.size > 0
        if opts.has_key?("factory")
          association(name, opts)
        else
          first_value = opts.values.first?
          raise RuntimeError.new(
            "undefined method '#{name}' in '#{@definition.name}' factory\n" \
            "Did you mean? '#{name} { #{first_value.inspect} }'")
        end
      elsif args.size > 0
        first_arg = args.to_a.first?
        raise RuntimeError.new(
          "undefined method '#{name}' in '#{@definition.name}' factory\n" \
          "Did you mean? '#{name} { #{first_arg.inspect} }'")
      else
        @definition.declare_attribute(Declaration::Implicit.new(name, @ignore))
      end
    end

    def __declare_association(name : String, factory_name : OptValue,
                              traits : Array(String), overrides : Hash(String, FBValue)) : Nil
      @definition.declare_attribute(
        Declaration::Association.new(name, factory_name, traits, overrides))
    end

    def __register_inline_sequence(seq : Sequence, name : String | Symbol) : Nil
      registered = (uri = seq.uris.first?) && Sequence.find_by_uri(uri)
      registered ||= Internal.register_inline_sequence(seq)
      add_attribute(name) { registered.next_value }
    end
  end
end
