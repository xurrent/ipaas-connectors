require 'nokogiri'

module IPaaS
  module Job
    module Outbound
      module XML
        extend ActiveSupport::Concern
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :parse_xml_response

        included do
          def parse_xml_response(xml_body)
            options = Nokogiri::XML::ParseOptions::NONET |
                      Nokogiri::XML::ParseOptions::NOBLANKS
            doc = Nokogiri::XML(xml_body, nil, nil, options)
            doc.remove_namespaces!
            doc
          end
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::Outbound::XML)
