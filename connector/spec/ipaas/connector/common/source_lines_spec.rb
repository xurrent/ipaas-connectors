require 'spec_helper'

describe IPaaS::Connector::Common::SourceLines do
  describe 'add_record_by_uuid' do
    it 'allows file to be retrieved based on file name as uuid inside uuid scope' do
      lines1 = nil
      lines2 = nil
      file_name = '/tmp/1'
      expect(described_class.by_uuid(file_name)).to eq(nil)

      scope1 = {}
      IPaaS::Connector::Connector.uuid_scope(scope1) do
        expect(described_class.by_uuid(file_name)).to eq(nil)
        lines1 = described_class.new(file_name)
        lines1.content = ['abc']
        described_class.add_record_by_uuid(lines1)

        expect(described_class.by_uuid(file_name)).to eq(lines1)
      end
      expect(described_class.by_uuid(file_name)).to eq(nil)

      scope2 = {}
      IPaaS::Connector::Connector.uuid_scope(scope2) do
        expect(described_class.by_uuid(file_name)).to eq(nil)
        lines2 = described_class.new(file_name)
        lines2.content = ['xyz']
        described_class.add_record_by_uuid(lines2)

        expect(described_class.by_uuid(file_name)).to eq(lines2)
      end
      expect(described_class.by_uuid(file_name)).to eq(nil)

      IPaaS::Connector::Connector.uuid_scope(scope1) do
        expect(described_class.by_uuid(file_name)).to eq(lines1)
      end
      IPaaS::Connector::Connector.uuid_scope(scope2) do
        expect(described_class.by_uuid(file_name)).to eq(lines2)
      end
    end

    it 'can store multiple files' do
      IPaaS::Connector::Connector.uuid_scope({}) do
        lines1 = described_class.new('/tmp/1')
        lines1.content = ['abc']
        lines2 = described_class.new('/tmp/2')
        lines2.content = ['xyz']
        described_class.add_record_by_uuid(lines1)
        expect(described_class.by_uuid('/tmp/1')).to eq(lines1)
        described_class.add_record_by_uuid(lines2)
        expect(described_class.by_uuid('/tmp/2')).to eq(lines2)
      end
    end

    it 'content of multiple files with identical content is only stored once' do
      IPaaS::Connector::Connector.uuid_scope({}) do
        lines1 = described_class.new('/tmp/1')
        lines1.content = %w[abc xyz]
        lines2 = described_class.new('/tmp/2')
        lines2.content = %w[abc xyz]
        lines3 = described_class.new('/tmp/3')
        lines3.content = %w[xyz xyz]
        lines4 = described_class.new('/tmp/4')
        lines4.content = %w[abc xyz]
        expect(lines1.content).to eq(lines2.content)
        expect(lines3.content).not_to eq(lines1.content)
        expect(lines4.content).to eq(lines1.content)
        # originally different arrays
        expect(lines1.content.object_id).not_to eq(lines2.content.object_id)
        expect(lines4.content.object_id).not_to eq(lines2.content.object_id)

        described_class.add_record_by_uuid(lines1)
        expect(described_class.by_uuid('/tmp/1')).to eq(lines1)
        described_class.add_record_by_uuid(lines2)
        expect(described_class.by_uuid('/tmp/2')).to eq(lines2)
        described_class.add_record_by_uuid(lines3)
        expect(described_class.by_uuid('/tmp/3')).to eq(lines3)
        described_class.add_record_by_uuid(lines4)
        expect(described_class.by_uuid('/tmp/4')).to eq(lines4)

        expect(described_class.by_uuid('/tmp/2')).to eq(lines2)
        expect(lines2.content).to eq(lines1.content)
        expect(described_class.by_uuid('/tmp/4')).to eq(lines4)
        expect(lines4.content).to eq(lines1.content)
        # values from scope use same array when content equals
        expect(lines2.content.object_id).to eq(lines1.content.object_id)
        expect(lines4.content.object_id).to eq(lines1.content.object_id)

        # other content that did not match was not changed
        expect(lines3.content).not_to eq(lines1.content)
      end
    end
  end
end
