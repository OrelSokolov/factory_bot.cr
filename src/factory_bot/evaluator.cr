# Evaluator — порт factory_bot/evaluator.rb (+ evaluator_class_definer.rb:
# вместо генерации классов с методами атрибутов используется хэш блоков;
# чтение атрибутов — через method_missing).

module FactoryBot
  class Evaluator
    property instance : ActiveRecord::Base?
    property build_class : ActiveRecord::Base.class = ActiveRecord::Base

    getter overrides : Hash(String, FBValue)

    @blocks : Hash(String, AttrBlock)
    @cached : Hash(String, FBValue)
    @invoked : Set(String)
    @tracking : Bool = false

    def initialize(@strategy : Strategy::Base, overrides : Hash(String, FBValue),
                   @blocks : Hash(String, AttrBlock))
      @overrides = overrides
      @cached = @overrides.dup
      @invoked = Set(String).new
    end

    # Чтение атрибута с кэшем (аналог сгенерированных методов гема).
    def __read(name : String) : FBValue
      @invoked << name if @tracking
      if @cached.has_key?(name)
        return @cached[name]
      end
      block = @blocks[name]?
      value = if (b1 = block.as?(Proc(Evaluator, FBValue)))
                b1.call(self)
              elsif (b0 = block.as?(Proc(FBValue)))
                b0.call
              else
                return nil
              end
      value = FactoryBot.__normalize_int(value)
      @cached[name] = value
      value
    end

    # Ассоциация из тела динамического атрибута / Attribute::Association.
    def association(factory_name : String, traits : Array(String),
                    overrides : Hash(String, FBValue)) : FBValue
      overrides = overrides.dup
      strategy_override = overrides.delete("strategy")
      strategy_name = case strategy_override
                      when String, Symbol then strategy_override.to_s
                      else
                        FactoryBot.use_parent_strategy? ? @strategy.to_sym : "create"
                      end
      runner = FactoryRunner.new(factory_name, strategy_name,
                                 traits, overrides)
      @strategy.association(runner).as(FBValue)
    end

    def generate(name : String | Symbol) : FBValue
      FactoryBot.generate(name)
    end

    def generate_list(name : String | Symbol, count : Int32) : Array(FBValue)
      FactoryBot.generate_list(name, count)
    end

    # Конструктор по умолчанию (initialize_with { new } в Ruby).
    def new_instance : ActiveRecord::Base
      build_class.new
    end

    def increment_sequence(sequence : Sequence) : FBValue
      sequence.next_value
    end

    def __override_names : Array(String)
      @overrides.keys
    end

    def __start_tracking : Nil
      @tracking = true
    end

    def __stop_tracking : Nil
      @tracking = false
    end

    def __invoked_methods : Array(String)
      @invoked.to_a
    end

    # Чтение атрибутов в теле динамического блока: `e.name` / `e.admin`.
    macro method_missing(call)
      {% if call.args.empty? && !call.block && call.named_args.nil? %}
        __read({{ call.name.stringify }})
      {% else %}
        {% raise <<-ERROR
          #{call.name} is not an attribute of this factory; the evaluator
          responds to attribute reads without arguments only (e.g. `e.#{call.name}`)
        ERROR
         %}
      {% end %}
    end
  end
end
