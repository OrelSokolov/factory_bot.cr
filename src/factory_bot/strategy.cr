# Strategy — порты factory_bot/strategy.rb, strategy/{build,create,
# attributes_for,stub,null}.rb и factory_runner.rb.
#
# Отклонения (build_stubbed): вместо singleton-переопределений
# disabled-методов (save/destroy/...) порт ставит id/таймстемпы и
# new_record=false (persisted? == true); обращение к БД у заглушки не
# перехватывается.

module FactoryBot
  module Strategy
    abstract class Base
      def association(runner : FactoryRunner) : Product?
        runner.run
      end

      abstract def result(evaluation : Evaluation) : Product?

      abstract def to_sym : String
    end

    class Build < Base
      def result(evaluation : Evaluation) : Product?
        evaluation.notify("before_build", nil)

        evaluation.object.tap do |instance|
          evaluation.notify("after_build", instance)
        end
      end

      def to_sym : String
        "build"
      end
    end

    class Create < Base
      def result(evaluation : Evaluation) : Product?
        evaluation.notify("before_build", nil)

        evaluation.object.tap do |instance|
          evaluation.notify("after_build", instance)
          evaluation.notify("before_create", instance)
          evaluation.create(instance)
          evaluation.notify("after_create", instance)
        end
      end

      def to_sym : String
        "create"
      end
    end

    class AttributesFor < Base
      def association(runner : FactoryRunner) : Product?
        runner.run("null")
      end

      def result(evaluation : Evaluation) : Product?
        evaluation.hash
      end

      def to_sym : String
        "attributes_for"
      end
    end

    class Stub < Base
      @@next_id : Int64 = 1000

      def self.next_id=(id : Int64)
        @@next_id = id
      end

      def association(runner : FactoryRunner) : Product?
        runner.run("build_stubbed")
      end

      def result(evaluation : Evaluation) : Product?
        instance = evaluation.object
        stub_database_interaction_on_result(instance)
        set_timestamps(instance)
        instance.__snapshot_original!
        evaluation.notify("after_stub", instance)
        instance
      end

      def to_sym : String
        "stub"
      end

      private def stub_database_interaction_on_result(result_instance : ActiveRecord::Base) : Nil
        if result_instance.id.nil?
          result_instance.id = next_id
        end
        result_instance.new_record = false
        result_instance.destroyed = false
      end

      private def next_id : Int64
        @@next_id += 1
      end

      private def set_timestamps(result_instance : ActiveRecord::Base) : Nil
        timestamp = Time.utc

        columns = result_instance.class.__column_names
        if columns.includes?("created_at") && result_instance.attributes["created_at"]?.nil?
          result_instance.assign_attributes({"created_at" => timestamp})
        end
        if columns.includes?("updated_at") && result_instance.attributes["updated_at"]?.nil?
          result_instance.assign_attributes({"updated_at" => timestamp})
        end
      end
    end

    class Null < Base
      def association(runner : FactoryRunner) : Product?
        nil
      end

      def result(evaluation : Evaluation) : Product?
        nil
      end

      def to_sym : String
        "null"
      end
    end

    @@registry = {} of String => Base

    def self.register(name : String, strategy : Base) : Nil
      @@registry[name] = strategy
    end

    def self.lookup(name : String | Symbol) : Base
      key = name.to_s
      @@registry.fetch(key) do
        raise KeyError.new(%(Strategy not registered: "#{key}"))
      end
    end

    def self.reset : Nil
      @@registry.clear
      register_default_strategies
    end

    def self.register_default_strategies : Nil
      register("build", Build.new)
      register("create", Create.new)
      register("attributes_for", AttributesFor.new)
      register("build_stubbed", Stub.new)
      register("null", Null.new)
    end
  end

  # --- FactoryRunner ------------------------------------------------------------

  class FactoryRunner
    def initialize(@name : String, @strategy : String, @traits : Array(String),
                   @overrides : Hash(String, FBValue))
    end

    def run(runner_strategy : String = @strategy) : Product?
      factory = Internal.factory_by_name(@name)

      factory.compile

      unless @traits.empty?
        factory = factory.with_traits(@traits)
      end

      factory.run(runner_strategy, @overrides)
    end

    def run(runner_strategy : String = @strategy, &block : Proc(Product, Nil)) : Product?
      factory = Internal.factory_by_name(@name)

      factory.compile

      unless @traits.empty?
        factory = factory.with_traits(@traits)
      end

      factory.run(runner_strategy, @overrides) { |instance| block.call(instance) }
    end
  end
end

# Регистрация стандартных стратегий при загрузке шардa.
FactoryBot::Strategy.register_default_strategies
