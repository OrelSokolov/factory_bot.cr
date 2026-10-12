# factory_bot_cr — 1:1 порт factory_bot 6.5.6 на Crystal поверх active_record_cr.
#
# Oracle: oracle/src — вендорен оригинальный гем; oracle/cases.rb снимает
# expected.yml с настоящего factory_bot (AR 8.1.4 + SQLite in-memory);
# spec/oracle_spec.cr обязан воспроизвести каждый кейс на PG.
#
# Ключевые механики порта (Crystal 1.21):
#   * DSL-блоки (`FactoryBot.define`, `factory/trait/transient do ... end`)
#     идут некапчуренными и раскрываются через `with proxy yield` —
#     неявные вызовы внутри биндятся на прокси (аналог instance_eval).
#   * Ленивые блоки (динамические атрибуты, sequence, callbacks,
#     initialize_with, to_create) капчурятся только на прямых вызовах
#     реальных def-методов — переадресация блока через method_missing
#     в капчуренный контекст в Crystal невозможна (yield-only).
#   * Сахар атрибутов (`email { |e| ... }`) диспетчеризуется method_missing
#     на DefinitionProxy: макрос генерирует перегрузку def под форму вызова
#     (блок 0/1-арности → Proc-ограничение; без блока → *args/**nargs).
#   * Чтение атрибутов evaluator-ом — method_missing на Evaluator.
# Отклонения от Ruby — см. PLAN.md.

require "active_record_cr"

module FactoryBot
  VERSION = "6.5.6"

  # Значения атрибутов/оврайдов. Int32 нормализуется в Int64 при чтении
  # (таблицы active_record_cr декодируют целые как Int64).
  alias FBValue = Nil | Bool | Int32 | Int64 | Float64 | String | Symbol |
                  Time | JSON::Any | ActiveRecord::Base

  # Продукт стратегии: объект записи (build/create/stub) или хэш
  # (attributes_for); Null-стратегия возвращает nil.
  alias Product = ActiveRecord::Base | Hash(String, FBValue)

  # Ленивый блок атрибута: без параметра или с evaluator-ом.
  alias AttrBlock = Proc(FBValue) | Proc(Evaluator, FBValue)

  # Блок to_create: (instance) либо (instance, evaluator).
  alias ToCreateBlock = Proc(ActiveRecord::Base, Nil) |
                        Proc(ActiveRecord::Base, Evaluator, Nil)

  # Блок конструктора (initialize_with): получает evaluator.
  alias ConstructorBlock = Proc(Evaluator, ActiveRecord::Base)

  # Значения опций фабрик/ассоциаций (parent/class/aliases/traits и
  # ovрайды в hash-форме method_missing).
  alias OptValue = Nil | Bool | Int32 | Int64 | Float64 | String | Symbol |
                   Time | JSON::Any | ActiveRecord::Base |
                   ActiveRecord::Base.class | Array(String) | Array(Symbol)

  # Блок callback-а: 0/1/2 параметра (instance[, evaluator]).
  alias CallbackBlock = Proc(Nil) |
                        Proc(ActiveRecord::Base, Nil) |
                        Proc(ActiveRecord::Base, Evaluator, Nil)
end

require "./factory_bot/errors"
require "./factory_bot/registry"
require "./factory_bot/sequence"
require "./factory_bot/callback"
require "./factory_bot/attributes"
require "./factory_bot/definition"
require "./factory_bot/definition_proxy"
require "./factory_bot/evaluator"
require "./factory_bot/attribute_assigner"
require "./factory_bot/evaluation"
require "./factory_bot/strategy"
require "./factory_bot/factory"
require "./factory_bot/enum"
require "./factory_bot/linter"
require "./factory_bot/internal"
require "./factory_bot/syntax"

