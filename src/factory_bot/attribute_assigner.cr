# AttributeAssigner — порт factory_bot/attribute_assigner.rb.
#
# Отклонения: присваивание значений идёт через assign_attributes +
# FK-эвристику (значение ActiveRecord::Base + колонка "<name>_id" →
# внешний ключ, "<name>_type" → полиморфный тип) вместо public_send.

module FactoryBot
  class AttributeAssigner
    @attribute_names_assigned = [] of String
    @built_instance : ActiveRecord::Base?

    def initialize(@evaluator : Evaluator, @build_class : ActiveRecord::Base.class,
                   @instance_builder : ConstructorBlock,
                   @attribute_list : AttributeList)
    end

    def object : ActiveRecord::Base
      instance = build_class_instance
      @evaluator.instance = instance
      attributes_to_set_on_instance.each do |attribute|
        __assign(instance, attribute, @evaluator.__read(attribute))
        @attribute_names_assigned << attribute
      end
      instance
    end

    def hash : Hash(String, FBValue)
      result = {} of String => FBValue
      attributes_to_set_on_hash.each do |attribute|
        result[attribute] = @evaluator.__read(attribute)
      end
      result
    end

    private def build_class_instance : ActiveRecord::Base
      @built_instance ||= begin
        @evaluator.__start_tracking
        instance = @instance_builder.call(@evaluator)
        @evaluator.__stop_tracking
        instance
      end
    end

    private def attributes_to_set_on_instance : Array(String)
      (attribute_names_to_assign - @attribute_names_assigned -
       @evaluator.__invoked_methods).uniq
    end

    private def attributes_to_set_on_hash : Array(String)
      attribute_names_to_assign - association_names
    end

    # Кандидаты: не-transient атрибуты + оврайды; минус transient,
    # реинтродуцированные оврайдами, минус прерываемые алиасами.
    private def attribute_names_to_assign : Array(String)
      assignment_candidates = non_ignored_attribute_names + @evaluator.__override_names
      assignment_candidates - ignored_attribute_names -
        attribute_names_overriden_by_alias
    end

    private def attribute_names : Array(String)
      @attribute_list.names
    end

    private def non_ignored_attribute_names : Array(String)
      @attribute_list.non_ignored.names
    end

    private def ignored_attribute_names : Array(String)
      @attribute_list.ignored.names
    end

    private def association_names : Array(String)
      @attribute_list.associations.names
    end

    private def attribute_names_overriden_by_alias : Array(String)
      result = [] of String
      non_ignored_attribute_names.each do |name|
        @evaluator.__override_names.each do |override|
          result << name if ignorable_alias?(name, override)
        end
      end
      result
    end

    private def ignorable_alias?(attribute_name : String, override : String) : Bool
      return false unless FactoryBot.aliases_for(override).includes?(attribute_name)
      return true if override_interrupts_association?(attribute_name, override)
      !attribute_names.includes?(override)
    end

    private def override_interrupts_association?(attribute_name : String, override : String) : Bool
      (association_names.includes?(attribute_name) || association_names.includes?(override)) &&
        attribute_name != override
    end

    private def __assign(record : ActiveRecord::Base, name : String, value : FBValue) : Nil
      columns = record.class.__column_names
      if value.is_a?(ActiveRecord::Base) && columns.includes?("#{name}_id")
        # Аналог Rails `record.user = value`: кроме FK объект сохраняется
        # в association target (inverse-of cache active_record_cr), чтобы
        # геттер возвращал несохранённую ассоциацию из build-стратегии.
        record.__cache_assoc(name, value)
        record.assign_attributes({"#{name}_id" => value.id})
        if columns.includes?("#{name}_type")
          record.assign_attributes({"#{name}_type" => value.class.to_s})
        end
      else
        record.assign_attributes({name => __ar_value(value)})
      end
    end

    private def __ar_value(value : FBValue) : ActiveRecord::Value
      case value
      when Int32 then value.to_i64
      when Symbol then value.to_s
      when ActiveRecord::Base
        raise ArgumentError.new(
          "unknown association attribute for #{value.class} value")
      else value
      end
    end
  end
end
