module IPaaS
  module Connector
    module Common
      class Helpers
        attr_accessor :proc_helpers_by_name, :parent_helpers, :errors

        def initialize(context = nil, parent_helpers: nil)
          @context = context
          @parent_helpers = parent_helpers
          self.proc_helpers_by_name = {}.with_indifferent_access
        end

        def copy_for(new_context)
          new_parent_helpers = parent_helpers&.copy_for(new_context)
          Helpers.new(new_context, parent_helpers: new_parent_helpers).tap do |new_helpers|
            proc_helpers_by_name.each do |name, proc_helper|
              new_helpers.define_helper(name, &proc_helper.procedure)
            end
          end
        end

        def copy_to(new_context)
          new_helpers = copy_for(new_context)
          new_context.define_singleton_method(:helpers) { new_helpers }
        end

        def valid?
          self.errors = []
          proc_helpers_by_name.map do |name, proc_helper|
            proc_helper.valid?.tap do |valid|
              self.errors << [name, proc_helper.errors] unless valid
            end
          end.detect(&:!).nil?
        end

        def define_helper(name, &block)
          proc_helpers_by_name[name] = IPaaS::Connector::Common::ProcHelper.new(@context, block)
        end

        def method_missing(method_name, *params, **, &block)
          if proc_helpers_by_name.key?(method_name)
            return proc_helpers_by_name[method_name].execute(*params, **, &block)
          end

          raise NoMethodError, "Missing helper method '#{method_name}'." unless parent_helpers
          parent_helpers.send(method_name, *params, **, &block)
        end

        def respond_to_missing?(method_name, include_private = false)
          proc_helpers_by_name.key?(method_name) || super || parent_helpers.respond_to?(method_name)
        end
      end
    end
  end
end
