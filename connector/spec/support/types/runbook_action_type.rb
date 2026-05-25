class RunbookActionType
  include IPaaS::Connector::Types::Base

  class << self
    def ruby_class
      Class # Runbook with trigger 'f3e0c4ed-5df7-4788-8f9b-266b9a96ea3b'
    end

    def example(_field)
      nil
    end
  end
end

IPaaS::Connector::Types.register(RunbookActionType)
