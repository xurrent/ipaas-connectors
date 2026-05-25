require 'spec_helper'

RSpec.describe IPaaS::Connector::Schema::StructureInferrer do
  subject(:structure) { described_class.infer(*samples) }

  describe 'flat object' do
    let(:samples) { ['{"name": "John", "age": 30}'] }

    it 'infers nested structure with typed fields' do
      expect(structure[:type]).to eq(:nested)
      expect(structure[:fields]['name'][:type]).to eq(:string)
      expect(structure[:fields]['name'][:values]).to eq({ 'John' => 1 })
      expect(structure[:fields]['age'][:type]).to eq(:integer)
      expect(structure[:fields]['age'][:values]).to eq({ 30 => 1 })
    end
  end

  describe 'type inference' do
    describe 'scalar types' do
      {
        'string' => ['"hello"', :string],
        'integer' => ['42', :integer],
        'float' => ['3.14', :float],
        'boolean true' => ['true', :boolean],
        'boolean false' => ['false', :boolean],
        'null' => ['null', :null],
      }.each do |label, (json_value, expected_type)|
        it "infers #{label}" do
          result = described_class.infer("{\"val\": #{json_value}}")
          expect(result[:fields]['val'][:type]).to eq(expected_type)
        end
      end
    end

    describe 'string sub-types' do
      it 'detects URI' do
        result = described_class.infer('{"url": "https://example.com"}')
        expect(result[:fields]['url'][:type]).to eq(:uri)
      end

      it 'detects date_time' do
        result = described_class.infer('{"at": "2024-01-15T10:30:00Z"}')
        expect(result[:fields]['at'][:type]).to eq(:date_time)
      end

      it 'detects date' do
        result = described_class.infer('{"day": "2024-01-15"}')
        expect(result[:fields]['day'][:type]).to eq(:date)
      end

      it 'detects time_of_day' do
        result = described_class.infer('{"time": "14:30:00"}')
        expect(result[:fields]['time'][:type]).to eq(:time_of_day)
      end
    end
  end

  describe 'nested objects' do
    let(:samples) { ['{"user": {"name": "John"}}'] }

    it 'produces nested structure with sub-fields' do
      user = structure[:fields]['user']
      expect(user[:type]).to eq(:nested)
      expect(user[:fields]['name'][:type]).to eq(:string)
    end
  end

  describe 'arrays' do
    it 'infers primitive array' do
      result = described_class.infer('{"tags": ["a", "b"]}')
      field = result[:fields]['tags']
      expect(field[:type]).to eq(:string)
      expect(field[:array]).to eq(true)
      expect(field[:values]).to eq({ 'a' => 1, 'b' => 1 })
    end

    it 'infers array of objects' do
      result = described_class.infer('{"items": [{"id": 1}, {"id": 2}]}')
      field = result[:fields]['items']
      expect(field[:type]).to eq(:nested)
      expect(field[:array]).to eq(true)
      expect(field[:fields]['id'][:type]).to eq(:integer)
    end

    it 'handles empty arrays' do
      result = described_class.infer('{"items": []}')
      field = result[:fields]['items']
      expect(field[:type]).to eq(:string)
      expect(field[:array]).to eq(true)
    end

    it 'handles mixed-type arrays' do
      result = described_class.infer({ 'values' => [1, 'two'] })
      field = result[:fields]['values']
      expect(field[:type]).to eq(:string)
      expect(field[:array]).to eq(true)
    end
  end

  describe 'edge cases' do
    it 'falls back to string for non-standard scalar types' do
      result = described_class.infer({ 'val' => :symbol_value })
      expect(result[:fields]['val'][:type]).to eq(:string)
    end

    it 'resolves arrays with null and a single type to the non-null type' do
      result = described_class.infer({ 'ids' => [1, nil, 2] })
      field = result[:fields]['ids']
      expect(field[:type]).to eq(:integer)
      expect(field[:array]).to eq(true)
      expect(field[:values]).to eq({ 1 => 1, 2 => 1 })
    end

    it 'resolves mixed-type arrays with null and multiple types to string' do
      result = described_class.infer({ 'mix' => [1, 'text', nil] })
      field = result[:fields]['mix']
      expect(field[:type]).to eq(:string)
      expect(field[:array]).to eq(true)
    end
  end

  describe 'multi-sample merging' do
    it 'produces union of fields' do
      result = described_class.infer('{"name": "John"}', '{"age": 30}')
      expect(result[:fields].keys).to contain_exactly('name', 'age')
    end

    it 'resolves type conflicts to string' do
      result = described_class.infer('{"val": "hello"}', '{"val": 42}')
      expect(result[:fields]['val'][:type]).to eq(:string)
    end

    it 'resolves null to the typed type' do
      result = described_class.infer('{"name": null}', '{"name": "John"}')
      expect(result[:fields]['name'][:type]).to eq(:string)
    end

    it 'collects values across samples' do
      result = described_class.infer('{"status": "open"}', '{"status": "closed"}')
      expect(result[:fields]['status'][:values]).to eq({ 'open' => 1, 'closed' => 1 })
    end

    it 'excludes nil values from frequency hash' do
      result = described_class.infer('{"name": null}', '{"name": "John"}')
      expect(result[:fields]['name'][:values]).to eq({ 'John' => 1 })
    end

    it 'counts duplicate values across samples' do
      result = described_class.infer('{"s": "open"}', '{"s": "open"}', '{"s": "closed"}')
      expect(result[:fields]['s'][:values]).to eq({ 'open' => 2, 'closed' => 1 })
    end

    it 'merges arrays with mismatched element types to string' do
      result = described_class.infer('{"v": [1, 2]}', '{"v": ["a", "b"]}')
      field = result[:fields]['v']
      expect(field[:type]).to eq(:string)
      expect(field[:array]).to eq(true)
    end

    it 'merges nested objects with shared, unique, and conflicting properties' do
      sample1 = '{"event": {"id": 1, "type": "alert", "source": "monitor", "assignee": 2}}'
      sample2 = '{"event": {"id": 2, "type": "incident", "severity": "high", "assignee": "Jane"}}'
      result = described_class.infer(sample1, sample2)
      event = result[:fields]['event']

      expect(event[:type]).to eq(:nested)
      expect(event[:fields].keys).to contain_exactly('id', 'type', 'source', 'severity', 'assignee')
      expect(event[:fields]['id'][:type]).to eq(:integer)
      expect(event[:fields]['id'][:values]).to eq({ 1 => 1, 2 => 1 })
      expect(event[:fields]['type'][:values]).to eq({ 'alert' => 1, 'incident' => 1 })
      expect(event[:fields]['source'][:values]).to eq({ 'monitor' => 1 })
      expect(event[:fields]['severity'][:values]).to eq({ 'high' => 1 })
      expect(event[:fields]['assignee'][:type]).to eq(:string)
      expect(event[:fields]['assignee'][:values]).to eq({ 2 => 1, 'Jane' => 1 })
    end
  end
end
