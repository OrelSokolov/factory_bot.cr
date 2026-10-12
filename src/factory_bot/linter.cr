# Linter — порт factory_bot/linter.rb.

module FactoryBot
  class Linter
    class FactoryError
      def initialize(@wrapped_error : Exception, @factory : Factory,
                     @trait_name : String? = nil)
      end

      def message : String
        "* #{location} - #{@wrapped_error.message} (#{error_class_name})"
      end

      # Ruby-совместимое имя класса ошибки: `raise "..."` в Ruby даёт
      # RuntimeError, в Crystal — голый Exception.
      private def error_class_name : String
        @wrapped_error.class == Exception ? "RuntimeError" : @wrapped_error.class.to_s
      end

      def location : String
        if (t = @trait_name)
          "#{@factory.name}+#{t}"
        else
          @factory.name
        end
      end
    end

    @invalid_factories : Hash(Factory, Array(FactoryError))

    def initialize(factories : Array(Factory), @factory_strategy : String = "create",
                   @traits : Bool = false)
      @invalid_factories = calculate_invalid_factories(factories)
    end

    def lint! : Nil
      unless @invalid_factories.empty?
        lines = @invalid_factories.map { |_, exceptions| exceptions.map(&.message) }.flatten
        raise InvalidFactoryError.new(
          "The following factories are invalid:\n\n#{lines.join("\n")}")
      end
    end

    private def calculate_invalid_factories(factories) : Hash(Factory, Array(FactoryError))
      result = {} of Factory => Array(FactoryError)
      factories.each do |factory|
        errors = @traits ? lint_factory(factory) + lint_traits(factory) : lint_factory(factory)
        result[factory] = errors unless errors.empty?
      end
      result
    end

    private def lint_factory(factory : Factory) : Array(FactoryError)
      result = [] of FactoryError
      begin
        in_transaction do
          runner = FactoryRunner.new(factory.name, @factory_strategy,
                                     [] of String, {} of String => FBValue)
          runner.run
        end
      rescue ex
        result << FactoryError.new(ex, factory)
      end
      result
    end

    private def lint_traits(factory : Factory) : Array(FactoryError)
      result = [] of FactoryError
      factory.definition.defined_traits.each do |trait|
        begin
          in_transaction do
            runner = FactoryRunner.new(factory.name, @factory_strategy,
                                       [trait.name], {} of String => FBValue)
            runner.run
          end
        rescue ex
          result << FactoryError.new(ex, factory, trait.name)
        end
      end
      result
    end

    private def in_transaction(&) : Nil
      ActiveRecord::Base.transaction(requires_new: true) do
        yield
        raise ActiveRecord::Rollback.new
      end
    rescue ex : ActiveRecord::Rollback
      # нормальное завершение проверки
    end
  end
end
