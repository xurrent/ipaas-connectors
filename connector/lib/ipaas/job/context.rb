module IPaaS
  module Job
    class DiscardTriggerEvent < IPaaS::Error
    end

    class FailJob < IPaaS::Error
    end

    class FinishJob < IPaaS::Error
    end

    class RescheduleJob < IPaaS::Error
      attr_reader :reschedule_after

      def initialize(message, retry_after: 1.minute)
        super(message)
        @reschedule_after = Time.current + (retry_after || 0.seconds)
      end
    end

    module Context
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :log, :discard_trigger_event!, :fail_job!, :finish_job!, :backoff,
                :job_context_identifier, :job_context_identifier=

      mattr_accessor :extensions do
        []
      end

      mattr_accessor :inclusions do
        Set.new
      end

      class << self
        def extension(extension_class)
          extensions << extension_class
          inclusions.each do |inclusion|
            inclusion.send(:include, extension_class)
          end
        end

        # Ambient logger consulted by authored procs when no explicit per-instance logger is
        # set. Lets a host that shares these objects across concurrent requests route log()
        # into a per-request sink without mutating the shared objects. Reentrancy-safe.
        def with_ambient_logger(logger)
          # Fiber-local (Thread#[]): scopes the sink to the request's execution context, so
          # concurrent requests stay isolated whether the server runs them on separate threads
          # or multiplexes them as fibers on shared threads (a thread-local would leak across
          # fibers sharing a thread). Consistent with other Thread#[] execution state here.
          prev = Thread.current[:ipaas_authored_logger]
          Thread.current[:ipaas_authored_logger] = logger
          yield
        ensure
          Thread.current[:ipaas_authored_logger] = prev
        end

        def ambient_logger
          Thread.current[:ipaas_authored_logger]
        end
      end

      extend ActiveSupport::Concern

      included do
        include IPaaS::Job::Helpers

        @@inclusions << self
        attr_writer :logger

        def log(message, interpolation = nil)
          message = interpolate(message, interpolation)
          logger.info(message)
          nil
        end

        def discard_trigger_event!(message, interpolation = nil)
          message = interpolate(message, interpolation)
          logger.info(message)
          raise DiscardTriggerEvent, message
        end

        def fail_job!(message, interpolation = nil)
          message = interpolate(message, interpolation)
          logger.error(message)
          raise FailJob, message
        end

        def finish_job!(message = 'Runbook execution completed', interpolation = nil)
          message = interpolate(message, interpolation)
          logger.info(message)
          raise FinishJob, message
        end

        def backoff(message = 'Rescheduling as backoff was called.', interpolation = nil, retry_after: 1.minute)
          message = interpolate(message, interpolation)
          logger.info(message)
          raise RescheduleJob.new(message, retry_after: retry_after)
        end

        def job_context_identifier
          job_context_identifier_store&.job_context_identifier
        end

        def job_context_identifier=(identifier)
          value_to_store = identifier.presence
          return if job_context_identifier == value_to_store

          job_context_identifier_store&.store_job_context_identifier(value_to_store)
        end

        IPaaS::Job::Context.extensions.each do |extension|
          include extension
        end

        private

        # Precedence: explicit per-instance logger > ambient sink > process default. The ambient
        # logger is re-read each call so it is never stale-memoized, and falling back to the
        # default never populates @logger, so it cannot shadow an ambient logger installed later.
        def logger
          @logger || IPaaS::Job::Context.ambient_logger || IPaaS.default_logger
        end

        def interpolate(message, interpolation)
          return message unless interpolation

          message % interpolation.symbolize_keys
        end

        def job_context_identifier_store
          (trigger || action)&.runbook || test_job_context_store
        end

        def test_job_context_store
          return TestJobContextStore.new if is_a?(IPaaS::Connector::TriggerTemplate)

          @test_job_context_store ||= TestJobContextStore.new
        end
      end

      class TestJobContextStore
        def store_job_context_identifier(identifier)
          @job_context_identifier = identifier
        end

        attr_reader :job_context_identifier
      end
    end
  end
end
