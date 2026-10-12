# Syntax — порты factory_bot/syntax/{methods,default}.rb:
# DSL/ModifyDSL и стратегии как методы модуля FactoryBot (+ миксин
# Syntax::Methods для тестовых контекстов).

module FactoryBot
  module Syntax
    ## Контейнер стратегийных методов (миксин в тестовые классы).
    module Methods
      def build(_name : String | Symbol, *_traits,
                **overrides, &block : Proc(Product, Nil)) : Product?
        FactoryBot.build(_name, *_traits, **overrides) { |i| block.call(i) }
      end

      def build(_name : String | Symbol, *_traits,
                **overrides) : Product?
        FactoryBot.build(_name, *_traits, **overrides)
      end

      def create(_name : String | Symbol, *_traits,
                 **overrides, &block : Proc(Product, Nil)) : Product?
        FactoryBot.create(_name, *_traits, **overrides) { |i| block.call(i) }
      end

      def create(_name : String | Symbol, *_traits,
                 **overrides) : Product?
        FactoryBot.create(_name, *_traits, **overrides)
      end

      def build_stubbed(_name : String | Symbol, *_traits,
                        **overrides, &block : Proc(Product, Nil)) : Product?
        FactoryBot.build_stubbed(_name, *_traits, **overrides) { |i| block.call(i) }
      end

      def build_stubbed(_name : String | Symbol, *_traits,
                        **overrides) : Product?
        FactoryBot.build_stubbed(_name, *_traits, **overrides)
      end

      def attributes_for(_name : String | Symbol, *_traits,
                         **overrides) : Hash(String, FBValue)
        FactoryBot.attributes_for(_name, *_traits, **overrides)
      end

      def build_list(_name : String | Symbol, _amount : Int32, *_traits,
                     **overrides, &block : Proc(Product, Int32, Nil)) : Array(Product)
        FactoryBot.build_list(_name, _amount, *_traits, **overrides) { |i, n| block.call(i, n) }
      end

      def build_list(_name : String | Symbol, _amount : Int32, *_traits,
                     **overrides) : Array(Product)
        FactoryBot.build_list(_name, _amount, *_traits, **overrides)
      end

      def create_list(_name : String | Symbol, _amount : Int32, *_traits,
                      **overrides, &block : Proc(Product, Int32, Nil)) : Array(Product)
        FactoryBot.create_list(_name, _amount, *_traits, **overrides) { |i, n| block.call(i, n) }
      end

      def create_list(_name : String | Symbol, _amount : Int32, *_traits,
                      **overrides) : Array(Product)
        FactoryBot.create_list(_name, _amount, *_traits, **overrides)
      end

      def build_stubbed_list(_name : String | Symbol, _amount : Int32, *_traits,
                             **overrides) : Array(Product)
        FactoryBot.build_stubbed_list(_name, _amount, *_traits, **overrides)
      end

      def attributes_for_list(_name : String | Symbol, _amount : Int32, *_traits,
                              **overrides) : Array(Hash(String, FBValue))
        FactoryBot.attributes_for_list(_name, _amount, *_traits, **overrides)
      end

      def build_pair(_name : String | Symbol, *_traits,
                     **overrides) : Array(Product)
        FactoryBot.build_pair(_name, *_traits, **overrides)
      end

      def create_pair(_name : String | Symbol, *_traits,
                      **overrides) : Array(Product)
        FactoryBot.create_pair(_name, *_traits, **overrides)
      end

      def build_stubbed_pair(_name : String | Symbol, *_traits,
                             **overrides) : Array(Product)
        FactoryBot.build_stubbed_pair(_name, *_traits, **overrides)
      end

      def attributes_for_pair(_name : String | Symbol, *_traits,
                              **overrides) : Array(Hash(String, FBValue))
        FactoryBot.attributes_for_pair(_name, *_traits, **overrides)
      end

      def generate(_name : String | Symbol) : FBValue
        FactoryBot.generate(_name)
      end

      def generate_list(_name : String | Symbol, count : Int32) : Array(FBValue)
        FactoryBot.generate_list(_name, count)
      end
    end

    module Default
      # DSL блока FactoryBot.define: factory / sequence / trait
      # (+ глобальные before/after/to_create/initialize_with).
      class DSL
        def factory(name : String | Symbol, **opts) : Nil
          opts_h = FactoryBot.__opts_hash(opts)
          factory = Factory.new(name.to_s,
            parent: FactoryBot.__opt_string?(opts_h["parent"]?),
            class_name: FactoryBot.__opt_class?(opts_h["class"]?),
            aliases: FactoryBot.__string_list?(opts_h["aliases"]?),
            traits: FactoryBot.__string_list?(opts_h["traits"]?))
          Internal.register_factory(factory)
        end

        def factory(name : String | Symbol, **opts, &) : Nil
          opts_h = FactoryBot.__opts_hash(opts)
          factory = Factory.new(name.to_s,
            parent: FactoryBot.__opt_string?(opts_h["parent"]?),
            class_name: FactoryBot.__opt_class?(opts_h["class"]?),
            aliases: FactoryBot.__string_list?(opts_h["aliases"]?),
            traits: FactoryBot.__string_list?(opts_h["traits"]?))
          proxy = DefinitionProxy.new(factory.definition, false, factory)
          with proxy yield
          Internal.register_factory(factory)
        end

        def sequence(name : String | Symbol, initial : Int64 | Int32 | Array(String) | Array(Symbol) = 1_i64,
                     *, aliases : Array(String | Symbol) = [] of String, &block : Proc(Int64, FBValue)) : Nil
          seq = Sequence.new(name, initial, aliases: aliases)
          seq.sequence(&block)
          Internal.register_sequence(seq)
        end

        def sequence(name : String | Symbol, initial : Int64 | Int32 | Array(String) | Array(Symbol) = 1_i64,
                     *, aliases : Array(String | Symbol) = [] of String) : Nil
          Internal.register_sequence(Sequence.new(name, initial, aliases: aliases))
        end

        def trait(name : String | Symbol, &) : Nil
          t = Trait.new(name.to_s)
          proxy = DefinitionProxy.new(t.definition)
          with proxy yield
          Internal.register_trait(t)
        end

        def before(*names : String | Symbol, &block : Proc(Nil)) : Nil
          Internal.global_before(*names, &block)
        end

        def before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
          Internal.global_before(*names, &block)
        end

        def before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
          Internal.global_before(*names, &block)
        end

        def after(*names : String | Symbol, &block : Proc(Nil)) : Nil
          Internal.global_after(*names, &block)
        end

        def after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
          Internal.global_after(*names, &block)
        end

        def after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
          Internal.global_after(*names, &block)
        end

        def to_create(&block : Proc(ActiveRecord::Base, Nil)) : Nil
          Internal.define_global_to_create(block)
        end

        def to_create(&block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
          Internal.define_global_to_create(block)
        end

        def initialize_with(&block : Proc(Evaluator, ActiveRecord::Base)) : Nil
          Internal.define_global_constructor(block)
        end

        def skip_create : Nil
          Internal.define_global_to_create(->(instance : ActiveRecord::Base) { nil })
        end
      end

      class ModifyDSL
        def factory(name : String | Symbol, **opts, &) : Nil
          factory = Internal.factory_by_name(name.to_s)
          factory.definition.overridable
          proxy = DefinitionProxy.new(factory.definition, false, factory)
          with proxy yield
          factory.reset_compilation
        end
      end
    end
  end

  # --- Методы модуля FactoryBot (extend Syntax::Default + Strategies) ------

  def self.define(&) : Nil
    dsl = Syntax::Default::DSL.new
    with dsl yield
  end

  def self.modify(&) : Nil
    dsl = Syntax::Default::ModifyDSL.new
    with dsl yield
  end

  def self.build(_name : String | Symbol, *_traits,
                 **overrides, &block : Proc(Product, Nil)) : Product?
    __strategy_run("build", _name, __traits_a(_traits), __overrides_hash(overrides)) { |i| block.call(i) }
  end

  def self.build(_name : String | Symbol, *_traits,
                 **overrides) : Product?
    __strategy_run("build", _name, __traits_a(_traits), __overrides_hash(overrides))
  end

  def self.create(_name : String | Symbol, *_traits,
                  **overrides, &block : Proc(Product, Nil)) : Product?
    __strategy_run("create", _name, __traits_a(_traits), __overrides_hash(overrides)) { |i| block.call(i) }
  end

  def self.create(_name : String | Symbol, *_traits,
                  **overrides) : Product?
    __strategy_run("create", _name, __traits_a(_traits), __overrides_hash(overrides))
  end

  def self.build_stubbed(_name : String | Symbol, *_traits,
                         **overrides, &block : Proc(Product, Nil)) : Product?
    __strategy_run("build_stubbed", _name, __traits_a(_traits), __overrides_hash(overrides)) { |i| block.call(i) }
  end

  def self.build_stubbed(_name : String | Symbol, *_traits,
                         **overrides) : Product?
    __strategy_run("build_stubbed", _name, __traits_a(_traits), __overrides_hash(overrides))
  end

  def self.attributes_for(_name : String | Symbol, *_traits,
                          **overrides) : Hash(String, FBValue)
    result = __strategy_run("attributes_for", _name, __traits_a(_traits), __overrides_hash(overrides))
    result.as(Hash(String, FBValue))
  end

  def self.null(_name : String | Symbol, *_traits,
                **overrides) : Product?
    __strategy_run("null", _name, __traits_a(_traits), __overrides_hash(overrides))
  end

  def self.build_list(_name : String | Symbol, _amount : Int32, *_traits,
                      **overrides, &block : Proc(Product, Int32, Nil)) : Array(Product)
    Array.new(_amount) { |i| build(_name, *_traits, **overrides) { |inst| block.call(inst, i) }.as(Product) }
  end

  def self.build_list(_name : String | Symbol, _amount : Int32, *_traits,
                      **overrides) : Array(Product)
    Array.new(_amount) { build(_name, *_traits, **overrides).as(Product) }
  end

  def self.create_list(_name : String | Symbol, _amount : Int32, *_traits,
                       **overrides, &block : Proc(Product, Int32, Nil)) : Array(Product)
    Array.new(_amount) { |i| create(_name, *_traits, **overrides) { |inst| block.call(inst, i) }.as(Product) }
  end

  def self.create_list(_name : String | Symbol, _amount : Int32, *_traits,
                       **overrides) : Array(Product)
    Array.new(_amount) { create(_name, *_traits, **overrides).as(Product) }
  end

  def self.build_stubbed_list(_name : String | Symbol, _amount : Int32, *_traits,
                              **overrides) : Array(Product)
    Array.new(_amount) { build_stubbed(_name, *_traits, **overrides).as(Product) }
  end

  def self.attributes_for_list(_name : String | Symbol, _amount : Int32, *_traits,
                               **overrides) : Array(Hash(String, FBValue))
    Array.new(_amount) { attributes_for(_name, *_traits, **overrides) }
  end

  def self.build_pair(_name : String | Symbol, *_traits,
                      **overrides) : Array(Product)
    Array.new(2) { build(_name, *_traits, **overrides).as(Product) }
  end

  def self.create_pair(_name : String | Symbol, *_traits,
                       **overrides) : Array(Product)
    Array.new(2) { create(_name, *_traits, **overrides).as(Product) }
  end

  def self.build_stubbed_pair(_name : String | Symbol, *_traits,
                              **overrides) : Array(Product)
    Array.new(2) { build_stubbed(_name, *_traits, **overrides).as(Product) }
  end

  def self.attributes_for_pair(_name : String | Symbol, *_traits,
                               **overrides) : Array(Hash(String, FBValue))
    Array.new(2) { attributes_for(_name, *_traits, **overrides) }
  end

  # Запуск произвольной (в т.ч. кастомной) стратегии по имени —
  # замена runtime-генерации методов в StrategySyntaxMethodRegistrar.
  def self.run_strategy(strategy_name : String | Symbol, _name : String | Symbol,
                        *_traits, **overrides) : Product?
    __strategy_run(strategy_name.to_s, _name, __traits_a(_traits), __overrides_hash(overrides))
  end

  def self.generate(_name : String | Symbol) : FBValue
    sequence = Sequence.find_by_uri(_name.to_s) ||
               Internal.sequences.find(_name.to_s)
    sequence.next_value
  end

  def self.generate_list(_name : String | Symbol, count : Int32) : Array(FBValue)
    Array.new(count) { generate(_name) }
  end

  def self.rewind_sequences : Nil
    Internal.rewind_sequences
  end

  def self.lint(factories : Array(Factory)? = nil, traits : Bool = false,
                verbose : Bool = false, strategy : String | Symbol = "create") : Nil
    factories ||= Internal.factories.to_a
    Linter.new(factories, strategy.to_s, traits).lint!
  end

  def self.reload : Nil
    Internal.reset
  end

  # Глобальные before/after/to_create/initialize_with вне блока define.
  def self.before(*names : String | Symbol, &block : Proc(Nil)) : Nil
    Internal.global_before(*names, &block)
  end

  def self.before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
    Internal.global_before(*names, &block)
  end

  def self.before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
    Internal.global_before(*names, &block)
  end

  def self.after(*names : String | Symbol, &block : Proc(Nil)) : Nil
    Internal.global_after(*names, &block)
  end

  def self.after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
    Internal.global_after(*names, &block)
  end

  def self.after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
    Internal.global_after(*names, &block)
  end

  def self.to_create(&block : Proc(ActiveRecord::Base, Nil)) : Nil
    Internal.define_global_to_create(block)
  end

  def self.to_create(&block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
    Internal.define_global_to_create(block)
  end

  def self.initialize_with(&block : Proc(Evaluator, ActiveRecord::Base)) : Nil
    Internal.define_global_constructor(block)
  end

  def self.skip_create : Nil
    Internal.define_global_to_create(->(instance : ActiveRecord::Base) { nil })
  end

  # --- Внутренние -------------------------------------------------------------

  # Tuple-сплат трейтов → Array(String) (аннотированный сплат вместе с
  # **overrides ломает матчинг нулевого числа аргументов — см. PLAN.md).
  def self.__traits_a(traits) : Array(String)
    ts = [] of String
    traits.each { |t| ts << t.to_s }
    ts
  end

  def self.__strategy_run(strategy : String, name : String | Symbol,
                          traits : Array(String),
                          overrides : Hash(String, FBValue)) : Product?
    runner = FactoryRunner.new(name.to_s, strategy,
                               __traits_a(traits), overrides)
    runner.run
  end

  def self.__strategy_run(strategy : String, name : String | Symbol,
                          traits : Array(String),
                          overrides : Hash(String, FBValue),
                          &block : Proc(Product, Nil)) : Product?
    runner = FactoryRunner.new(name.to_s, strategy,
                               __traits_a(traits), overrides)
    runner.run { |instance| block.call(instance) }
  end

  # NamedTuple опций/оврайдов → Hash(String, Object) (без нормализации;
  # значения любого типа).
  def self.__opts_hash(nt : NamedTuple) : Hash(String, OptValue)
    h = {} of String => OptValue
    nt.each { |k, v| h[k.to_s] = v.as(OptValue) }
    h
  end

  # NamedTuple оврайдов → Hash(String, FBValue).
  def self.__overrides_hash(nt : NamedTuple) : Hash(String, FBValue)
    h = {} of String => FBValue
    nt.each { |k, v| h[k.to_s] = __normalize(v) }
    h
  end

  def self.__opt_string?(v : OptValue?) : String?
    case v
    when String, Symbol then v.to_s
    else nil
    end
  end

  def self.__opt_class?(v : OptValue?) : String | Symbol | ActiveRecord::Base.class | Nil
    case v
    when ActiveRecord::Base.class then v
    when String, Symbol then v
    else nil
    end
  end

  def self.__string_list?(v : OptValue?) : Array(String)?
    case v
    when Array then v.map(&.to_s)
    else nil
    end
  end
end
