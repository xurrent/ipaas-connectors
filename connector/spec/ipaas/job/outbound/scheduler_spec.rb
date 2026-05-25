require 'spec_helper'

describe IPaaS::Job::Outbound::Scheduler do
  let(:solution) { double('Solution') }

  let(:context) do
    klass = Class.new { include IPaaS::Job::Context }
    klass.new.tap { |c| allow(c).to receive(:solution).and_return(solution) }
  end

  let(:resolved_mapping) do
    schema = IPaaS::Connector::Schema.new('test') do
      field :time_zone, 'Time Zone', :string
    end
    IPaaS::Connector::Mapping::ResolvedMapping.new(
      Object.new,
      schema.fields,
      [{ field_id: :time_zone, fixed: 'America/Chicago' }],
    ).resolve
  end

  describe '#update_schedule' do
    it 'converts a ResolvedMapping to a plain hash before passing to solution' do
      received_attrs = nil
      allow(solution).to receive(:update_schedule) { |_, attrs| received_attrs = attrs }

      context.update_schedule('ref-123', resolved_mapping)

      expect(received_attrs).not_to be_a(IPaaS::Connector::Mapping::ResolvedMapping)
      expect(received_attrs).to include('time_zone' => 'America/Chicago')
    end

    it 'passes a plain hash through unchanged' do
      received_attrs = nil
      allow(solution).to receive(:update_schedule) { |_, attrs| received_attrs = attrs }

      context.update_schedule('ref-123', { time_zone: 'UTC' })

      expect(received_attrs).to include(time_zone: 'UTC')
    end
  end

  describe '#create_schedule!' do
    it 'converts a ResolvedMapping to a plain hash before passing to solution' do
      received_attrs = nil
      allow(solution).to receive(:create_schedule!) { |_, attrs| received_attrs = attrs }

      context.create_schedule!('runbook-uuid', resolved_mapping)

      expect(received_attrs).not_to be_a(IPaaS::Connector::Mapping::ResolvedMapping)
      expect(received_attrs).to include('time_zone' => 'America/Chicago')
    end
  end
end
