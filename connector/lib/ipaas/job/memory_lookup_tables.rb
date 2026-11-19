module IPaaS
  module Job
    class MemoryLookupTables
      PAGE_SIZE = 100
      MUTEX = Monitor.new.freeze
      TABLES = {} # rubocop:disable Style/MutableConstant

      class << self
        def define(table_uuid, name:, columns:)
          MUTEX.synchronize do
            TABLES[table_uuid] = { name: name, columns: columns.map { |column| column.transform_keys(&:to_sym) },
                                   entries: [], issued: 0, }
          end
        end

        def entries(table_uuid)
          MUTEX.synchronize { TABLES.fetch(table_uuid)[:entries].map(&:dup) }
        end

        def reset!
          MUTEX.synchronize { TABLES.clear }
        end
      end

      def add_entry(table_uuid, values)
        with_table(table_uuid) do |table|
          entry = { entry_id: format('00000000-0000-7000-8000-%012x', table[:issued] += 1), values: stringify(values) }
          table[:entries] << entry
          output(table, entry)
        end
      end

      def lookup_entry(table_uuid, match)
        with_table(table_uuid) do |table|
          entry = matching(table, match).first
          raise IPaaS::Job::FailJob, %(No entry in "#{table[:name]}" matches) unless entry

          output(table, entry)
        end
      end

      def search_page(table_uuid, match, after: nil, limit: nil)
        with_table(table_uuid) { |table| page(table, matching(table, match), after, [limit, PAGE_SIZE].compact.min) }
      end

      def get_all_page(table_uuid, after: nil)
        with_table(table_uuid) { |table| page(table, table[:entries], after, PAGE_SIZE) }
      end

      def update_entry(table_uuid, entry_id, values, ignore_missing:)
        with_table(table_uuid) do |table|
          entry = find(table, entry_id)
          next missing(table, entry_id, ignore_missing) unless entry

          entry[:values] = entry[:values].merge(stringify(values))
          output(table, entry)
        end
      end

      def delete_entry(table_uuid, entry_id, ignore_missing:)
        with_table(table_uuid) do |table|
          entry = find(table, entry_id)
          next table[:entries].delete(entry)[:entry_id] if entry
          next if ignore_missing

          raise IPaaS::Job::FailJob, not_found(table, entry_id)
        end
      end

      def truncate(table_uuid)
        with_table(table_uuid) { |table| table[:entries].size.tap { table[:entries] = [] } }
      end

      private

      def with_table(table_uuid)
        MUTEX.synchronize do
          table = TABLES[table_uuid]
          raise IPaaS::Job::FailJob, %(Table "#{table_uuid}" not found) unless table

          yield table
        end
      end

      def find(table, entry_id)
        table[:entries].detect { |candidate| candidate[:entry_id] == entry_id }
      end

      def stringify(values)
        values.to_h.transform_keys(&:to_s)
      end

      def matching(table, match)
        conditions = stringify(match)
        table[:entries].select do |entry|
          conditions.all? { |key, value| (value.is_a?(Array) ? value : [value]).compact.include?(entry[:values][key]) }
        end
      end

      def page(table, entries, after, limit)
        later = entries.sort_by { |entry| entry[:entry_id] }.select { |entry| after.nil? || entry[:entry_id] > after }
        { entries: later.first(limit).map { |entry| output(table, entry).except(:columns) },
          columns: columns(table), more: later.size > limit, }
      end

      def output(table, entry)
        { entry_id: entry[:entry_id],
          entry: table[:columns].to_h { |column| [column[:key], entry[:values][column[:key]]] },
          columns: columns(table), }
      end

      def columns(table)
        table[:columns].map { |column| { column: column[:key], label: column[:label] } }
      end

      def missing(table, entry_id, ignore_missing)
        raise IPaaS::Job::FailJob, not_found(table, entry_id) unless ignore_missing

        { entry_id: nil, entry: nil, columns: columns(table) }
      end

      def not_found(table, entry_id)
        %(Entry #{entry_id} not found in "#{table[:name]}")
      end
    end
  end
end
