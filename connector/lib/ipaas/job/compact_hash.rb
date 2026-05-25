module IPaaS
  module Job
    module CompactHash
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :compact_hash

      class << self
        def compact_hash(hash)
          return nil if hash.blank?

          hash.each_with_object({}) do |(k, v), result|
            result[k.to_s] = v unless blank_value?(v)
          end.presence
        end

        private

        def blank_value?(value)
          value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end
      end
    end
  end
end