# Фолбэки класс-методов Base: кодоген определяет их в каждой модели,
# виртуальный диспетч нужен для вызовов через переменную Base.class
# (AttributeAssigner/Strategy::Stub работают с произвольным klass).
class ActiveRecord::Base
  def self.__column_names : Array(String)
    [] of String
  end

  # Обход кодеген-бага Crystal 1.21 (см. PLAN.md): вызов `save!` из
  # Proc(Base) через виртуальный диспетч ломает nested-closure в
  # Base#save (saved-флаг не materialизуется). Поколенчески сгенерирован-
  # ный на моделях `__fb_save!` даёт self статического типа модели и
  # работает; дефолтный to_create зовёт именно его.
  def __fb_save! : Bool
    raise "FactoryBot: cannot save a bare ActiveRecord::Base"
  end

  def __fb_save(validate : Bool = true) : Bool
    raise "FactoryBot: cannot save a bare ActiveRecord::Base"
  end

  def self.__column_defaults : Hash(String, ActiveRecord::Value)
    {} of String => ActiveRecord::Value
  end

  def self.table_name : String
    raise ArgumentError.new("FactoryBot: bare ActiveRecord::Base has no table")
  end

  def self.primary_key : String
    "id"
  end

  # Фолбэк для вызовов через статический тип Base (у моделей метод
  # генерируется кодогеном из schema.yml): пустой набор атрибутов.
  def attributes : Hash(String, ActiveRecord::Value)
    {} of String => ActiveRecord::Value
  end

  def assign_attributes(values : Hash(String, ActiveRecord::Value)) : Nil
    values.each do |name, _value|
      raise ArgumentError.new("unknown attribute #{name} for #{self.class}")
    end
  end

  def [](name : String) : ActiveRecord::Value
    raise ArgumentError.new("unknown attribute #{name} for #{self.class}")
  end
end

module FactoryBot
  # Runtime-разрешение имени класса по справочнику моделей
  # (замена Ruby `constantize`; заполняется на macro finished,
  # когда все модели уже зарегистрированы через macro inherited).
  macro finished
    def self.__constantize(name : String) : ActiveRecord::Base.class
      case name
      {% for m in ActiveRecord::MODELS %}
        {% unless m.abstract? %}
      when {{ m.name.stringify }} then {{ m }}.as(ActiveRecord::Base.class)
        {% end %}
      {% end %}
      else
        raise ArgumentError.new("uninitialized constant #{name}")
      end
    end

    # Обход кодеген-бага (см. класс Base): переопределение на модели даёт
    # вызову save! статический тип self — как прямому вызову.
    {% for m in ActiveRecord::MODELS %}
      {% unless m.abstract? %}
        class ::{{ m.stringify.id }}
          def __fb_save! : Bool
            save!
          end

          def __fb_save(validate : Bool = true) : Bool
            save(validate)
          end
        end
      {% end %}
    {% end %}
  end

  # --- Module-level state (Configuration) -----------------------------------

  def self.aliases : Array({Regex, String})
    AliasesStorage.aliases
  end

  def self.aliases=(vals : Array({Regex, String}))
    AliasesStorage.aliases = vals
  end

  def self.aliases_for(attribute : String) : Array(String)
    out = [] of String
    aliases.each do |(pattern, replace)|
      out << attribute.sub(pattern, replace) if pattern.matches?(attribute)
    end
    out << attribute
    out
  end

  class_property? use_parent_strategy = true
  class_property? automatically_define_enum_traits = false
  class_property sequence_setting_timeout = 0.5

  # --- Регистры --------------------------------------------------------------

  def self.factories : Registry(Factory)
    Internal.factories
  end

  def self.sequences : Registry(Sequence)
    Internal.sequences
  end

  def self.register_factory(factory : Factory)
    Internal.register_factory(factory)
  end

  def self.register_sequence(sequence : Sequence)
    Internal.register_sequence(sequence)
  end

  def self.register_trait(trait : Trait)
    Internal.register_trait(trait)
  end

  def self.register_strategy(name : String | Symbol, strategy : Strategy::Base)
    Internal.register_strategy(name.to_s, strategy)
  end

  # --- Ошибки значений -------------------------------------------------------

  def self.__normalize(value) : FBValue
    case value
    when FBValue then value
    else
      raise ArgumentError.new(
        "unsupported factory value type: #{value.class}")
    end
  end

  # Int32 → Int64, Symbol остаётся Symbol (на запись в колонку приводится
  # к String в AttributeAssigner).
  def self.__normalize_int(value : FBValue) : FBValue
    value.is_a?(Int32) ? value.to_i64 : value
  end
end
