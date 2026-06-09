require 'spec_helper'

describe IPaaS::Connector::Types::RecurrenceType do
  it 'should define the ruby class' do
    expect(subject.ruby_class).to eq(Hash)
  end

  it 'should return true for nested?' do
    expect(subject.nested?).to be_truthy
  end

  it 'should provide an example' do
    field = IPaaS::Connector::Schema::Field.new(id: :foo, label: 'Foo', type: :recurrence)
    example = subject.example(field)
    expect(example[:day]).to eq(%w[monday thursday])
    expect(example[:day_of_month]).to eq([1, 16, -1])
    expect(example[:disabled]).to eq(false)
    expect(example[:frequency]).to eq('monthly')
  end

  describe 'date range validation' do
    let(:date_schema) do
      IPaaS::Connector::Schema.new('reference') do
        field :rec, 'Rec', :recurrence
      end
    end

    def recurrence_nested(start_date, end_date)
      [
        { field_id: :frequency, fixed: 'daily' },
        { field_id: :time_zone, fixed: 'UTC' },
        { field_id: :interval, fixed: 1 },
        { field_id: :time_of_day, fixed: '09:00' },
        { field_id: :start_date, fixed: start_date },
        { field_id: :end_date, fixed: end_date },
      ]
    end

    def resolve_recurrence(start_date:, end_date:)
      mapping = [{ field_id: :rec, nested: recurrence_nested(start_date, end_date) }]
      IPaaS::Connector::Mapping::ResolvedMapping.new(Object.new, date_schema.fields, mapping).resolve
    end

    def nested_errors(resolved, field_id)
      rec = resolved.mapping.detect { |m| m.field_id == :rec }
      rec.nested.detect { |n| n.field_id == field_id }.errors[:base]
    end

    it 'flags both start_date and end_date when the end date is before the start date' do
      resolved = resolve_recurrence(start_date: '2026-06-20', end_date: '2026-06-10')

      expect(resolved).not_to be_valid
      expect(nested_errors(resolved, :start_date)).to include("Field 'start_date' should be on or before 2026-06-10.")
      expect(nested_errors(resolved, :end_date)).to include("Field 'end_date' should be on or after 2026-06-20.")
    end

    it 'accepts a recurrence whose end date is on or after the start date' do
      expect(resolve_recurrence(start_date: '2026-06-10', end_date: '2026-06-20')).to be_valid
    end
  end

  describe 'schema' do
    let(:schema) { subject.schema }

    [:frequency, :time_zone, :interval, :time_of_day, :day, :day_of_month, :day_of_week_index, :day_of_week_day,
     :month_of_year,]
      .each do |field_id|
      it "should mark #{field_id} as required" do
        expect(schema.field(field_id).required).to be_truthy
      end
    end

    {
      frequency: 'monthly',
      disabled: false,
      time_zone: 'UTC',
      interval: 4,
      day: %w[monday thursday],
      day_of_month: [1, 16, -1],
      day_of_week_index: 3,
      day_of_week_day: 'monday',
      month_of_year: [2, 4],
    }.each do |field_id, sample|
      it "should define sample of #{field_id} as #{sample.inspect}" do
        expect(schema.field(field_id).sample).to eq(sample)
      end
    end

    {
      frequency: %w[no_repeat minutely hourly daily weekly monthly yearly],
      day: %w[sunday monday tuesday wednesday thursday friday saturday],
      day_of_month: (1..31).to_a + [-1],
      day_of_week_index: [1, 2, 3, 4, -1],
      day_of_week_day: %w[sunday monday tuesday wednesday thursday friday saturday],
      month_of_year: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    }.each do |field_id, enumeration|
      it "should define enumeration of #{field_id} as #{enumeration.inspect}" do
        expect(schema.field(field_id).enumeration.pluck(:id)).to eq(enumeration)
      end
    end

    it 'should define a min of 1 for interval' do
      expect(schema.field(:interval).min).to eq(1)
    end

    [:day, :day_of_month, :month_of_year]
      .each do |field_id|
      it "should mark #{field_id} as array" do
        expect(schema.field(field_id).array).to be_truthy
      end
    end

    context 'on config update' do
      STANDARD_RECURRENCE_FIELDS = [
        :frequency, :disabled, :time_zone, :interval, :time_of_day, :start_date, :end_date,
      ].freeze

      it 'should disable and hide all fields when disabled is true' do
        schema.resolve(Object.new, [{ field_id: 'disabled', fixed: true }])
        should_have_active_fields([:disabled])
      end

      it 'should not disable required fields when frequency is daily' do
        schema.resolve(Object.new, [{ field_id: 'frequency', fixed: 'daily' }])
        expected_fields = [:frequency, :disabled, :time_zone, :interval, :time_of_day, :start_date, :end_date]
        should_have_active_fields(expected_fields)
      end

      it 'should disable all fields except for disabled and frequency when not repeating' do
        schema.resolve(Object.new, [{ field_id: 'frequency', fixed: 'no_repeat' }])
        should_have_active_fields([:frequency, :disabled])
      end

      it 'should enable "day" for weekly recurrence' do
        schema.resolve(Object.new, [{ field_id: 'frequency', fixed: 'weekly' }])
        should_have_active_fields([:day] + STANDARD_RECURRENCE_FIELDS)
      end

      it 'should enable "day_of_month" for monthly recurrence' do
        schema.resolve(Object.new, [{ field_id: 'frequency', fixed: 'monthly' }])
        should_have_active_fields([:day_of_week, :day_of_month] + STANDARD_RECURRENCE_FIELDS)
      end

      it 'should enable "day_of_week_index" and "day_of_week_day" for monthly recurrence when day_of_week is true' do
        schema.resolve(Object.new, [
          { field_id: 'frequency', fixed: 'monthly' },
          { field_id: 'day_of_week', fixed: true },
        ])
        should_have_active_fields([:day_of_week, :day_of_week_index, :day_of_week_day] + STANDARD_RECURRENCE_FIELDS)
      end

      it 'should enable "month_of_year" for yearly recurrence' do
        schema.resolve(Object.new, [{ field_id: 'frequency', fixed: 'yearly' }])
        should_have_active_fields([:day_of_week, :month_of_year] + STANDARD_RECURRENCE_FIELDS)
      end

      it 'should enable "day_of_week_index" and "day_of_week_day" for yearly recurrence when day_of_week is true' do
        schema.resolve(Object.new, [
          { field_id: 'frequency', fixed: 'yearly' },
          { field_id: 'day_of_week', fixed: true },
        ])
        should_have_active_fields([:day_of_week, :day_of_week_index, :day_of_week_day,
                                   :month_of_year,] + STANDARD_RECURRENCE_FIELDS)
      end

      it 'should not require time_of_day for hourly recurrence' do
        schema.resolve(Object.new, [{ field_id: 'frequency', fixed: 'hourly' }])
        expect(schema.fields.detect { |f| f.id == :time_of_day }.required).to be_falsey

        %w[daily weekly monthly yearly].each do |frequency|
          schema.resolve(Object.new, [{ field_id: 'frequency', fixed: frequency }])
          expect(schema.fields.detect { |f| f.id == :time_of_day }.required).to be_truthy
        end
      end

      it 'bounds end_date by start_date and start_date by end_date' do
        schema.resolve(Object.new, [
          { field_id: 'frequency', fixed: 'daily' },
          { field_id: 'start_date', fixed: '2026-06-10' },
          { field_id: 'end_date', fixed: '2026-06-20' },
        ])

        expect(schema.field(:end_date).min_date).to eq('2026-06-10')
        expect(schema.field(:start_date).max_date).to eq('2026-06-20')
      end

      it 'leaves date bounds unset when the sibling date is absent' do
        schema.resolve(Object.new, [
          { field_id: 'frequency', fixed: 'daily' },
          { field_id: 'start_date', fixed: '2026-06-10' },
        ])

        expect(schema.field(:end_date).min_date).to eq('2026-06-10')
        expect(schema.field(:start_date).max_date).to be_nil
      end

      it 'clears date bounds when the frequency is no_repeat' do
        schema.resolve(Object.new, [
          { field_id: 'frequency', fixed: 'daily' },
          { field_id: 'start_date', fixed: '2026-06-10' },
          { field_id: 'end_date', fixed: '2026-06-20' },
        ])
        schema.resolve(Object.new, [
          { field_id: 'frequency', fixed: 'no_repeat' },
          { field_id: 'start_date', fixed: '2026-06-10' },
          { field_id: 'end_date', fixed: '2026-06-20' },
        ])

        expect(schema.field(:end_date).min_date).to be_nil
        expect(schema.field(:start_date).max_date).to be_nil
      end

      def should_have_active_fields(active_field_ids)
        expect(enabled_fields.map(&:id)).to contain_exactly(*active_field_ids)
        expect(visible_fields.map(&:id)).to contain_exactly(*active_field_ids)
      end

      def enabled_fields
        schema.fields.reject(&:disabled)
      end

      def visible_fields
        schema.fields.select { |f| f.visibility == 'visible' }
      end
    end

    context 'when a previous resolve raised an exception (regression: request #77167827)' do
      # RecurrenceType.schema is a process-wide singleton — an exception leaking
      # @resolving=true on it silently disables after_update for every later
      # resolve in the same process.

      it 'still runs after_update on subsequent resolves' do
        expect { schema.resolve(Object.new, 'not a hash') }.to raise_error(IPaaS::Error)

        schema.resolve(Object.new, [
          { field_id: 'frequency', fixed: 'daily' },
          { field_id: 'time_of_day', fixed: '09:00' },
        ])

        [:day, :day_of_month, :day_of_week_index, :day_of_week_day, :month_of_year].each do |id|
          expect(schema.field(id).disabled).to be_truthy
        end
        expect(schema.field(:time_zone).disabled).to be_falsey
        expect(schema.field(:interval).disabled).to be_falsey
      end
    end
  end
end
