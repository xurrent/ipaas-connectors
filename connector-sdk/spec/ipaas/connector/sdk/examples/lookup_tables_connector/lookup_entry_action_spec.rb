require 'spec_helper'

describe 'Lookup Entry', :action, :lookup_tables do
  let(:action_template_id) { '01a19c65-6237-7115-942e-6bd21ea2be67' }

  it 'returns the oldest entry matching every mapped column' do
    add(device => 'OTHER', ci => 'ci_0')
    first = add(device => 'JAMF-0042', ci => 'ci_1')
    add(device => 'JAMF-0042', ci => 'ci_2')

    expect(run_action(per_column(:match, { device => 'JAMF-0042' }))).to eq(first.deep_stringify_keys)
  end

  it 'fails the step when nothing matches' do
    add(device => 'JAMF-0042')

    expect { run_action(per_column(:match, { device => 'NOPE' })) }
      .to raise_error(IPaaS::Job::FailJob, 'No entry in "device_map" matches')
  end
end
