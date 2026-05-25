module IPaaS
  module Job
    module Humanize
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :humanize_field_name

      class << self
        # camelCase -> space, underscores -> space, then Title Case.
        # Keeps consecutive capitals together (e.g. sourceID -> Source ID).
        def humanize_field_name(name)
          name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2')
              .gsub(/([a-z\d])([A-Z])/, '\1 \2')
              .tr('_', ' ')
              .strip
              .split(/\s+/)
              .map { |w| w == w.upcase ? w : w.capitalize }
              .join(' ')
        end
      end
    end
  end
end
