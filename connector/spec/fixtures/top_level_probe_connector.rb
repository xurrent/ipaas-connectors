class TopLevelProbeConnector < IPaaS::Connector::Definition
  LIMIT = 1

  connector '00000000-0000-4000-8000-0000000f1a7e' do
    name 'Top Level Probe'
    helper(:own_read) { TopLevelProbeConnector::LIMIT }
    helper(:bare_self) { TopLevelProbeConnector }
    helper(:top_level_from_another_file) { PROC_FROM_ANOTHER_FILE_MARK }
  end
end
