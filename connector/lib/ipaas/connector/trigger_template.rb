module IPaaS
  module Connector
    class TriggerTemplate
      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::UuidMixin
      include IPaaS::Job::Context # for validation of (schema) functions
      include IPaaS::Connector::Dsl::HelpersMixin

      # Must start with letter or number
      # Can contain letters, numbers, underscore, hyphen
      # Optionally ends with .extension
      # No spaces or special characters
      # No hidden files (starting with .)
      VALID_BLUEPRINT_FILENAME = /\A[a-zA-Z0-9][a-zA-Z0-9_-]*(\.[a-zA-Z0-9]+)?\z/
      MAX_NR_OF_BLUEPRINT_FILES = 50

      attr_accessor :connector

      attribute :name, required: true, length: { in: 6..120 }
      attribute :avatar, format: { with: IPaaS::Connector::Types::AVATAR_REGEXP }
      attribute :description
      attribute :outbound_traffic, type: Boolean, default: false
      attribute :blueprint_filenames, type: [String]
      attribute :internal_only, type: Boolean, default: false

      schema :config_schema do
        field :url_postfix,
              'URL postfix',
              :string,
              hint: 'The given postfix will be added to the end of the endpoint URL.',
              pattern: %r{\A[\w/]*([?&]([\w%]+)=\w+)*\z},
              visibility: 'optional'

        field :discard_trigger_event,
              'Discard trigger event',
              :boolean,
              hint: 'Set to true to discard the trigger event and execute none of the actions of the runbook.',
              visibility: 'optional'
      end
      schema :output_schema do
        field :deduplication_id,
              'Deduplication ID',
              :string,
              hint: 'ID used to deduplicate events.'
      end

      function :extract_blueprint
      function :provision
      function :deprovision
      function :parse, required: true
      function :respond_with

      validate :blueprint_filenames_valid?
      validate :extract_blueprint_valid?

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :uuid)
      end

      private

      def blueprint_filenames_valid?
        return if blueprint_filenames.blank?

        errors.add(:blueprint_filenames, 'requires outbound traffic.') unless outbound_traffic
        validate_blueprint_filenames_format
        validate_nr_of_blueprint_filenames
      end

      def validate_blueprint_filenames_format
        invalid = blueprint_filenames.reject { |filename| filename.match(VALID_BLUEPRINT_FILENAME) }.sort
        return if invalid.empty?

        errors.add(:blueprint_filenames, "contains invalid characters: '#{invalid.join("', '")}'.")
      end

      def validate_nr_of_blueprint_filenames
        return unless blueprint_filenames.size > MAX_NR_OF_BLUEPRINT_FILES

        errors.add(:blueprint_filenames,
                   "Too many files #{blueprint_filenames.size}, allowed: #{MAX_NR_OF_BLUEPRINT_FILES}.")
      end

      def extract_blueprint_valid?
        return if blueprint_filenames.blank?

        errors.add(:extract_blueprint, "function is required, define 'extract do ... end'.") if extract_blueprint.blank?
        errors.add(:provision, "function is required, define 'provision do ... end'.") if provision.blank?
      end
    end
  end
end
