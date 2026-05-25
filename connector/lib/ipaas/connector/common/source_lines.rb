module IPaaS
  module Connector
    module Common
      class SourceLines
        include IPaaS::Connector::Common::Model
        include IPaaS::Connector::Common::UuidMixin

        attr_accessor :content

        class << self
          def add_record_by_uuid(record)
            scoped_records_by_uuid.each_value do |v|
              next unless v.content == record.content

              # ensure we keep only one copy of the identical file content in memory
              v.content = record.content
            end
            scoped_records_by_uuid[record.uuid] = record
          end
        end
      end
    end
  end
end
