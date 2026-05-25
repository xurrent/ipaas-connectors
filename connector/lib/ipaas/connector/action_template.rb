module IPaaS
  module Connector
    class ActionTemplate
      include IPaaS::Connector::Common::Model
      include IPaaS::Connector::Common::UuidMixin
      include IPaaS::Job::Context # for validation of (schema) functions
      include IPaaS::Connector::Dsl::HelpersMixin

      attr_accessor :connector

      attribute :name, required: true, length: { in: 4..120 }
      attribute :avatar, format: { with: IPaaS::Connector::Types::AVATAR_REGEXP }
      attribute :description
      attribute :nested, type: Boolean, default: false
      attribute :disable_output_schema_name_mapping, type: Boolean, default: false

      schema :input_schema
      schema :output_schema, array: true
      schema :iteration_state_schema

      function :run, required: true

      def to_h_ref
        IPaaS::Connector::Common::Serializer.to_h(self, :uuid)
      end
    end
  end
end
