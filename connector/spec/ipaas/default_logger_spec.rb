require 'spec_helper'

describe 'IPaaS.default_logger' do
  around(:each) do |example|
    original = IPaaS.default_logger
    example.run
  ensure
    IPaaS.default_logger = original
  end

  it 'answers the assigned logger once one is set' do
    assigned = Logger.new(File::NULL)
    IPaaS.default_logger = assigned

    expect(IPaaS.default_logger).to be(assigned)
  end

  it 'derives the logger when none is set' do
    derived = Logger.new(File::NULL)
    allow(Logger).to receive(:new).with('log/test.log').and_return(derived)
    IPaaS.default_logger = nil

    expect(IPaaS.default_logger).to be(derived)
  end
end
