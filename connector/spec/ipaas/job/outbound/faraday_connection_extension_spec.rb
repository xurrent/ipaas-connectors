require 'spec_helper'

describe IPaaS::Job::Outbound::FaradayConnectionExtension do
  let(:connection) do
    Faraday::Connection.new('https://example.com')
  end

  Faraday::Connection::METHODS.each do |method|
    it "should call the given method and pass the given block when #{method} is passed" do
      specific_block = -> { 'foo' }
      expect(connection).to receive(:get) { |&block| expect(block).to be(specific_block) }
      connection.http_send(:get, &specific_block)
    end

    it "should allow passing a path for #{method}" do
      specific_block = -> { 'foo' }
      expect(connection).to receive(:get).with('/path') { |&block| expect(block).to be(specific_block) }
      connection.http_send(:get, '/path', &specific_block)
    end
  end

  it 'should fail when an invalid method is passed' do
    failure_message = 'Invalid http method, expected one of get, post, put, delete, head, patch, options, trace.'
    expect do
      connection.http_send(:foo) {}
    end.to raise_error(IPaaS::Error, failure_message)
  end
end
