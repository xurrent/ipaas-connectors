require_relative 'graphql_introspection_helper'

# Three levels of nesting below the queried node: Task -> workflow -> tasks -> approvals.
module GraphqlDeepNestingHelper
  include GraphqlIntrospectionHelper

  def gql_deep_obj(name, fields)
    { 'kind' => 'OBJECT', 'name' => name, 'description' => nil,
      'fields' => fields, 'inputFields' => nil, 'enumValues' => nil, 'possibleTypes' => nil, }
  end

  def gql_deep_field(name, kind, type, args = [])
    { 'name' => name, 'description' => nil, 'args' => args,
      'type' => { 'kind' => kind, 'name' => type, 'ofType' => nil }, }
  end

  def gql_deep_nodes(type)
    { 'name' => 'nodes', 'description' => nil, 'args' => [],
      'type' => { 'kind' => 'LIST', 'name' => nil,
                  'ofType' => { 'kind' => 'OBJECT', 'name' => type, 'ofType' => nil }, }, }
  end

  def gql_deep_page_args
    [{ 'name' => 'first', 'description' => nil,
       'type' => { 'kind' => 'SCALAR', 'name' => 'Int', 'ofType' => nil }, 'defaultValue' => nil, },
     { 'name' => 'after', 'description' => nil,
       'type' => { 'kind' => 'SCALAR', 'name' => 'String', 'ofType' => nil }, 'defaultValue' => nil, },]
  end

  def graphql_connector_introspection_schema
    { 'queryType' => { 'name' => 'Query' },
      'mutationType' => nil,
      'types' => gql_deep_type_defs, }
  end

  def gql_deep_type_defs
    [gql_deep_query_type_def, gql_deep_task_connection_type_def, gql_deep_task_type_def,
     gql_deep_workflow_type_def, gql_deep_approval_connection_type_def,
     gql_deep_approval_type_def, gql_deep_task_template_type_def, gql_deep_page_info_type_def,]
  end

  def gql_deep_query_type_def
    gql_deep_obj('Query', [gql_deep_field('tasks', 'OBJECT', 'TaskConnection', gql_deep_page_args)])
  end

  def gql_deep_task_connection_type_def
    gql_deep_obj('TaskConnection',
                 [gql_deep_nodes('Task'), gql_deep_field('pageInfo', 'OBJECT', 'PageInfo'),
                  gql_deep_field('totalCount', 'SCALAR', 'Int'),])
  end

  def gql_deep_task_type_def
    gql_deep_obj('Task',
                 [gql_deep_field('id', 'SCALAR', 'ID'), gql_deep_field('subject', 'SCALAR', 'String'),
                  gql_deep_field('workflow', 'OBJECT', 'Workflow'),
                  gql_deep_field('approvals', 'OBJECT', 'ApprovalConnection', gql_deep_page_args),
                  gql_deep_field('template', 'OBJECT', 'TaskTemplate'),])
  end

  def gql_deep_workflow_type_def
    gql_deep_obj('Workflow',
                 [gql_deep_field('id', 'SCALAR', 'ID'), gql_deep_field('subject', 'SCALAR', 'String'),
                  gql_deep_field('tasks', 'OBJECT', 'TaskConnection', gql_deep_page_args),])
  end

  def gql_deep_approval_connection_type_def
    gql_deep_obj('ApprovalConnection',
                 [gql_deep_nodes('Approval'), gql_deep_field('pageInfo', 'OBJECT', 'PageInfo'),
                  gql_deep_field('totalCount', 'SCALAR', 'Int'),])
  end

  def gql_deep_approval_type_def
    gql_deep_obj('Approval',
                 [gql_deep_field('id', 'SCALAR', 'ID'), gql_deep_field('status', 'SCALAR', 'String')])
  end

  def gql_deep_task_template_type_def
    gql_deep_obj('TaskTemplate',
                 [gql_deep_field('id', 'SCALAR', 'ID'), gql_deep_field('subject', 'SCALAR', 'String')])
  end

  def gql_deep_page_info_type_def
    gql_deep_obj('PageInfo',
                 [gql_deep_field('endCursor', 'SCALAR', 'String'),
                  gql_deep_field('hasNextPage', 'SCALAR', 'Boolean'),])
  end
end
