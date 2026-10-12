# Enum — порт factory_bot/enum.rb (traits_for_enum).
# Автоматическая регистрация enum-ов модели (values = nil) не поддержана:
# в Crystal нет runtime-интерроспекции enum-ов модели.

module FactoryBot
  class Enum
    def initialize(@attribute_name : String,
                   @values : Array(String) | Hash(String, FBValue)?)
    end

    def build_traits : Array(Trait)
      enum_values.map do |trait_name, value|
        build_trait(trait_name, @attribute_name, value || trait_name)
      end
    end

    private def enum_values : Array({String, FBValue?})
      case (values = @values)
      when Array(String)
        values.map { |v| {v, nil.as(FBValue?)} }
      when Hash(String, FBValue)
        values.map { |k, v| {k, v.as(FBValue?)} }
      else
        raise ArgumentError.new(
          "traits_for_enum: values are required (automatic model enum " \
          "registration is not supported in Crystal)")
      end
    end

    private def build_trait(trait_name : String, attribute_name : String,
                            value : FBValue?) : Trait
      trait = Trait.new(trait_name)
      proxy = DefinitionProxy.new(trait.definition)
      value_c = value # замыкание
      proxy.add_attribute(attribute_name) { value_c }
      trait
    end
  end
end
