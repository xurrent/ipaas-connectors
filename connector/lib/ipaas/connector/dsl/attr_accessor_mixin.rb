module IPaaS
  module Connector
    module Dsl
      # Enhances `attr_accessor` so that attributes can be set without using the equals (=) sign.
      #
      # Default values can be set using a code block that is evaluated on the instance when no value has been set.
      #
      # Example with multiple attributes:
      #   class Test
      #     include IPaaS::Connector::Model
      #     attr_accessor :foo, :bar
      #   end
      #   test = Test.new.tap do |t|
      #     t.foo 'My Foo'
      #     t.bar 42
      #   end
      #
      #   test.foo
      #   => "My Foo"
      #   test.bar
      #   => 42
      #
      # Example with default value based on value of another instance variable:
      #   class Test
      #     include IPaaS::Connector::Model
      #     attr_accessor :car
      #     attr_accessor :cars do car ? [car] : [] end
      #   end
      #
      #   Test.new.tap do |t|
      #     t.cars
      #     => []
      #   end
      #   Test.new.tap do |t|
      #     t.car 'Kit'
      #     t.cars
      #     => ['Kit']
      #   end
      module AttrAccessorMixin
        UNDEFINED = Object.new.freeze
        extend ActiveSupport::Concern

        included do
          def self.attr_accessor(*keys, &block)
            # pass all keys to the original `attr_accessor` mixin
            result = super(*keys)
            keys.each do |key|
              # override the getter method to accept a value `t.foo 'My Foo'`
              define_method(key) do |value = UNDEFINED|
                if value == UNDEFINED
                  # no value provided, retrieve the current value
                  ivar = :"@#{key}"
                  unless instance_variable_defined?(ivar)
                    # first time so generate a default value or fallback to `nil`
                    resolved_default_value = block ? self.instance_exec(&block) : nil
                    instance_variable_set(ivar, resolved_default_value)
                  end
                  instance_variable_get(ivar)
                else
                  # when a value is given, call the setter method from the original `attr_accessor` mixin
                  self.send(:"#{key}=", value)
                end
              end
            end
            result
          end
        end
      end
    end
  end
end
