# Shared assertion for request #78064178: the GraphQL connectors define their
# input_schema `after_update` proc in the same block scope as the
# `schema_data = cache_read('gql_schema')` local. Because Ruby closures capture
# the whole enclosing binding, and the proc is stored on the cached Schema, a
# live `schema_data` would pin the multi-MB parsed introspection schema per
# cached solution version (GUI OOM). The fix releases that local before the
# closure is created.
module SchemaClosureHelper
  # Fails if the schema's after_update closure still retains the parsed schema.
  # Robust to a future helper-extraction refactor: if `schema_data` is no longer
  # a local in the closure's binding at all, that is the strongest possible form
  # of "not captured" and passes.
  def expect_after_update_not_to_retain_schema(schema)
    after_update = schema.after_update
    expect(after_update).to be_a(Proc)

    proc_binding = after_update.binding
    captured = nil
    captured = proc_binding.local_variable_get(:schema_data) if proc_binding.local_variables.include?(:schema_data)
    expect(captured).to be_nil
  end
end

RSpec.configure { |config| config.include SchemaClosureHelper }
