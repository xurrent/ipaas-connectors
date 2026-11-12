require 'spec_helper'

describe 'Public Holidays List Public Holidays Action', :action, :public_holidays do
  let(:action_template_id) { '01a1d0f0-edb0-76f8-94b0-39b230288208' }
  let(:holidays_url) { "#{base_url}/api/v3/PublicHolidays/2027/DE" }

  let(:german_holidays) do
    [
      { date: '2027-01-01', localName: 'Neujahr', name: "New Year's Day", countryCode: 'DE', fixed: true,
        global: true, counties: nil, launchYear: nil, types: ['Public'], },
      { date: '2027-01-06', localName: 'Heilige Drei Könige', name: 'Epiphany', countryCode: 'DE', fixed: true,
        global: false, counties: %w[DE-BW DE-BY DE-ST], launchYear: nil, types: ['Public'], },
      { date: '2027-02-14', localName: 'Valentinstag', name: "Valentine's Day", countryCode: 'DE', fixed: true,
        global: true, counties: nil, launchYear: nil, types: ['Observance'], },
      { date: '2027-03-08', localName: 'Internationaler Frauentag', name: "International Women's Day",
        countryCode: 'DE', fixed: true, global: false, counties: %w[DE-BE DE-MV], launchYear: 2019,
        types: nil, },
      { date: '2027-10-03', localName: 'Tag der Deutschen Einheit', name: 'German Unity Day', countryCode: 'DE',
        fixed: true, global: true, counties: nil, launchYear: 1990, types: %w[Public Bank], },
    ]
  end

  def input(**overrides)
    { country_code: 'DE', year: 2027, region: nil, days_off_only: true }.merge(overrides)
  end

  def stub_holidays(url: holidays_url, status: 200, body: german_holidays.to_json)
    stub_request(:get, url).to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def names(result)
    result['holidays'].pluck('name')
  end

  describe 'input_schema' do
    it 'requires the country code and year, and defaults days off only to on' do
      schema = action.input_schema
      expect([schema.field(:country_code).required, schema.field(:year).required]).to eq([true, true])
      expect(schema.field(:days_off_only).default).to be(true)
    end
  end

  describe 'run' do
    context 'with the defaults' do
      before { stub_holidays }

      it 'returns every day off of the country, nationwide and regional' do
        result = run_action(input)
        expect(result).to include('country_code' => 'DE', 'year' => 2027, 'count' => 3)
        expect(names(result)).to eq(["New Year's Day", 'Epiphany', 'German Unity Day'])
      end

      it 'maps a regional holiday' do
        expect(run_action(input)['holidays'][1]).to eq(
          'date' => '2027-01-06', 'name' => 'Epiphany', 'local_name' => 'Heilige Drei Könige',
          'nationwide' => false, 'regions' => %w[DE-BW DE-BY DE-ST], 'types' => ['Public'],
          'fixed' => true, 'launch_year' => nil
        )
      end

      it 'maps a nationwide holiday with empty regions and its first year' do
        expect(run_action(input)['holidays'][2])
          .to include('nationwide' => true, 'regions' => [], 'types' => %w[Public Bank], 'launch_year' => 1990)
      end

      it 'treats an empty days off only as on' do
        expect(run_action(input(days_off_only: nil))['count']).to eq(3)
      end
    end

    context 'with a region' do
      before { stub_holidays }

      it 'keeps the nationwide holidays and those of the region, whatever its case and spacing' do
        expect(names(run_action(input(region: ' de-by ')))).to eq(["New Year's Day", 'Epiphany', 'German Unity Day'])
      end

      it 'drops the holidays of other regions' do
        expect(names(run_action(input(region: 'DE-NW')))).to eq(["New Year's Day", 'German Unity Day'])
      end

      it 'refuses a region of another country' do
        expect { run_action(input(region: 'US-CA')) }
          .to raise_error(IPaaS::Job::FailJob, "Region 'US-CA' is not in DE. Use a code that starts with DE-.")
      end
    end

    context 'with days off only off' do
      before { stub_holidays }

      it 'includes observances and holidays without types' do
        result = run_action(input(days_off_only: false))
        expect(result['count']).to eq(5)
        expect(result['holidays'][3]).to include('name' => "International Women's Day", 'types' => [])
      end
    end

    context 'with the country code' do
      it 'trims and upcases it' do
        stub = stub_holidays(url: "#{base_url}/api/v3/PublicHolidays/2027/NL", body: '[]')
        expect(run_action(input(country_code: ' nl '))).to include('country_code' => 'NL', 'count' => 0)
        expect(stub).to have_been_requested
      end

      it 'refuses one that is not two letters' do
        expect { run_action(input(country_code: 'NLD')) }
          .to raise_error(IPaaS::Job::FailJob, "'NLD' is not a two-letter country code, such as NL or US.")
      end
    end

    context 'when Nager.Date refuses the request' do
      it 'explains a country it has no holidays for' do
        stub_holidays(url: "#{base_url}/api/v3/PublicHolidays/2027/IN", status: 204, body: '')
        expect { run_action(input(country_code: 'IN')) }
          .to raise_error(IPaaS::Job::FailJob,
                          'Nager.Date has no holidays for IN. See https://date.nager.at/Country for the countries ' \
                          'it supports.')
      end

      it 'explains an unknown country with the problem detail' do
        stub_holidays(url: "#{base_url}/api/v3/PublicHolidays/2027/XX", status: 404,
                      body: { title: 'Unknown country code', status: 404,
                              detail: 'The country code provided is invalid or not recognized.', }.to_json)
        expect { run_action(input(country_code: 'XX')) }
          .to raise_error(IPaaS::Job::FailJob,
                          'Nager.Date: The country code provided is invalid or not recognized. (HTTP 404)')
      end

      it 'explains an unsupported year with the validation errors' do
        stub_holidays(url: "#{base_url}/api/v3/PublicHolidays/1900/DE", status: 400,
                      body: { title: 'One or more validation errors occurred.', status: 400,
                              errors: { year: ["The specified year '1900' is not supported."] }, }.to_json)
        expect { run_action(input(year: 1900)) }
          .to raise_error(IPaaS::Job::FailJob,
                          "Nager.Date API error (HTTP 400): The specified year '1900' is not supported.")
      end

      it 'falls back to the problem title' do
        stub_holidays(status: 500, body: { title: 'Internal Server Error', status: 500 }.to_json)
        expect { run_action(input) }
          .to raise_error(IPaaS::Job::FailJob, 'Nager.Date API error (HTTP 500): Internal Server Error')
      end

      it 'falls back to the body when the error is not a problem object' do
        stub_holidays(status: 500, body: '["boom"]')
        expect { run_action(input) }.to raise_error(IPaaS::Job::FailJob, 'Nager.Date API error (HTTP 500): ["boom"]')
      end

      it 'truncates a long error body that is not JSON' do
        stub_holidays(status: 500, body: 'x' * 400)
        expect { run_action(input) }
          .to raise_error(IPaaS::Job::FailJob, "Nager.Date API error (HTTP 500): #{'x' * 297}...")
      end
    end

    context 'when Nager.Date is busy' do
      it 'retries after the Retry-After header' do
        stub_request(:get, holidays_url).to_return(status: 429, headers: { 'Retry-After' => '5' })
        expect_reschedule_after(5) { run_action(input) }
      end

      it 'retries after 60 seconds without a Retry-After header' do
        stub_request(:get, holidays_url).to_return(status: 503)
        expect_reschedule_after(60) { run_action(input) }
      end
    end

    context 'when Nager.Date answers with an unexpected body' do
      it 'fails on a body that is not JSON' do
        stub_holidays(body: '<html>')
        expect { run_action(input) }
          .to raise_error(IPaaS::Job::FailJob, "Nager.Date response was not valid JSON: '<html>'")
      end

      it 'fails on JSON that is not a list' do
        stub_holidays(body: '{"unexpected":true}')
        expect { run_action(input) }
          .to raise_error(IPaaS::Job::FailJob, %(Nager.Date response was not a JSON array: '{"unexpected":true}'))
      end
    end
  end
end
