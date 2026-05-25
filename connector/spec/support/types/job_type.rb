class JobType
  include IPaaS::Connector::Types::Base

  class << self
    def ruby_class
      Class
    end

    def example(_field)
      nil
    end
  end
end

IPaaS::Connector::Types.register(JobType)
