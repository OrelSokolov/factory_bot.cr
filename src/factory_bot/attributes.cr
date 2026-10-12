# Attribute / Declaration / AttributeList — порты factory_bot/attribute.rb,
# attribute/*.rb, declaration.rb, declaration/*.rb, attribute_list.rb.

module FactoryBot
  # @api private
  abstract class Attribute
    getter name : String
    getter? ignored : Bool

    def initialize(@name : String, @ignored : Bool)
    end

    def association? : Bool
      false
    end

    def alias_for?(attr : String) : Bool
      FactoryBot.aliases_for(attr).includes?(@name)
    end

    # Блок вычисления значения для Evaluator (аналог to_proc).
    abstract def block : AttrBlock
  end

  class Attribute
    class Dynamic < Attribute
      @block : AttrBlock

      def initialize(name : String, ignored : Bool, block : AttrBlock)
        super(name, ignored)
        @block = block
      end

      def block : AttrBlock
        @block
      end
    end

    class Association < Attribute
      getter factory_name : String
      getter traits : Array(String)
      getter overrides : Hash(String, FBValue)

      def initialize(name : String, @factory_name : String, @traits : Array(String),
                     @overrides : Hash(String, FBValue))
        super(name, false)
      end

      def association? : Bool
        true
      end

      def block : AttrBlock
        factory_name = @factory_name
        traits = @traits
        overrides = @overrides
        ->(evaluator : Evaluator) : FBValue {
          evaluator.association(factory_name, traits, overrides)
        }
      end
    end

    class Sequence < Attribute
      getter sequence_name : String

      def initialize(name : String, @sequence_name : String, ignored : Bool)
        super(name, ignored)
      end

      def block : AttrBlock
        sequence_name = @sequence_name
        -> : FBValue { FactoryBot.generate(sequence_name) }
      end
    end
  end

  # --- Declarations -----------------------------------------------------------

  abstract class Declaration
    getter name : String
    getter? ignored : Bool

    def initialize(@name : String, @ignored : Bool)
    end

    def to_attributes(definition : Definition) : Array(Attribute)
      build(definition)
    end

    protected abstract def build(definition : Definition) : Array(Attribute)
  end

  class Declaration
    class Dynamic < Declaration
      @block : AttrBlock

      def initialize(name : String, ignored : Bool, block : AttrBlock)
        super(name, ignored)
        @block = block
      end

      def build(definition : Definition) : Array(Attribute)
        [Attribute::Dynamic.new(@name, @ignored, @block)] of Attribute
      end
    end

    class Association < Declaration
      getter factory_name : String
      getter traits : Array(String)
      getter overrides : Hash(String, FBValue)

      def initialize(name : String, factory_name : Object,
                     traits : Array(String), overrides : Hash(String, FBValue))
        super(name, false)
        @factory_name = factory_name.to_s
        @traits = traits
        @overrides = overrides
      end

      def build(definition : Definition) : Array(Attribute)
        [Attribute::Association.new(@name, @factory_name, @traits, @overrides)] of Attribute
      end
    end

    class Implicit < Declaration
      def initialize(name : String, @ignored : Bool)
        super(name, @ignored)
      end

      def build(definition : Definition) : Array(Attribute)
        if FactoryBot.factories.registered?(@name)
          [Attribute::Association.new(@name, @name,
            [] of String, {} of String => FBValue)] of Attribute
        elsif FactoryBot.sequences.registered?(@name) ||
              Internal.inline_sequences.any? { |s| s.has_name?(@name) }
          [Attribute::Sequence.new(@name, @name, @ignored)] of Attribute
        elsif definition.name == @name
          raise TraitDefinitionError.new("Self-referencing trait '#{@name}'")
        else
          definition.inherit_traits([@name])
          [] of Attribute
        end
      end
    end
  end

  # --- AttributeList ------------------------------------------------------------

  class AttributeList
    getter name : String?

    def initialize(@name : String? = nil, @attributes = [] of Attribute)
    end

    def define_attribute(attribute : Attribute) : Attribute
      ensure_attribute_not_self_referencing!(attribute)
      ensure_attribute_not_defined!(attribute)
      add_attribute(attribute)
    end

    def each(& : Attribute ->)
      @attributes.each { |a| yield a }
    end

    def to_a : Array(Attribute)
      @attributes
    end

    def names : Array(String)
      @attributes.map(&.name)
    end

    def associations : AttributeList
      AttributeList.new(@name, @attributes.select(&.association?))
    end

    def ignored : AttributeList
      AttributeList.new(@name, @attributes.select(&.ignored?))
    end

    def non_ignored : AttributeList
      AttributeList.new(@name, @attributes.reject(&.ignored?))
    end

    def apply_attributes(attributes_to_apply : Array(Attribute)) : Nil
      attributes_to_apply.each { |attribute| add_attribute(attribute) }
    end

    private def add_attribute(attribute : Attribute) : Attribute
      @attributes << attribute
      attribute
    end

    private def ensure_attribute_not_defined!(attribute : Attribute) : Nil
      if names.includes?(attribute.name)
        raise AttributeDefinitionError.new(
          "Attribute already defined: #{attribute.name}")
      end
    end

    private def ensure_attribute_not_self_referencing!(attribute : Attribute) : Nil
      if attribute.association? && @name
        assoc = attribute.as(Attribute::Association)
        if assoc.factory_name == @name
          raise AssociationDefinitionError.new(
            "Self-referencing association '#{attribute.name}' in '#{@name}'")
        end
      end
    end
  end

  # --- DeclarationList --------------------------------------------------------

  class DeclarationList
    getter name : String?

    def initialize(@name : String?)
      @declarations = [] of Declaration
      @overridable = false
    end

    def declare_attribute(declaration : Declaration) : Nil
      if @overridable
        @declarations.reject! { |d| d.name == declaration.name }
      end
      @declarations << declaration
    end

    def overridable : Nil
      @overridable = true
    end

    def to_a : Array(Declaration)
      @declarations
    end

    # Разворачивает декларации в атрибуты (Implicit разрешает ассоциации
    # по реестрам и наследует трейты). Как в оригинале — через
    # define_attribute (проверки дубликата и самореференса).
    def attributes(definition : Definition) : AttributeList
      list = AttributeList.new(@name)
      @declarations.each do |declaration|
        declaration.to_attributes(definition).each { |attribute| list.define_attribute(attribute) }
      end
      list
    end
  end
end
