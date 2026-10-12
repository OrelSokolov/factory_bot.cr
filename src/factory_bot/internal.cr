# Internal — порт factory_bot/internal.rb (+ configuration.rb): реестры,
# глобальная конфигурация (default to_create/constructor, global callbacks).

module FactoryBot
  module Internal
    class_property? initialized = false

    @@factories = Registry(Factory).new("Factory", duplicates_allowed: false)
    @@sequences = Registry(Sequence).new("Sequence", duplicates_allowed: false)
    @@traits = Registry(Trait).new("Trait", duplicates_allowed: false)
    @@inline_sequences = [] of Sequence
    @@global_callbacks = [] of Callback

    def self.factories : Registry(Factory)
      @@factories
    end

    def self.sequences : Registry(Sequence)
      @@sequences
    end

    def self.inline_sequences : Array(Sequence)
      @@inline_sequences
    end

    def self.register_inline_sequence(sequence : Sequence) : Sequence
      @@inline_sequences << sequence
      sequence
    end

    def self.rewind_inline_sequences : Nil
      @@inline_sequences.each(&.rewind)
    end

    def self.register_trait(trait : Trait) : Trait
      trait.names.each { |name| @@traits.register(name, trait) }
      trait
    end

    def self.trait_by_name(name : String, klass : ActiveRecord::Base.class | Nil) : Trait
      @@traits.find(name).tap { |t| t.klass ||= klass }
    end

    def self.register_sequence(sequence : Sequence) : Sequence
      sequence.names.each { |name| @@sequences.register(name, sequence) }
      sequence
    end

    def self.sequence_by_name(name : String | Symbol) : Sequence
      @@sequences.find(name.to_s)
    end

    def self.rewind_sequences : Nil
      @@sequences.each(&.rewind)
      rewind_inline_sequences
    end

    def self.register_factory(factory : Factory) : Factory
      factory.names.each { |name| @@factories.register(name, factory) }
      factory
    end

    def self.factory_by_name(name : String | Symbol) : Factory
      @@factories.find(name.to_s)
    end

    def self.register_strategy(strategy_name : String, strategy_class : Strategy::Base) : Nil
      Strategy.register(strategy_name, strategy_class)
    end

    def self.strategy_by_name(name : String | Symbol) : Strategy::Base
      Strategy.lookup(name.to_s)
    end

    # --- Глобальная конфигурация (Configuration) ------------------------------

    def self.default_to_create : ToCreateBlock
      @@default_to_create ||= ->(instance : ActiveRecord::Base) { instance.__fb_save!; nil }
    end

    def self.default_constructor : ConstructorBlock
      @@default_constructor ||= ->(evaluator : Evaluator) { evaluator.new_instance }
    end

    @@default_to_create : ToCreateBlock?
    @@default_constructor : ConstructorBlock?

    def self.global_callbacks : Array(Callback)
      @@global_callbacks
    end

    def self.define_global_to_create(block : ToCreateBlock) : Nil
      @@default_to_create = block
    end

    def self.define_global_constructor(block : ConstructorBlock) : Nil
      @@default_constructor = block
    end

    def self.global_before(*names : String | Symbol, &block : Proc(Nil)) : Nil
      __global_callback("before", names, block)
    end

    def self.global_before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
      __global_callback("before", names, block)
    end

    def self.global_before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      __global_callback("before", names, block)
    end

    def self.global_after(*names : String | Symbol, &block : Proc(Nil)) : Nil
      __global_callback("after", names, block)
    end

    def self.global_after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
      __global_callback("after", names, block)
    end

    def self.global_after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      __global_callback("after", names, block)
    end

    private def self.__global_callback(prefix : String, names, block : CallbackBlock) : Nil
      names.each { |cb_name| @@global_callbacks << Callback.new("#{prefix}_#{cb_name}", block) }
    end

    def self.reset : Nil
      @@factories.clear
      @@sequences.clear
      @@traits.clear
      @@inline_sequences.clear
      @@global_callbacks.clear
      @@default_to_create = nil
      @@default_constructor = nil
      Strategy.reset
    end
  end
end
