require 'spec_helper'

# The helpers that put a string on the wire. Anything interpolated into one of these calls becomes
# a URL path segment.
CLICKUP_REQUEST_BUILDERS = %w[
  clickup_get clickup_post clickup_put clickup_delete
  fetch_options_keyed multipart_post
  http_get http_post http_put http_delete
].freeze

# BASE_URL is a constant and `path` is the already-assembled argument of a transport helper.
# Neither is a caller-supplied id.
CLICKUP_PATH_PLUMBING = %w[BASE_URL path].freeze

# Every ClickUp id is checked at its own call site rather than once on the assembled path, because
# a slash-bearing id reads as a run of legal segments after joining. That per-site guard has no
# backstop: Upload Task Attachment shipped without it while the other call sites had it, and
# nothing failed. This sweep is the backstop. It reads the connector source rather than driving the
# actions, because the property is syntactic: no id may reach a request builder unguarded.
describe 'ClickUp path safety' do
  let(:source_path) do
    File.expand_path('../../../../../fixtures/clickup_connector/clickup_connector.rb', __dir__)
  end
  let(:source) { File.read(source_path) }
  let(:builder_call) { Regexp.new("\\b(?:#{CLICKUP_REQUEST_BUILDERS.join('|')})\\(") }

  # A local counts as safe once it is assigned from one of the two guards, which is the shape the
  # read actions use: `space_id = helpers.safe_id(input[:space_id], 'space_id')`. The name is
  # trusted only until the next block opens: matching file-wide would let one action's guarded
  # `space_id` vouch for every other action's, and this sweep is the only backstop those call
  # sites have.
  BLOCK_START = /^\s*(?:helper\s+:[\w!?]+|run|provision|deprovision|parse|validate|options)\b.*\bdo\b/
  GUARD_ASSIGNMENT = /(\w+)\s*=\s*helpers\.(?:safe_id|connection_workspace_id)\b/

  def guarded?(expression, locals)
    expression.include?('safe_id') ||
      expression.include?('connection_workspace_id') ||
      CLICKUP_PATH_PLUMBING.include?(expression) ||
      locals.include?(expression)
  end

  def unguarded_interpolations(source, builder_call)
    locals = []

    source.each_line.with_index(1).flat_map do |line, number|
      locals = [] if line.match?(BLOCK_START)
      locals |= line.scan(GUARD_ASSIGNMENT).flatten

      next [] unless line.match?(builder_call)

      line.scan(/\#\{([^}]*)\}/).flatten.map(&:strip)
          .reject { |expression| guarded?(expression, locals) }
          .map { |expression| "line #{number}: #{expression}" }
    end
  end

  it 'passes every id interpolated into a request path through safe_id' do
    expect(unguarded_interpolations(source, builder_call)).to eq([])
  end

  # Proves the sweep can fail. Without it a broken scan would report a clean file forever.
  it 'reports a call site that interpolates an id directly' do
    guarded = "multipart_post(\"\#{BASE_URL}/task/\#{helpers.safe_id(input[:task_id], 'task_id')}/attachment\""
    unguarded = "multipart_post(\"\#{BASE_URL}/task/\#{input[:task_id]}/attachment\""
    regression = source.sub(guarded, unguarded)

    expect(regression).not_to eq(source), 'the guarded upload call site moved; update this mutation'
    expect(unguarded_interpolations(regression, builder_call))
      .to contain_exactly(a_string_including('input[:task_id]'))
  end

  # The locals branch is the one that can fail quietly, and the mutation above cannot exercise it:
  # `input[:task_id]` is never a local name, so it only shows that the scan runs. The two blocks are
  # appended to the real connector rather than scanned alone, so the example still depends on that
  # file. They are `run do` because that is the shape every guarded call site uses: with `run`
  # dropped from BLOCK_START the second block keeps the first one's space_id and reports nothing.
  it 'does not let a local guarded in one block vouch for the same name in another' do
    regression = source + <<~'RUBY'

      run do
        space_id = helpers.safe_id(input[:space_id], 'space_id')
        helpers.clickup_get("space/#{space_id}/folder")
      end

      run do
        space_id = input[:space_id]
        helpers.clickup_get("space/#{space_id}/folder")
      end
    RUBY

    expect(unguarded_interpolations(regression, builder_call)).to contain_exactly(a_string_including('space_id'))
  end

  # So that an empty result above means "all guarded" rather than "nothing was scanned".
  it 'finds the request builders it is meant to check' do
    scanned = source.each_line.count { |line| line.match?(builder_call) }

    expect(scanned).to be >= 20
  end
end
