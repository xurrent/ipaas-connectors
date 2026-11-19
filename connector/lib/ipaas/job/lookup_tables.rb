module IPaaS
  module Job
    module LookupTables
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      CONNECTOR_UUID = '01a19c65-6232-71c9-842a-1d22c682e939'.freeze
      FIXED_FIELDS = IPaaS.make_shareable([:table, :columns])
      FIXED_TABLE = 'A Lookup Tables connection needs a fixed table name'.freeze
      MAX_AT_MOST = 100_000
      AT_MOST = 'At most must be a whole number from 1 to 100,000'.freeze
      BLANK = /\A[ \t\r\n]*\z/

      proc_safe :lookup_table_add_entry, :lookup_table_lookup_entry, :lookup_table_search_page,
                :lookup_table_get_all_page, :lookup_table_update_entry, :lookup_table_delete_entry,
                :lookup_table_truncate, :lookup_table_mapped_keys

      included do
        def self.lookup_tables_for(_instance)
          IPaaS::Job::MemoryLookupTables.new
        end
      end

      def self.fixed_table_refusal(connection)
        return unless connection.connector&.uuid == CONNECTOR_UUID

        refused = Array(connection.config_mapping).any? do |mapping|
          FIXED_FIELDS.include?(mapping.field_id) &&
            [mapping.proc, mapping.variable, mapping.runbook_variable, mapping.nested].any?(&:present?)
        end
        FIXED_TABLE if refused
      end

      def lookup_table_add_entry(table_uuid, values)
        lookup_table_access.add_entry(table_uuid, values)
      end

      def lookup_table_lookup_entry(table_uuid, match)
        lookup_table_access.lookup_entry(table_uuid, match)
      end

      def lookup_table_search_page(table_uuid, match, at_most: nil)
        lookup_table_page(lookup_table_at_most(at_most)) do |after, limit|
          lookup_table_access.search_page(table_uuid, match, after: after, limit: limit)
        end
      end

      def lookup_table_get_all_page(table_uuid)
        lookup_table_page(nil) { |after, _limit| lookup_table_access.get_all_page(table_uuid, after: after) }
      end

      def lookup_table_update_entry(table_uuid, entry_id, values, ignore_if_not_found: nil)
        lookup_table_access.update_entry(table_uuid, entry_id, values, ignore_missing: ignore_if_not_found || false)
      end

      def lookup_table_delete_entry(table_uuid, entry_id, ignore_if_not_found: nil)
        lookup_table_access.delete_entry(table_uuid, entry_id, ignore_missing: ignore_if_not_found != false)
      end

      def lookup_table_truncate(table_uuid)
        lookup_table_access.truncate(table_uuid)
      end

      def lookup_table_mapped_keys(field_id)
        mapping = Array(try(:input_mapping)).detect { |candidate| candidate.field_id.to_s == field_id.to_s }
        Array(mapping&.nested).map { |nested| nested.field_id.to_s }
      end

      private

      def lookup_table_access
        self.class.lookup_tables_for(self)
      end

      def lookup_table_at_most(value)
        return if value.nil? || (value.is_a?(String) && value.match?(BLANK))

        number = lookup_table_whole_number(value)
        raise IPaaS::Job::FailJob, AT_MOST unless number&.between?(1, MAX_AT_MOST)

        number
      end

      def lookup_table_whole_number(value)
        case value
        when Integer then value
        when Float, BigDecimal, Rational then value.to_i if value.finite? && (value % 1) == 0
        when String then value.to_i if value.match?(/\A\d+\z/)
        end
      end

      def lookup_table_page(at_most)
        after = try(:iteration_state_value, :after)
        returned = try(:iteration_state_value, :returned).to_i
        left = at_most && [at_most - returned, 0].max
        page = yield(after, left)
        self.iteration_state_value = lookup_table_next_state(page, left, returned)
        page.slice(:entries, :columns) unless after && page[:entries].empty?
      end

      def lookup_table_next_state(page, left, returned)
        return unless page[:more] && (left.nil? || left > page[:entries].size)

        { after: page[:entries].last[:entry_id], returned: returned + page[:entries].size }
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::LookupTables)
