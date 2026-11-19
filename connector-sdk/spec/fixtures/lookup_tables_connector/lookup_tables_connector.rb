class LookupTablesConnector < IPaaS::Connector::Definition
  connector '01a19c65-6232-71c9-842a-1d22c682e939' do
    name 'Lookup Tables'
    avatar '/assets/icons/table.svg'
    description <<~END_OF_DESCRIPTION
      Reads and writes the account's lookup tables: tables of text values that outlive any job, such as a map from one system's identifier to another's.

      A connection names one table. Saving the connection finds the table in this account and lists its columns, and each step on the connection shows one field per listed column. Runs always use the table's own columns.

      Values are stored as text, trimmed of spaces, tabs and line breaks at both ends. Matching is exact and case-sensitive.
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :table, 'Table', :string,
              required: true,
              hint: 'The name of a lookup table in this account. ' \
                    'Saving the connection finds the table and lists its columns.'
        field :columns, 'Columns', :hash,
              visibility: 'hidden',
              hint: 'Written when the connection is saved: the table and its columns.'
      end
    end

    helper :table_uuid do
      columns = outbound_connection&.config&.[](:columns)
      columns.is_a?(Hash) ? columns[:table_uuid].to_s : ''
    end

    helper :listed_columns do
      columns = outbound_connection&.config&.[](:columns)
      listed = columns.is_a?(Hash) ? Array(columns[:columns]) : []
      listed.filter_map do |column|
        next unless column.is_a?(Hash) && column[:key].present?

        { key: column[:key].to_s, label: column[:label].to_s.presence || column[:key].to_s }
      end
    end

    helper :column_fields do |container, field_id|
      next if container.nil?

      listed = helpers.listed_columns
      container.fields = []
      listed.each { |column| container.field(column[:key].to_sym, column[:label], :any) }
      (lookup_table_mapped_keys(field_id) - listed.pluck(:key)).uniq.each do |key|
        container.field(key.to_sym, key, :any)
      end
    end

    action '01a19c65-6234-7803-bddf-646f76f381fd' do
      name 'Add Entry'
      avatar '/assets/icons/table.svg'
      description <<~END_OF_DESCRIPTION
        Adds an entry to the connection's table. Each mapped column gets its value as text; a column left unmapped gets no value. An entry needs at least one value.
      END_OF_DESCRIPTION

      input_schema do
        field :values, 'Values', :nested,
              hint: 'A value per column. Numbers, true and false, times and dates are stored as text.'

        after_update do |fields|
          helpers.column_fields(fields.detect { |field| field.id == :values }, :values)
          fields
        end
      end

      output_schema do
        field :entry_id, 'Entry ID', :string
        field :entry, 'Entry', :nested, remove_unmapped_fields: false
        field :columns, 'Columns', :nested, array: true do
          field :column, 'Column', :string
          field :label, 'Label', :string
        end
      end

      run do
        [{ output: lookup_table_add_entry(helpers.table_uuid, input[:values].to_h) }]
      end
    end

    action '01a19c65-6237-7115-942e-6bd21ea2be67' do
      name 'Lookup Entry'
      avatar '/assets/icons/table.svg'
      description <<~END_OF_DESCRIPTION
        Finds the oldest entry whose mapped columns all match exactly, case-sensitively. A column may take a list of up to 100 values; any of them matches. Finding nothing fails the step.
      END_OF_DESCRIPTION

      input_schema do
        field :match, 'Lookup by', :nested,
              hint: 'Map at least one column. A blank value fails the step.'

        after_update do |fields|
          helpers.column_fields(fields.detect { |field| field.id == :match }, :match)
          fields
        end
      end

      output_schema do
        field :entry_id, 'Entry ID', :string
        field :entry, 'Entry', :nested, remove_unmapped_fields: false
        field :columns, 'Columns', :nested, array: true do
          field :column, 'Column', :string
          field :label, 'Label', :string
        end
      end

      run do
        [{ output: lookup_table_lookup_entry(helpers.table_uuid, input[:match].to_h) }]
      end
    end

    action '01a19c65-6239-79c7-ae02-52ac9d367bd2' do
      name 'Search Entries'
      avatar '/assets/icons/table.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Runs the steps inside once per page of up to 100 matching entries, oldest first. With no match, they run once with Entries empty. At most limits the entries returned in all.
      END_OF_DESCRIPTION

      input_schema do
        field :match, 'Search by', :nested,
              hint: 'Map at least one column. A blank value fails the step.'
        field :at_most, 'At most', :any,
              visibility: 'optional',
              hint: 'The most entries to return in all: a whole number from 1 to 100,000.'

        after_update do |fields|
          helpers.column_fields(fields.detect { |field| field.id == :match }, :match)
          fields
        end
      end

      output_schema 'page' do
        field :entries, 'Entries', :nested, array: true do
          field :entry_id, 'Entry ID', :string
          field :entry, 'Entry', :nested, remove_unmapped_fields: false
        end
        field :columns, 'Columns', :nested, array: true do
          field :column, 'Column', :string
          field :label, 'Label', :string
        end
      end

      iteration_state_schema do
        field :after, 'After', :string
        field :returned, 'Returned', :integer
      end

      run do
        page = lookup_table_search_page(helpers.table_uuid, input[:match].to_h, at_most: input[:at_most])
        page ? [{ output: page, schema_reference: 'page' }] : []
      end
    end

    action '01a19c65-623b-7579-96e6-934ea378ec73' do
      name 'Get All Entries'
      avatar '/assets/icons/table.svg'
      nested true
      description <<~END_OF_DESCRIPTION
        Runs the steps inside once per page of up to 100 entries, oldest first. An empty table runs them once with Entries empty.
      END_OF_DESCRIPTION

      output_schema 'page' do
        field :entries, 'Entries', :nested, array: true do
          field :entry_id, 'Entry ID', :string
          field :entry, 'Entry', :nested, remove_unmapped_fields: false
        end
        field :columns, 'Columns', :nested, array: true do
          field :column, 'Column', :string
          field :label, 'Label', :string
        end
      end

      iteration_state_schema do
        field :after, 'After', :string
        field :returned, 'Returned', :integer
      end

      run do
        page = lookup_table_get_all_page(helpers.table_uuid)
        page ? [{ output: page, schema_reference: 'page' }] : []
      end
    end

    action '01a19c65-623e-776d-a4ce-9239740e7cae' do
      name 'Update Entry'
      avatar '/assets/icons/table.svg'
      description <<~END_OF_DESCRIPTION
        Writes each mapped column of an entry as sent: a blank value clears the column. Columns left unmapped keep their values. Returns the whole entry. With no column mapped it writes nothing and returns the entry.
      END_OF_DESCRIPTION

      input_schema do
        field :entry_id, 'Entry ID', :string,
              required: true,
              hint: 'The Entry ID of the entry to change.'
        field :values, 'Values', :nested,
              hint: 'A value per column to write. Numbers, true and false, times and dates are stored as text.'
        field :ignore_if_not_found, 'Ignore if not found', :boolean,
              default: false,
              hint: 'When on, a missing entry returns no entry instead of failing the step.'

        after_update do |fields|
          helpers.column_fields(fields.detect { |field| field.id == :values }, :values)
          fields
        end
      end

      output_schema do
        field :entry_id, 'Entry ID', :string
        field :entry, 'Entry', :nested, remove_unmapped_fields: false
        field :columns, 'Columns', :nested, array: true do
          field :column, 'Column', :string
          field :label, 'Label', :string
        end
      end

      run do
        [{ output: lookup_table_update_entry(helpers.table_uuid, input[:entry_id], input[:values].to_h,
                                             ignore_if_not_found: input[:ignore_if_not_found]) }]
      end
    end

    action '01a19c65-6241-79da-ba41-1510015dac80' do
      name 'Delete Entry'
      avatar '/assets/icons/table.svg'
      description <<~END_OF_DESCRIPTION
        Deletes an entry. Deleted entry ID is null when there was no such entry, unless Ignore if not found is off.
      END_OF_DESCRIPTION

      input_schema do
        field :entry_id, 'Entry ID', :string,
              required: true,
              hint: 'The Entry ID of the entry to delete.'
        field :ignore_if_not_found, 'Ignore if not found', :boolean,
              default: true,
              hint: 'When off, a missing entry fails the step.'
      end

      output_schema do
        field :deleted_entry_id, 'Deleted entry ID', :string
      end

      run do
        deleted = lookup_table_delete_entry(helpers.table_uuid, input[:entry_id],
                                            ignore_if_not_found: input[:ignore_if_not_found])
        [{ output: { deleted_entry_id: deleted } }]
      end
    end

    action '01a19c65-6243-7f7d-9e10-97402a9c848d' do
      name 'Truncate Table'
      avatar '/assets/icons/table.svg'
      description <<~END_OF_DESCRIPTION
        Permanently deletes every entry of the table, for every solution that uses it. This can't be undone. Count is how many entries were deleted.
      END_OF_DESCRIPTION

      output_schema do
        field :count, 'Count', :integer
      end

      run do
        [{ output: { count: lookup_table_truncate(helpers.table_uuid) } }]
      end
    end
  end
end
