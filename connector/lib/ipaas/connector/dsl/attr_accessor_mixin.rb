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
          class_attribute :default_blocks, instance_accessor: false, default: {}

          def self.attr_accessor(*keys, &block)
            # pass all keys to the original `attr_accessor` mixin
            result = super(*keys)
            self.default_blocks = default_blocks.merge(keys.index_with { block })
            keys.each do |key|
              # override the getter method to accept a value `t.foo 'My Foo'`
              define_method(key) do |value = UNDEFINED|
                if value == UNDEFINED
                  stored_or_default(key)
                else
                  # when a value is given, call the setter method from the original `attr_accessor` mixin
                  self.send(:"#{key}=", value)
                end
              end
            end
            result
          end
        end

        # Reading an unset accessor stores its default, a write a sealed object cannot take, so sealing
        # stores them all first.
        def store_defaults
          self.class.default_blocks.each_key { |key| stored_or_default(key) }
        end

        private

        def stored_or_default(key)
          ivar = :"@#{key}"
          unless instance_variable_defined?(ivar)
            # first time so generate a default value or fallback to `nil`
            block = self.class.default_blocks[key]
            instance_variable_set(ivar, block ? self.instance_exec(&block) : nil)
          end
          instance_variable_get(ivar)
        end
      end
    end
  end
end
