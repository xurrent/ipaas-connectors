require 'spec_helper'

describe IPaaS::Job::Humanize do
  describe '.humanize_field_name' do
    it 'converts camelCase to Title Case' do
      expect(described_class.humanize_field_name('primaryEmail')).to eq('Primary Email')
    end

    it 'converts PascalCase to Title Case' do
      expect(described_class.humanize_field_name('PrimaryEmail')).to eq('Primary Email')
    end

    it 'converts snake_case to Title Case' do
      expect(described_class.humanize_field_name('primary_email')).to eq('Primary Email')
    end

    it 'handles single word' do
      expect(described_class.humanize_field_name('name')).to eq('Name')
    end

    it 'handles multiple consecutive capitals' do
      expect(described_class.humanize_field_name('sourceID')).to eq('Source ID')
    end

    it 'preserves all-caps words' do
      expect(described_class.humanize_field_name('ASC')).to eq('ASC')
      expect(described_class.humanize_field_name('DRAFT')).to eq('DRAFT')
    end

    it 'splits acronym followed by word' do
      expect(described_class.humanize_field_name('HTMLParser')).to eq('HTML Parser')
    end

    it 'handles already spaced input' do
      expect(described_class.humanize_field_name('first name')).to eq('First Name')
    end

    it 'handles mixed camelCase and underscores' do
      expect(described_class.humanize_field_name('my_fieldName')).to eq('My Field Name')
    end
  end
end
