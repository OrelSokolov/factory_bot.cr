# Factory — порт factory_bot/factory.rb (+ null_factory.rb).
#
# Отклонения: build_class разрешается через FactoryBot.__constantize
# (compile-time справочник моделей) вместо String#constantize;
# иерархия to_create/constructor/callbacks вычисляется по цепочке
# родителей на лету (вместо генерации DefinitionHierarchy-классов).

module FactoryBot
  class Factory
    getter name : String
    getter definition : Definition

    @parent : String?
    @aliases : Array(String)
    @class_name : String | Symbol | ActiveRecord::Base.class | Nil
    @compiled = false
    @attributes : AttributeList?

    def initialize(@name : String | Symbol, parent : String | Symbol | Nil = nil,
                   class_name : String | Symbol | ActiveRecord::Base.class | Nil = nil,
                   aliases : Array(String) | Array(Symbol) | Nil = nil,
                   traits : Array(String) | Array(Symbol) | Nil = nil)
      @name = @name.to_s
      @parent = parent.try(&.to_s)
      @aliases = (aliases || [] of String).map(&.to_s)
      @class_name = class_name
      @definition = Definition.new(@name, traits || [] of String)
    end

    delegate add_callback, declare_attribute, define_trait, to: @definition

    def build_class : ActiveRecord::Base.class
      case (cn = class_name)
      when ActiveRecord::Base.class then cn
      else
        FactoryBot.__constantize(__camelize(cn.to_s))
      end
    end

    def run(build_strategy : String, overrides : Hash(String, FBValue)) : Product?
      run(build_strategy, overrides) { |instance| instance }
    end

    def run(build_strategy : String, overrides : Hash(String, FBValue),
            &block : Proc(Product, Nil)) : Product?
      compile

      strategy = Strategy.lookup(build_strategy)

      evaluator = Evaluator.new(strategy, overrides, __attribute_blocks)
      evaluator.build_class = build_class

      attribute_assigner = AttributeAssigner.new(
        evaluator, build_class, compiled_constructor, attributes)

      observer = CallbacksObserver.new(callbacks, evaluator)
      evaluation = Evaluation.new(evaluator, attribute_assigner, compiled_to_create, observer)

      evaluation.notify("before_all", nil)
      instance = strategy.result(evaluation)
      block.call(instance) if instance
      evaluation.notify("after_all", instance)

      instance
    end

    def human_names : Array(String)
      names.map { |name| name.tr("_", " ").capitalize.downcase }
    end

    def associations : Array(Attribute)
      attributes.associations.to_a
    end

    # Имена фабрики, включая алиасы.
    def names : Array(String)
      [@name] + @aliases
    end

    def compile : Nil
      unless @compiled
        parent_factory.try(&.compile)
        inherit_parent_traits
        @definition.compile(build_class)
        @compiled = true
      end
    end

    def with_traits(traits : Array(String)) : Factory
      factory_with_traits = Factory.new(@name, parent: @parent,
                                        class_name: @class_name, aliases: @aliases)
      factory_with_traits.definition = @definition.copy
      factory_with_traits.definition.append_traits(traits)
      factory_with_traits
    end

    def reset_compilation : Nil
      @compiled = false
      @attributes = nil
      @definition.reset_compilation
    end

    protected def definition=(definition : Definition)
      @definition = definition
    end

    protected def class_name : String | Symbol | ActiveRecord::Base.class | Nil
      @class_name || parent_factory.try(&.class_name) || @name
    end

    def attributes : AttributeList
      compile
      @attributes ||= begin
        # Слияние с родителем (аналог EvaluatorClassDefiner:
        # attribute_lists родителя + собственные; дочерние перекрывают).
        list = AttributeList.new(@name)
        if (parent = parent_factory)
          list.apply_attributes(parent.attributes.to_a)
        end
        list.apply_attributes(@definition.attributes.to_a)
        list
      end
    end

    def compiled_to_create : ToCreateBlock
      @definition.to_create || parent_factory.try(&.compiled_to_create) ||
        Internal.default_to_create
    end

    def compiled_constructor : ConstructorBlock
      @definition.constructor || parent_factory.try(&.compiled_constructor) ||
        Internal.default_constructor
    end

    def callbacks : Array(Callback)
      (parent_factory.try(&.callbacks) || [] of Callback) + @definition.callbacks +
        Internal.global_callbacks
    end

    def parent_factory : Factory?
      if (p = @parent)
        Internal.factory_by_name(p)
      end
    end

    def inherit_parent_traits : Nil
      parent_factory.try &.definition.defined_traits.each do |trait|
        next if @definition.defined_traits_names.includes?(trait.name)
        @definition.define_trait(trait)
      end
    end

    private def __attribute_blocks : Hash(String, AttrBlock)
      blocks = {} of String => AttrBlock
      attributes.each { |attribute| blocks[attribute.name] = attribute.block }
      blocks
    end

    private def __camelize(name : String) : String
      name.split("_").map(&.capitalize).join
    end
  end

  # Корень иерархии фабрик (порт factory_bot/null_factory.rb):
  # пустые атрибуты, дефолтные to_create/constructor.
  class NullFactory
    getter definition : Definition

    def initialize
      @definition = Definition.new("null_factory")
    end

    def compile : Nil
    end

    def class_name : String?
      nil
    end

    def compiled_to_create : ToCreateBlock
      Internal.default_to_create
    end

    def compiled_constructor : ConstructorBlock
      Internal.default_constructor
    end

    def callbacks : Array(Callback)
      Internal.global_callbacks
    end
  end
end
