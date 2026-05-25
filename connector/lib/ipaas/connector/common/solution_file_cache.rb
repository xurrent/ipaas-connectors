module IPaaS
  module Connector
    module Common
      class SolutionFileCache
        class << self
          def store_file_content(file_name, content)
            current_lines = SourceLines.by_uuid(file_name)
            current_lines ||= SourceLines.new(file_name)
            current_lines.content = content
            current_lines
          end

          def content_cached?(file_name)
            SourceLines.by_uuid(file_name).present?
          end

          def lines_for(file_name)
            store_file_content(file_name, read_file_content(file_name)) unless content_cached?(file_name)
            cached_content(file_name)
          end

          def read_file_content(file_name)
            File.readlines(file_name)
          end

          def clear
            SourceLines.scoped_records_by_uuid&.clear
          end

          def uuid_scope_postfix_for_error_msg
            SourceLines.uuid_scope_postfix_for_error_msg
          end

          private

          def cached_content(file_name)
            SourceLines.by_uuid(file_name)&.content
          end
        end
      end
    end
  end
end
