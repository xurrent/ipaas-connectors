module IPaaS
  module Job
    module Ruby
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :ruby_eval, :output

      def ruby_eval(code, params)
        with_input_stack(self, params) do
          with_output_stack(self) do
            on_invalid = ->(msg) { raise("Ruby code is invalid: #{msg}") }
            proc_helper = IPaaS::Connector::Common::ProcHelper.new(self, code, on_invalid: on_invalid)
            proc_helper.execute

            output
          end
        end
      end

      private

      def ruby_eval_input_stack
        @ruby_eval_input_stack ||= []
      end

      def ruby_eval_output_stack
        @ruby_eval_output_stack ||= []
      end

      def with_input_stack(context, params)
        input_stack = ruby_eval_input_stack
        input_stack << (params || {}).with_indifferent_access

        original_input_method = context.method(:input) if context.respond_to?(:input)
        context.define_singleton_method(:input) { input_stack.last }

        yield
      ensure
        input_stack.pop
        restore_method(context, :input, original_input_method)
      end

      def with_output_stack(context)
        output_stack = ruby_eval_output_stack
        output_stack << {}.with_indifferent_access

        original_output_method = context.method(:output) if context.respond_to?(:output)
        context.define_singleton_method(:output) { output_stack.last }

        yield
      ensure
        output_stack.pop
        restore_method(context, :output, original_output_method)
      end

      def restore_method(context, method_name, original_method)
        if original_method
          context.define_singleton_method(method_name, original_method)
        else
          context.singleton_class.undef_method(method_name)
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Ruby)
