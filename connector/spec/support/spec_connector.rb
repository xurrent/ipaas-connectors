# A block written in a spec has no connector of its own, where every production block does. These
# hand a spec's objects one, so a missing owner in production code still raises.
def spec_connector
  @spec_connector ||= new_spec_connector
end

def new_spec_connector
  IPaaS::Connector::Connector.new("spec-connector-#{SecureRandom.hex(4)}")
end

def owned_by_spec_connector(object)
  spec_connector.send(:owned_by, object, spec_connector)
  object
end

def schema_with_connector(reference, &block)
  owned_by_spec_connector(IPaaS::Connector::Schema.new(reference)).tap do |schema|
    schema.instance_eval(&block) if block
  end
end

# An authentication module written in a spec stands in for one of the gem's own, whose blocks are
# judged process-wide rather than against a connector.
def treat_spec_blocks_as_gem_code
  authentication_specs = "#{File.expand_path('../ipaas/connector/authentication', __dir__)}/"
  allow(IPaaS::Connector::Common::ProcHelper).to receive(:gem_file?).and_wrap_original do |original, file|
    original.call(file) || file.to_s.start_with?(authentication_specs)
  end
end
