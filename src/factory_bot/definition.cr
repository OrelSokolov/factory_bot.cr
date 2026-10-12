# Definition / Trait — порты factory_bot/definition.rb, definition_hierarchy.rb
# (иерархия to_create/constructor/callbacks считается на лету цепочкой
# родительских фабрик вместо генерации классов) и factory_bot/trait.rb.

module FactoryBot
  class Definition
    getter name : String
    getter declarations : DeclarationList
    getter defined_traits = [] of Trait
    property klass : ActiveRecord::Base.class | Nil

    @callbacks = [] of Callback
    @base_traits = [] of String
    @additional_traits = [] of String
    @to_create : ToCreateBlock?
    @constructor : ConstructorBlock?
    @attributes : AttributeList?
    @compiled = false
    @expanded_enum_traits = false
    @registered_enums = [] of Enum

    def initialize(@name : String, base_traits = [] of String, uri_paths : Array(String)? = nil)
      @declarations = DeclarationList.new(@name)
      @base_traits = base_traits.map(&.to_s)
    end

    def declare_attribute(declaration : Declaration) : Nil
      @declarations.declare_attribute(declaration)
    end

    def attributes : AttributeList
      @attributes ||= begin
        list = AttributeList.new(@name)
        aggregate_attributes.each { |attrs| list.apply_attributes(attrs.to_a) }
        list
      end
    end

    # aggregate_from_traits_and_self: базовые трейты → собственное →
    # дополнительные; у to_create/constructor побеждает последний ненулевой.
    def to_create : ToCreateBlock?
      candidates = resolved_base_traits.map(&.definition.own_to_create) +
                   [@to_create] +
                   resolved_additional_traits.map(&.definition.own_to_create)
      candidates.reject(Nil).last?
    end

    def own_to_create : ToCreateBlock?
      @to_create
    end

    def define_to_create(block : ToCreateBlock) : Nil
      @to_create = block
    end

    def constructor : ConstructorBlock?
      candidates = resolved_base_traits.map(&.definition.own_constructor) +
                   [@constructor] +
                   resolved_additional_traits.map(&.definition.own_constructor)
      candidates.reject(Nil).last?
    end

    def own_constructor : ConstructorBlock?
      @constructor
    end

    def define_constructor(block : ConstructorBlock) : Nil
      @constructor = block
    end

    def callbacks : Array(Callback)
      (resolved_base_traits.map(&.definition.own_callbacks) +
       [@callbacks] +
       resolved_additional_traits.map(&.definition.own_callbacks)).flatten
    end

    def own_callbacks : Array(Callback)
      @callbacks
    end

    def compile(klass : ActiveRecord::Base.class | Nil = nil) : Nil
      unless @compiled
        expand_enum_traits

        declarations.attributes(self)

        self.klass ||= klass
        defined_traits.each do |defined_trait|
          defined_trait.definition.klass ||= self.klass
          (@base_traits + @additional_traits).each do |trait_name|
            if (t = trait_for(trait_name))
              t.definition.define_trait(defined_trait)
            end
          end
        end

        @compiled = true
      end
    end

    def overridable : Nil
      @declarations.overridable
      reset_compilation
    end

    def inherit_traits(new_traits : Array(String)) : Nil
      @base_traits += new_traits.map(&.to_s)
      @attributes = nil
    end

    def append_traits(new_traits : Array(String)) : Nil
      @additional_traits += new_traits.map(&.to_s)
      @attributes = nil
    end

    def base_trait_names : Array(String)
      @base_traits
    end

    def additional_trait_names : Array(String)
      @additional_traits
    end

    def add_callback(callback : Callback) : Nil
      @callbacks << callback
    end

    def skip_create : Nil
      @to_create = ->(instance : ActiveRecord::Base) { nil }
    end

    def define_trait(trait : Trait) : Nil
      return if defined_traits.any? { |t| t.name == trait.name }
      @defined_traits << trait
    end

    def defined_traits_names : Array(String)
      @defined_traits.map(&.name)
    end

    def register_enum(enum_def : Enum) : Nil
      @registered_enums << enum_def
    end

    def before(*names : String | Symbol, &block : Proc(Nil)) : Nil
      callback(*names.map { |n| "before_#{n}" }, &block)
    end

    def before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
      callback(*names.map { |n| "before_#{n}" }, &block)
    end

    def before(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      callback(*names.map { |n| "before_#{n}" }, &block)
    end

    def after(*names : String | Symbol, &block : Proc(Nil)) : Nil
      callback(*names.map { |n| "after_#{n}" }, &block)
    end

    def after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
      callback(*names.map { |n| "after_#{n}" }, &block)
    end

    def after(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      callback(*names.map { |n| "after_#{n}" }, &block)
    end

    def callback(*names : String | Symbol, &block : Proc(Nil)) : Nil
      names.each { |name| add_callback(Callback.new(name.to_s, block)) }
    end

    def callback(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Nil)) : Nil
      names.each { |name| add_callback(Callback.new(name.to_s, block)) }
    end

    def callback(*names : String | Symbol, &block : Proc(ActiveRecord::Base, Evaluator, Nil)) : Nil
      names.each { |name| add_callback(Callback.new(name.to_s, block)) }
    end

    def reset_compilation : Nil
      @attributes = nil
      @compiled = false
    end

    # Копия для with_traits/modify.
    def copy : Definition
      copy = Definition.new(@name, @base_traits)
      copy.klass = @klass
      @declarations.to_a.each { |d| copy.declare_attribute(d) }
      copy.additional_traits = @additional_traits.dup
      copy.callbacks = @callbacks.dup
      copy.defined_traits = @defined_traits.dup
      copy.to_create_block = @to_create
      copy.constructor_block = @constructor
      copy.registered_enums = @registered_enums.dup
      copy.reset_compilation
      copy
    end

    protected def additional_traits=(v : Array(String))
      @additional_traits = v
    end

    protected def callbacks=(v : Array(Callback))
      @callbacks = v
    end

    protected def defined_traits=(v : Array(Trait))
      @defined_traits = v
    end

    protected def to_create_block=(v : ToCreateBlock?)
      @to_create = v
    end

    protected def constructor_block=(v : ConstructorBlock?)
      @constructor = v
    end

    protected def registered_enums=(v : Array(Enum))
      @registered_enums = v
    end

    private def resolved_base_traits : Array(Trait)
      @base_traits.map { |name| trait_by_name!(name) }
    end

    private def resolved_additional_traits : Array(Trait)
      # В отличие от базовых, KeyError для дополнительных трейтов не
      # дополняется именем определения (поведение гема 6.5.6).
      @additional_traits.map { |name| trait_for(name) || Internal.trait_by_name(name, @klass) }
    end

    private def trait_by_name!(name : String) : Trait
      trait_for(name) || Internal.trait_by_name(name, @klass)
    rescue ex : KeyError
      raise KeyError.new(
        %(#{ex.message} referenced within "#{@name}" definition))
    end

    def trait_for(name : String) : Trait?
      @defined_traits.find { |t| t.name == name }
    end

    private def aggregate_attributes : Array(AttributeList)
      compile
      lists = [] of AttributeList
      resolved_base_traits.each { |t| lists << t.definition.attributes }
      lists << @declarations.attributes(self)
      resolved_additional_traits.each { |t| lists << t.definition.attributes }
      lists
    end

    private def expand_enum_traits : Nil
      return if @expanded_enum_traits
      @registered_enums.each do |enum_def|
        enum_def.build_traits.each { |t| define_trait(t) }
      end
      @expanded_enum_traits = true
    end
  end

  class Trait
    getter name : String
    getter definition : Definition

    # Блок тела трейта выполняется на прокси вызывающего (см.
    # DefinitionProxy#trait / DSL#trait), поэтому конструктор без блока.
    def initialize(@name : String, uri_paths : Array(String)? = nil)
      @definition = Definition.new(@name, uri_paths: uri_paths)
    end

    def names : Array(String)
      [@name]
    end

    def klass : ActiveRecord::Base.class | Nil
      @definition.klass
    end

    def klass=(klass : ActiveRecord::Base.class | Nil)
      @definition.klass = klass
    end
  end
end
