require 'spec_helper'

describe IPaaS::Job::ContentType do
  describe '.detect_content_type' do
    {
      'document.pdf' => 'application/pdf',
      'image.png' => 'image/png',
      'photo.jpg' => 'image/jpeg',
      'photo.jpeg' => 'image/jpeg',
      'animation.gif' => 'image/gif',
      'icon.svg' => 'image/svg+xml',
      'picture.webp' => 'image/webp',
      'data.json' => 'application/json',
      'feed.xml' => 'application/xml',
      'report.csv' => 'text/csv',
      'readme.txt' => 'text/plain',
      'archive.zip' => 'application/zip',
    }.each do |file_name, expected|
      it "returns '#{expected}' for '#{file_name}'" do
        expect(described_class.detect_content_type(file_name)).to eq(expected)
      end
    end

    it 'returns octet-stream for unknown extensions' do
      expect(described_class.detect_content_type('file.unknown')).to eq('application/octet-stream')
    end

    it 'returns octet-stream for nil file name' do
      expect(described_class.detect_content_type(nil)).to eq('application/octet-stream')
    end

    it 'returns octet-stream for file without extension' do
      expect(described_class.detect_content_type('noextension')).to eq('application/octet-stream')
    end

    it 'is case-insensitive for extensions' do
      expect(described_class.detect_content_type('FILE.PDF')).to eq('application/pdf')
      expect(described_class.detect_content_type('image.PNG')).to eq('image/png')
    end

    it 'uses the last dot-separated segment as extension' do
      expect(described_class.detect_content_type('archive.tar.gz')).to eq('application/octet-stream')
      expect(described_class.detect_content_type('my.file.pdf')).to eq('application/pdf')
    end
  end
end
