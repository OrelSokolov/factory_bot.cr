# Callback — порт factory_bot/callback.rb.
#
# Отклонение: колбэки, которым Ruby передаёт nil-инстанс
# (before_build/before_all) или хэш (attributes_for), получают
# заглушку ActiveRecord::Base.new / хэш опускается — nilable-параметры
# в Proc-типах лишили бы пользовательский код `|u| u.name` типов.

module FactoryBot
  class Callback
    getter name : String

    def initialize(@name : String, @block : CallbackBlock)
    end

    def run(instance : Product?, evaluator : Evaluator) : Nil
      inst = instance.as?(ActiveRecord::Base) || BLANK_INSTANCE
      if (b0 = @block.as?(Proc(Nil)))
        b0.call
      elsif (b1 = @block.as?(Proc(ActiveRecord::Base, Nil)))
        b1.call(inst)
      else
        @block.as(Proc(ActiveRecord::Base, Evaluator, Nil)).call(inst, evaluator)
      end
    end

    private BLANK_INSTANCE = ActiveRecord::Base.new
  end
end
