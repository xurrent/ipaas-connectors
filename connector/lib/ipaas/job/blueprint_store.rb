module IPaaS
  module Job
    module BlueprintStore
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :blueprint_store

      MAX_FILE_SIZE = 256.kilobytes

      class BlueprintStoreWrapper
        include ActiveSupport::NumberHelper

        def initialize(store, allowed_filenames)
          @store = store
          @allowed_filenames = Array(allowed_filenames).sort
        end

        def read(filename)
          validate_filename!(filename)
          @store.read(filename)
        end

        def write(filename, contents)
          contents = contents.to_s
          validate_filename!(filename)
          validate_size!(filename, contents)
          @store.write(filename, contents)
        end

        def delete(filename)
          validate_filename!(filename)
          @store.delete(filename)
        end

        def checksum
          content = @allowed_filenames.sort.filter_map do |filename|
            data = @store.read(filename)
            next if data.nil?

            [filename, data].to_json
          end.join

          content.blank? ? nil : Digest::SHA256.hexdigest(content)
        end

        def clear!
          @allowed_filenames.each { |filename| delete(filename) }
        end

        def blank?
          @allowed_filenames.all? { |filename| @store.read(filename).blank? }
        end

        def present?
          !blank?
        end

        private

        def validate_filename!(filename)
          return if @allowed_filenames.include?(filename.to_s)

          raise ArgumentError, "Invalid filename: '#{filename}', allowed: '#{@allowed_filenames.join("', '")}'."
        end

        def validate_size!(filename, contents)
          return if contents.bytesize <= MAX_FILE_SIZE

          raise ArgumentError, "File '#{filename}' too large, allowed: #{number_to_human_size(MAX_FILE_SIZE)}."
        end
      end

      extend ActiveSupport::Concern

      included do
        def self.blueprint_store_for(_instance, trigger)
          MemoryStore.new(namespace: "#{trigger.outbound_connection.uuid}:blueprint")
        end

        def blueprint_store
          @blueprint_store ||= blueprint_store_for
        end

        private

        def blueprint_store_for
          BlueprintStoreWrapper.new(
            self.class.blueprint_store_for(self, trigger),
            trigger.trigger_template.blueprint_filenames,
          )
        end
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::BlueprintStore)
