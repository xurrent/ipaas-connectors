require 'spec_helper'

describe 'endoflife.date: get release cycle', :action, :endoflife_date do
  let(:action_template_id) { '01a1d2c9-68db-7bae-8b27-6752a10ea0b5' }
  let(:release_path) { '/products/ubuntu/releases/22.04' }

  describe 'input_schema' do
    it 'requires a product and a release' do
      expect(action.input_schema.field(:product).required).to be true
      expect(action.input_schema.field(:release).required).to be true
    end

    it 'is invalid without a release' do
      expect { run_action({ product: 'ubuntu' }) }.to raise_error(IPaaS::Error, /release/i)
    end
  end

  describe 'run' do
    context 'when the release cycle exists' do
      before { stub_eol(release_path, body: eol_body(release_json)) }

      let(:output) { run_action({ product: 'ubuntu', release: '22.04' }) }

      it 'sets found and echoes the requested product' do
        expect(output[:found]).to be true
        expect(output[:product]).to eq('ubuntu')
      end

      it 'returns the release cycle fields in snake_case' do
        expect(output[:name]).to eq('22.04')
        expect(output[:codename]).to eq('Jammy Jellyfish')
        expect(output[:label]).to eq("22.04 'Jammy Jellyfish' (LTS)")
        expect(output[:is_lts]).to be true
        expect(output[:is_eoas]).to be true
        expect(output[:is_eol]).to be false
        expect(output[:is_eoes]).to be false
        expect(output[:is_maintained]).to be true
      end

      it 'returns the dates' do
        expect(output[:release_date].to_s).to eq('2022-04-21')
        expect(output[:eoas_from].to_s).to eq('2024-09-30')
        expect(output[:eol_from].to_s).to eq('2027-06-01')
        expect(output[:eoes_from].to_s).to eq('2032-04-21')
        expect(output[:lts_from]).to be_nil
      end

      it 'returns the latest version' do
        expect(output[:latest][:name]).to eq('22.04.5')
        expect(output[:latest][:date].to_s).to eq('2024-09-12')
        expect(output[:latest][:link]).to eq('https://wiki.ubuntu.com/JammyJellyfish/ReleaseNotes/')
      end

      it 'returns the response metadata' do
        expect(output[:schema_version]).to eq('1.2.1')
        expect(output[:generated_at]).to be_present
      end
    end

    it 'passes custom fields through with their original names' do
      stub_eol(release_path, body: eol_body(release_json(custom: { chromeVersion: 'M120' })))
      output = run_action({ product: 'ubuntu', release: '22.04' })
      expect(output[:custom].to_h.transform_keys(&:to_s)).to eq({ 'chromeVersion' => 'M120' })
    end

    it 'trims and lowercases the product name' do
      stub_eol(release_path, body: eol_body(release_json))
      expect(run_action({ product: ' Ubuntu ', release: '22.04' })[:found]).to be true
    end

    it 'publishes a release name containing a slash under a hyphen' do
      stub_eol('/products/ubuntu/releases/a-b', body: eol_body(release_json(name: 'a/b')))
      expect(run_action({ product: 'ubuntu', release: 'a/b' })[:found]).to be true
    end

    context 'when endoflife.date does not know the release' do
      it 'succeeds with found false instead of failing' do
        stub_eol('/products/ubuntu/releases/99.99', status: 404, body: '<html>Not found</html>')
        output = run_action({ product: 'ubuntu', release: '99.99' })
        expect(output[:found]).to be false
        expect(output[:product]).to eq('ubuntu')
        expect(output[:name]).to eq('99.99')
      end
    end

    context 'when the product was renamed or an alias is used' do
      it 'follows a relative redirect' do
        location = '/api/v1/products/ubuntu/releases/22.04'
        stub_eol('/products/ubuntu-linux/releases/22.04', status: 301, headers: { 'Location' => location })
        stub_eol(release_path, body: eol_body(release_json))
        output = run_action({ product: 'ubuntu-linux', release: '22.04' })
        expect(output[:found]).to be true
        expect(output[:product]).to eq('ubuntu-linux')
      end

      it 'follows an absolute redirect on endoflife.date' do
        location = "#{eol_api}#{release_path}"
        stub_eol('/products/ubuntu-linux/releases/22.04', status: 301, headers: { 'Location' => location })
        stub_eol(release_path, body: eol_body(release_json))
        expect(run_action({ product: 'ubuntu-linux', release: '22.04' })[:found]).to be true
      end

      it 'refuses a redirect to another host' do
        stub_eol(release_path, status: 301, headers: { 'Location' => 'https://example.com/api/v1/x' })
        expect { run_action({ product: 'ubuntu', release: '22.04' }) }
          .to raise_error(IPaaS::Job::FailJob, /unexpected address/)
      end

      it 'stops after too many redirects' do
        stub_eol(release_path, status: 301, headers: { 'Location' => "/api/v1#{release_path}" })
        expect { run_action({ product: 'ubuntu', release: '22.04' }) }
          .to raise_error(IPaaS::Job::FailJob, /redirected too many times/)
      end
    end

    context 'when endoflife.date is unavailable or limiting requests' do
      it 'backs off on 429 using the default delay' do
        stub_eol(release_path, status: 429)
        Timecop.freeze do
          expect { run_action({ product: 'ubuntu', release: '22.04' }) }
            .to raise_error(IPaaS::Job::RescheduleJob, /rate limit/) do |error|
              expect(error.reschedule_after).to eq(60.seconds.from_now)
            end
        end
      end

      it 'backs off on 429 using Retry-After' do
        stub_eol(release_path, status: 429, headers: { 'Retry-After' => '30' })
        Timecop.freeze do
          expect { run_action({ product: 'ubuntu', release: '22.04' }) }
            .to raise_error(IPaaS::Job::RescheduleJob) do |error|
              expect(error.reschedule_after).to eq(30.seconds.from_now)
            end
        end
      end

      it 'backs off on 502' do
        stub_eol(release_path, status: 502)
        Timecop.freeze do
          expect { run_action({ product: 'ubuntu', release: '22.04' }) }
            .to raise_error(IPaaS::Job::RescheduleJob, /not available/) do |error|
              expect(error.reschedule_after).to eq(60.seconds.from_now)
            end
        end
      end

      it 'backs off on 503' do
        stub_eol(release_path, status: 503)
        Timecop.freeze do
          expect { run_action({ product: 'ubuntu', release: '22.04' }) }
            .to raise_error(IPaaS::Job::RescheduleJob, /not available/) do |error|
              expect(error.reschedule_after).to eq(60.seconds.from_now)
            end
        end
      end
    end

    context 'when the response is unusable' do
      it 'fails on an unexpected status' do
        stub_eol(release_path, status: 500, body: 'boom')
        expect { run_action({ product: 'ubuntu', release: '22.04' }) }
          .to raise_error(IPaaS::Job::FailJob, /request failed \(HTTP 500\)/)
      end

      it 'fails on a body that is not JSON' do
        stub_eol(release_path, body: 'not json')
        expect { run_action({ product: 'ubuntu', release: '22.04' }) }
          .to raise_error(IPaaS::Job::FailJob, /not JSON/)
      end

      it 'fails on JSON that is not an object' do
        stub_eol(release_path, body: '[]')
        expect { run_action({ product: 'ubuntu', release: '22.04' }) }
          .to raise_error(IPaaS::Job::FailJob, /unexpected response/)
      end
    end

    describe 'unmodelled fields' do
      it 'stays silent when every field is modelled' do
        messages = captured_logs
        stub_eol(release_path, body: eol_body(release_json))
        run_action({ product: 'ubuntu', release: '22.04' })
        expect(messages.grep(/does not model/)).to be_empty
      end

      it 'names a field the output schema does not model' do
        messages = captured_logs
        stub_eol(release_path, body: eol_body(release_json(brandNewField: 1)))
        run_action({ product: 'ubuntu', release: '22.04' })
        expect(messages.grep(/does not model/).first).to include('brand_new_field')
      end
    end
  end
end
