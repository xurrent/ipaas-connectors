module GraphqlSchemaHelper
  module TypeRef
    class << self
      def scalar(name)
        { 'kind' => 'SCALAR', 'name' => name, 'ofType' => nil }
      end

      def object(name)
        { 'kind' => 'OBJECT', 'name' => name, 'ofType' => nil }
      end

      def enum(name)
        { 'kind' => 'ENUM', 'name' => name, 'ofType' => nil }
      end

      def input_object(name)
        { 'kind' => 'INPUT_OBJECT', 'name' => name, 'ofType' => nil }
      end

      def non_null(inner)
        { 'kind' => 'NON_NULL', 'name' => nil, 'ofType' => inner }
      end

      def list(inner)
        { 'kind' => 'LIST', 'name' => nil, 'ofType' => inner }
      end

      def fld(name, type, args: [], description: nil)
        h = { 'name' => name, 'type' => type, 'args' => args }
        h['description'] = description if description
        h
      end

      def arg(name, type)
        { 'name' => name, 'type' => type, 'defaultValue' => nil }
      end

      def input_fld(name, type, description: nil)
        h = { 'name' => name, 'type' => type, 'defaultValue' => nil }
        h['description'] = description if description
        h
      end

      def obj_type(name, fields:)
        { 'kind' => 'OBJECT', 'name' => name, 'fields' => fields,
          'inputFields' => nil, 'enumValues' => nil, 'possibleTypes' => nil, }
      end

      def input_type(name, input_fields:)
        { 'kind' => 'INPUT_OBJECT', 'name' => name, 'fields' => nil,
          'inputFields' => input_fields,
          'enumValues' => nil, 'possibleTypes' => nil, }
      end

      def enum_type(name, values:)
        { 'kind' => 'ENUM', 'name' => name, 'fields' => nil,
          'inputFields' => nil, 'enumValues' => values,
          'possibleTypes' => nil, }
      end

      def id_field(desc = nil)
        fld('id', non_null(scalar('ID')), description: desc)
      end

      def string_field(name, desc = nil)
        fld(name, scalar('String'), description: desc)
      end
    end
  end

  def self.schema_data # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    t = TypeRef
    {
      'queryType' => { 'name' => 'Query' },
      'mutationType' => { 'name' => 'Mutation' },
      'types' => [
        t.obj_type('Query', fields: [
          { 'name' => 'people', 'description' => 'List of people',
            'type' => t.object('PersonConnection'),
            'args' => [
              t.arg('first', t.scalar('Int')),
              t.arg('after', t.scalar('String')),
              t.arg('view', t.enum('PersonView')),
              t.arg('filter', t.input_object('PersonFilter')),
              t.arg('order', t.list(t.input_object('PersonOrder'))),
            ], },
          { 'name' => 'me', 'description' => 'Current user',
            'type' => t.object('Person'), 'args' => [], },
        ]),
        t.obj_type('Mutation', fields: [
          { 'name' => 'requestCreate', 'description' => 'Create a request',
            'type' => t.object('RequestCreatePayload'),
            'args' => [
              t.arg('input', t.non_null(t.input_object('RequestCreateInput'))),
            ], },
        ]),
        t.obj_type('PersonConnection', fields: [
          t.fld('nodes', t.list(t.object('Person'))),
          t.fld('pageInfo', t.object('PageInfo')),
          t.fld('totalCount', t.scalar('Int')),
        ]),
        t.obj_type('Person', fields: [
          t.id_field('Unique identifier.'),
          t.string_field('name', 'Full name.'),
          t.string_field('primaryEmail', 'Primary email.'),
          t.fld('disabled', t.scalar('Boolean')),
          t.fld('organization', t.object('Organization'),
                description: 'Organization.'),
        ]),
        t.obj_type('Organization', fields: [
          t.id_field,
          t.string_field('name'),
        ]),
        t.obj_type('RequestCreatePayload', fields: [
          t.fld('request', t.object('Request')),
          t.fld('errors', t.list(t.object('MutationError'))),
        ]),
        t.input_type('RequestCreateInput', input_fields: [
          t.input_fld('subject', t.non_null(t.scalar('String'))),
          t.input_fld('category', t.enum('RequestCategory')),
          t.input_fld('source', t.scalar('String')),
          t.input_fld('sourceID', t.scalar('String')),
          t.input_fld('customFields',
                      t.list(t.non_null(t.input_object('CustomFieldInput')))),
          t.input_fld('clientMutationId', t.scalar('String')),
        ]),
        t.input_type('CustomFieldInput', input_fields: [
          t.input_fld('id', t.non_null(t.scalar('String'))),
          t.input_fld('value', t.scalar('String')),
        ]),
        t.obj_type('Request', fields: [
          t.id_field,
          t.string_field('subject'),
        ]),
        t.obj_type('MutationError', fields: [
          t.string_field('message'),
          t.fld('path', t.list(t.scalar('String'))),
        ]),
        t.obj_type('PageInfo', fields: [
          t.fld('hasNextPage', t.non_null(t.scalar('Boolean'))),
          t.string_field('endCursor'),
        ]),
        t.enum_type('PersonView', values: [
          { 'name' => 'all', 'description' => 'All people' },
          { 'name' => 'disabled', 'description' => 'Disabled people' },
        ]),
        t.enum_type('RequestCategory', values: [
          { 'name' => 'incident' },
          { 'name' => 'rfc' },
        ]),
        t.input_type('PersonFilter', input_fields: [
          t.input_fld('query', t.scalar('String'), description: 'Search by keyword'),
          t.input_fld('disabled', t.scalar('Boolean')),
        ]),
        t.input_type('PersonOrder', input_fields: [
          t.input_fld('field', t.non_null(t.enum('PersonOrderField')),
                      description: 'Field to order by'),
          t.input_fld('direction', t.enum('OrderDirection'),
                      description: 'Order direction'),
        ]),
        t.enum_type('PersonOrderField', values: [
          { 'name' => 'name' },
          { 'name' => 'createdAt' },
        ]),
        t.enum_type('OrderDirection', values: [
          { 'name' => 'asc', 'description' => 'Ascending' },
          { 'name' => 'desc', 'description' => 'Descending' },
        ]),
      ],
    }
  end
end
