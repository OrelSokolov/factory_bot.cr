# Ошибки — 1:1 к factory_bot/errors.rb (KeyError/ArgumentError/NoMethodError
# используются нативные).

module FactoryBot
  # Raised when a factory is defined that attempts to instantiate itself.
  class AssociationDefinitionError < Exception
  end

  # Raised when a trait is defined that references itself.
  class TraitDefinitionError < Exception
  end

  # Raised when a callback is defined that has an invalid name
  class InvalidCallbackNameError < Exception
  end

  # Raised when a factory is defined with the same name as a
  # previously-defined factory.
  class DuplicateDefinitionError < Exception
  end

  # Raised when attempting to register a sequence from a dynamic attribute block
  class SequenceAbuseError < Exception
  end

  # Raised when defining an attribute twice in the same factory
  class AttributeDefinitionError < Exception
  end

  # Raised when attempting to pass a block to an association definition
  class AssociationDefinitionError < Exception
  end

  # Raised when a method is defined in a factory or trait with arguments
  class MethodDefinitionError < Exception
  end

  # Raised when any factory is considered invalid
  class InvalidFactoryError < Exception
  end
end
