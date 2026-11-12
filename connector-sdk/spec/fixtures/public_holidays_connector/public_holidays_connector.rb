class PublicHolidaysConnector < IPaaS::Connector::Definition
  connector '01a1d0f0-edb0-71a4-a345-f2b92534e646' do
    name 'Public Holidays Connector'
    avatar '/assets/icons/public-holidays.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Looks up the public holidays of more than 100 countries using [Nager.Date](https://date.nager.at), a free and open source holiday service. Use it to keep the holidays of Xurrent calendars, and with them service hours and SLA targets, up to date every year.

      ## Prerequisites
      None. Nager.Date needs no account. Check that your country is in the [list of supported countries](https://date.nager.at/Country): India and the United Arab Emirates, for example, are not.

      ## Authentication
      None. The connection only holds the **Base URL**, `https://date.nager.at`. Change it only when you host your own copy of Nager.Date.

      ## Actions
      ### List public holidays
      Lists the holidays of one country in one year, in date order.

      | Input | Description |
      |---|---|
      | Country code | Two-letter ISO 3166 code, such as `NL` or `US`. |
      | Year | The year, such as `2027`. |
      | Region | Optional ISO 3166-2 code, such as `DE-BY`. Empty: every holiday of the country, nationwide and regional. Set: only the holidays observed in that region. |
      | Days off only | On by default: skips holidays that are not days off, such as observances. |

      | Output | Description |
      |---|---|
      | Country code, Year | The country and year that were looked up. |
      | Count | The number of holidays. |
      | Holidays | Per holiday: Date, Name (English), Local name, Nationwide, Regions (empty when nationwide), Types (`Public`, `Bank`, `School`, `Authorities`, `Optional` or `Observance`), Fixed date and Since year. |

      ## Error handling
      | HTTP status | Behaviour |
      |---|---|
      | 204 | Fails: Nager.Date has no holidays for the country |
      | 400 | Fails: Nager.Date does not support the year |
      | 404 | Fails: unknown country code |
      | 429, 502, 503, 504 | Retries after the `Retry-After` header, 60 seconds when absent |
      | Other 4xx/5xx | Fails with Nager.Date's error message |

      ## References
      - [Nager.Date API](https://date.nager.at/Api)
      - [Supported countries](https://date.nager.at/Country)
    END_OF_DESCRIPTION

    COUNTRY_CODE_PATTERN = /\A[A-Z]{2}\z/
    DAY_OFF_TYPES = %w[Public Bank].freeze
    TRUNCATED_BODY_LIMIT = 300

    outbound_connection do
      config_schema do
        field :base_url, 'Base URL', :uri,
              required: true,
              default: 'https://date.nager.at',
              hint: 'Change it only when you host your own copy of Nager.Date.'
      end

      config_tester do
        response = http_get(helpers.holidays_url('/api/v3/AvailableCountries'), nil, nil, open_timeout: 2, timeout: 5)
        if response.status == 200
          countries = helpers.parse_holidays_array(response)
          { status: :success, message: "Connected to Nager.Date: #{countries.size} countries available." }
        else
          { status: :error,
            message: "Nager.Date connection check failed (HTTP #{response.status}): " \
                     "#{helpers.holidays_error_message(response)}", }
        end
      end
    end

    action '01a1d0f0-edb0-76f8-94b0-39b230288208' do
      name 'List public holidays'
      avatar '/assets/icons/public-holidays.svg'
      description <<~END_OF_DESCRIPTION
        Lists the holidays of one country in one year, in date order.

        Leave **Region** empty to get every holiday of the country, nationwide and regional; the **Nationwide** and **Regions** outputs tell them apart. Set a region, such as `DE-BY` or `US-CA`, to get only the holidays observed there.

        **Days off only** (on by default) skips holidays that are not days off, such as observances.
      END_OF_DESCRIPTION

      input_schema do
        field :country_code, 'Country code', :string,
              required: true,
              hint: 'Two-letter ISO 3166 code, such as NL or US.'
        field :year, 'Year', :integer, required: true
        field :region, 'Region', :string,
              visibility: 'optional',
              hint: 'ISO 3166-2 code, such as DE-BY. Empty: all holidays of the country.'
        field :days_off_only, 'Days off only', :boolean,
              default: true,
              visibility: 'optional'
      end

      output_schema do
        field :country_code, 'Country code', :string, required: true
        field :year, 'Year', :integer, required: true
        field :count, 'Count', :integer, required: true
        field :holidays, 'Holidays', :nested, array: true do
          field :date, 'Date', :date, required: true
          field :name, 'Name', :string, required: true, hint: 'English name.'
          field :local_name, 'Local name', :string
          field :nationwide, 'Nationwide', :boolean
          field :regions, 'Regions', :string, array: true, hint: 'Empty when nationwide.'
          field :types, 'Types', :string,
                array: true,
                hint: 'Public, Bank, School, Authorities, Optional or Observance.'
          field :fixed, 'Fixed date', :boolean, hint: 'Falls on the same date every year.'
          field :launch_year, 'Since year', :integer, hint: 'The first year the holiday was observed, when known.'
        end
      end

      run do
        country = input[:country_code].to_s.strip.upcase
        unless COUNTRY_CODE_PATTERN.match?(country)
          fail_job!("'#{input[:country_code]}' is not a two-letter country code, such as NL or US.")
        end

        region = input[:region].to_s.strip.upcase.presence
        if region && !region.start_with?("#{country}-")
          fail_job!("Region '#{region}' is not in #{country}. Use a code that starts with #{country}-.")
        end

        response = http_get(helpers.holidays_url("/api/v3/PublicHolidays/#{input[:year]}/#{country}"))
        if response.status == 204
          fail_job!("Nager.Date has no holidays for #{country}. See https://date.nager.at/Country for the " \
                    'countries it supports.')
        end

        days_off_only = input[:days_off_only] != false
        holidays = helpers.parse_holidays_array(response).filter_map do |holiday|
          regions = holiday['counties'] || []
          types = holiday['types'] || []
          next unless region.nil? || holiday['global'] || regions.include?(region)
          next if days_off_only && types.none? { |type| DAY_OFF_TYPES.include?(type) }

          {
            date: holiday['date'],
            name: holiday['name'],
            local_name: holiday['localName'],
            nationwide: holiday['global'],
            regions: regions,
            types: types,
            fixed: holiday['fixed'],
            launch_year: holiday['launchYear'],
          }
        end

        [{ output: { country_code: country, year: input[:year], count: holidays.size, holidays: holidays } }]
      end
    end

    helper :holidays_url do |path|
      "#{outbound_connection.config[:base_url].to_s.sub(%r{/+\z}, '')}#{path}"
    end

    helper :truncate_body do |body|
      text = body.to_s
      text.length > TRUNCATED_BODY_LIMIT ? "#{text[0, TRUNCATED_BODY_LIMIT - 3]}..." : text
    end

    helper :holidays_error_message do |response|
      parsed = JSON.parse(response.body.to_s)
      problem = parsed.is_a?(Hash) ? parsed : {}
      errors = problem['errors'].is_a?(Hash) ? problem['errors'].values.flatten.join(' ') : nil
      errors.presence || problem['detail'].presence || problem['title'].presence || helpers.truncate_body(response.body)
    rescue JSON::ParserError
      helpers.truncate_body(response.body)
    end

    helper :parse_holidays_array do |response|
      backoff_if_needed(response, api_name: 'Nager.Date', server_error_statuses: [502, 503, 504])
      status = response.status
      fail_job!("Nager.Date: #{helpers.holidays_error_message(response)} (HTTP 404)") if status == 404
      unless status >= 200 && status < 300
        fail_job!("Nager.Date API error (HTTP #{status}): #{helpers.holidays_error_message(response)}")
      end

      body = helpers.truncate_body(response.body)
      parsed = parse_json_response(response.body, error_message: "Nager.Date response was not valid JSON: '#{body}'")
      fail_job!("Nager.Date response was not a JSON array: '#{body}'") unless parsed.is_a?(Array)

      parsed
    end
  end
end
