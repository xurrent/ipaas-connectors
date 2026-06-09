module IPaaS
  module Connector
    module Types
      module RecurrenceType
        include IPaaS::Connector::Types::Base

        SCHEMA_REFERENCE = 'recurrence-type'.freeze

        class << self
          def ruby_class
            Hash
          end

          def nested?
            true
          end

          # The end-date-on-or-after-start-date constraint is enforced per field via the
          # min_date/max_date bounds set in after_update (validated server-side by
          # ResolvedMapping#validate_min_date/#validate_max_date), so errors attach to the
          # specific start_date/end_date fields rather than the whole recurrence value.

          def example(field)
            fields_example(field.fields)
          end

          def schema
            @schema ||= IPaaS::Connector::Schema.new(SCHEMA_REFERENCE) do
              field :frequency, 'Frequency', :string,
                    required: true,
                    sample: 'monthly',
                    enumeration: [
                      { id: 'no_repeat', label: 'No Repeat' },
                      { id: 'minutely', label: 'Minutely' },
                      { id: 'hourly', label: 'Hourly' },
                      { id: 'daily', label: 'Daily' },
                      { id: 'weekly', label: 'Weekly' },
                      { id: 'monthly', label: 'Monthly' },
                      { id: 'yearly', label: 'Yearly' },
                    ]

              field :disabled, 'Disabled', :boolean,
                    sample: false

              field :time_zone, 'Time Zone', :time_zone,
                    required: true,
                    sample: 'UTC',
                    enumeration: IPaaS::Connector::Types::TimeZoneType::ZONES_BY_NAME.keys.sort.map { |name| { id: name, label: name } }

              field :interval, 'Interval', :integer,
                    required: true,
                    min: 1,
                    sample: 4

              field :time_of_day, 'Time of day', :time_of_day,
                    required: true,
                    hint: 'The time of day (in the given time zone) to execute the recurrence function. ' \
                          'When frequency is "hourly", indicates the time of the day the recurrence function ' \
                          'is executed for the first time.'

              field :start_date, 'Start date', :date
              field :end_date, 'End date', :date
              # TODO: after: :start_date

              # weekly
              field :day, 'Weekday', :string,
                    required: true,
                    array: true,
                    enumeration: [
                      { id: 'sunday', label: 'Sunday' },
                      { id: 'monday', label: 'Monday' },
                      { id: 'tuesday', label: 'Tuesday' },
                      { id: 'wednesday', label: 'Wednesday' },
                      { id: 'thursday', label: 'Thursday' },
                      { id: 'friday', label: 'Friday' },
                      { id: 'saturday', label: 'Saturday' },
                    ],
                    sample: %w[monday thursday]

              # monthly
              field :day_of_week, 'Day of week', :boolean

              field :day_of_month, 'Day of month', :integer,
                    required: true,
                    array: true,
                    enumeration: (1..31).map { |i| { id: i, label: i } } + [{ id: -1, label: 'Last' }],
                    sample: [1, 16, -1]

              # monthly/yearly
              field :day_of_week_index, 'Day of the week', :integer,
                    required: true,
                    enumeration: [
                      { id: 1, label: 'First' },
                      { id: 2, label: 'Second' },
                      { id: 3, label: 'Third' },
                      { id: 4, label: 'Fourth' },
                      { id: -1, label: 'Last' },
                    ],
                    sample: 3

              field :day_of_week_day, 'Weekday', :string,
                    required: true,
                    enumeration: [
                      { id: 'sunday', label: 'Sunday' },
                      { id: 'monday', label: 'Monday' },
                      { id: 'tuesday', label: 'Tuesday' },
                      { id: 'wednesday', label: 'Wednesday' },
                      { id: 'thursday', label: 'Thursday' },
                      { id: 'friday', label: 'Friday' },
                      { id: 'saturday', label: 'Saturday' },
                    ],
                    sample: 'monday'

              # yearly
              field :month_of_year, 'Month of year', :integer,
                    required: true,
                    array: true,
                    enumeration: [
                      { id: 1, label: 'January' },
                      { id: 2, label: 'February' },
                      { id: 3, label: 'March' },
                      { id: 4, label: 'April' },
                      { id: 5, label: 'May' },
                      { id: 6, label: 'June' },
                      { id: 7, label: 'July' },
                      { id: 8, label: 'August' },
                      { id: 9, label: 'September' },
                      { id: 10, label: 'October' },
                      { id: 11, label: 'November' },
                      { id: 12, label: 'December' },
                    ],
                    sample: [2, 4]

              after_update do |fields, values|
                active_fields = [:disabled]

                unless values[:disabled]
                  active_fields += [:frequency, :interval, :time_of_day, :time_zone, :start_date, :end_date]

                  time_of_day = fields.detect { |f| f.id == :time_of_day }
                  time_of_day.required(%w[daily weekly monthly yearly].include?(values[:frequency]))

                  case values[:frequency]
                  when 'weekly'
                    active_fields += [:day]
                  when 'monthly'
                    active_fields += [:day_of_week]
                    active_fields += if values[:day_of_week]
                                       [:day_of_week_index, :day_of_week_day]
                                     else
                                       [:day_of_month]
                                     end
                  when 'yearly'
                    active_fields += [:month_of_year, :day_of_week]
                    active_fields += [:day_of_week_index, :day_of_week_day] if values[:day_of_week]
                  when 'no_repeat'
                    active_fields = [:disabled, :frequency]
                  end

                  start_date = fields.detect { |f| f.id == :start_date }
                  end_date = fields.detect { |f| f.id == :end_date }
                  if start_date && end_date
                    no_repeat = values[:frequency] == 'no_repeat'
                    end_date.min_date = !no_repeat && values[:start_date].present? ? values[:start_date].to_s : nil
                    start_date.max_date = !no_repeat && values[:end_date].present? ? values[:end_date].to_s : nil
                  end
                end

                fields.each do |field|
                  active = active_fields.include?(field.id)
                  field.disabled = !active
                  field.visibility = active ? 'visible' : 'hidden'
                end

                fields
              end
            end
          end
        end
      end
    end
  end
end

IPaaS::Connector::Types.register(IPaaS::Connector::Types::RecurrenceType)
