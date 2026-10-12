# Registry — 1:1 к factory_bot/registry.rb (+ Decorator::
# DisallowsDuplicatesRegistry ввиду флага duplicates_allowed; конструктор
# хранит копию для Modification-семантики не требуется).

module FactoryBot
  class Registry(T)
    getter name : String

    def initialize(@name : String, @duplicates_allowed = true)
      @items = {} of String => T
    end

    def clear : Nil
      @items.clear
    end

    def each(& : T ->) : Nil
      @items.values.each { |item| yield item }
    end

    def to_a : Array(T)
      @items.values
    end

    def size : Int32
      @items.size
    end

    def find(name : String | Symbol) : T
      key = name.to_s
      @items.fetch(key) do
        raise KeyError.new(%(#{@name} not registered: "#{key}"))
      end
    end

    def register(name : String | Symbol, item : T) : T
      key = name.to_s
      if !@duplicates_allowed && @items.has_key?(key)
        raise DuplicateDefinitionError.new("#{@name} already registered: #{key}")
      end
      @items[key] = item
      item
    end

    def registered?(name : String | Symbol) : Bool
      @items.has_key?(name.to_s)
    end
  end
end

module FactoryBot
  # Отдельное хранилище дефолтных алиасов (class_property в общем модуле
  # конфликтовал бы с methods-синтаксисом).
  module AliasesStorage
    class_property aliases : Array({Regex, String}) = [
      {/(.+)_id/, "\\1"},
      {/(.*)/, "\\1_id"},
    ]
  end
end
