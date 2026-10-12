# Evaluation / CallbacksObserver — порты factory_bot/evaluation.rb и
# factory_bot/callbacks_observer.rb.

module FactoryBot
  class Evaluation
    def initialize(@evaluator : Evaluator, @attribute_assigner : AttributeAssigner,
                   @to_create : ToCreateBlock, @observer : CallbacksObserver)
    end

    def object : ActiveRecord::Base
      @attribute_assigner.object
    end

    def hash : Hash(String, FBValue)
      @attribute_assigner.hash
    end

    def create(result_instance : ActiveRecord::Base) : Nil
      if (b1 = @to_create.as?(Proc(ActiveRecord::Base, Nil)))
        b1.call(result_instance)
      else
        b2 = @to_create.as(Proc(ActiveRecord::Base, Evaluator, Nil))
        b2.call(result_instance, @evaluator)
      end
    end

    def notify(name : String, result_instance : Product?) : Nil
      @observer.update(name, result_instance)
    end
  end

  class CallbacksObserver
    def initialize(@callbacks : Array(Callback), @evaluator : Evaluator)
      @completed = [] of {UInt64, UInt64}
    end

    def update(name : String, result_instance : Product?) : Nil
      @callbacks.each do |callback|
        next unless callback.name == name
        key = {result_instance.object_id, callback.object_id}
        next if @completed.includes?(key)
        callback.run(result_instance, @evaluator)
        @completed << key
      end
    end
  end
end
