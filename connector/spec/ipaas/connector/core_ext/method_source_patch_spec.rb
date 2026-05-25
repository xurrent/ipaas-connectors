require 'spec_helper'

RSpec.describe 'ProcHelper source caching' do
  describe 'file caching' do
    before(:each) do
      allow(IPaaS).to receive(:solution_directory).and_return(__dir__)
      allow(File).to receive(:readlines).and_call_original
    end

    def in_test_uuid_scope(scope_hash = {})
      IPaaS::Connector::Connector.uuid_scope(scope_hash) do
        yield scope_hash
      end
    end

    it 'content should be read once for one uuid scope' do
      proc = -> { 'Hello World!' }

      expect(File).to receive(:readlines).with(File.realpath(__FILE__)).and_call_original
      scope_hash = {}
      in_test_uuid_scope(scope_hash) do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
        expect(helper.source).to eq("proc = -> { 'Hello World!' }")
      end
      in_test_uuid_scope(scope_hash) do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
        expect(helper.source).to eq("proc = -> { 'Hello World!' }")
      end
    end

    it 'can provide uuid scope postfix' do
      msg = IPaaS::Connector::Common::SolutionFileCache.uuid_scope_postfix_for_error_msg
      expect(msg).to eq(', in default scope')

      proc = -> { 'Hello World!' }
      in_test_uuid_scope do
        msg = IPaaS::Connector::Common::SolutionFileCache.uuid_scope_postfix_for_error_msg
        expect(msg).to eq(', in scope: {}')

        IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
        msg = IPaaS::Connector::Common::SolutionFileCache.uuid_scope_postfix_for_error_msg
        location = File.realpath(__FILE__)
        expect(msg).to eq(", in scope: {\"IPaaS::Connector::Common::SourceLines\" => [\"#{location}\"]}")
      end
    end
  end
end
