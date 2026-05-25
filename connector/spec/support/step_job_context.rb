module IPaaS
  module Job
    Step = Struct.new(:output)

    module StepContext
      cattr_accessor :outputs do
        {}
      end
      extend ActiveSupport::Concern
      included do
        def step(uuid)
          Step.new(outputs[uuid] || {})
        end

        def step_output(uuid, data)
          outputs[uuid] = data
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::StepContext)
