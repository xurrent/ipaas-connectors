class NagerDateConnector < IPaaS::Connector::Definition
  # Constants live at class level, outside every DSL block: the sandbox rejects constant
  # definitions only inside validate/parse/run/authenticate/config_tester/helper blocks.
  DEFAULT_BASE_URL          = 'https://date.nager.at'.freeze
  API_BASE_PATH             = '/api/v3'.freeze
  PUBLIC_HOLIDAYS_ROUTE     = '/PublicHolidays'.freeze
  AVAILABLE_COUNTRIES_ROUTE = '/AvailableCountries'.freeze
  API_NAME                  = 'Nager.Date'.freeze

  HOLIDAY_TYPES = %w[Public Bank School Authorities Optional Observance].freeze

  connector '01a1d15a-f8ba-78e0-8a81-9deab0fee4ff' do
    name 'Nager.Date'
    avatar '/assets/icons/nager-date.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Reads public holidays from [Nager.Date](https://date.nager.at), a free, open-source holiday API covering more than 100 countries. Use it to make runbooks holiday-aware: skip or reschedule work on public holidays, calculate business days, or keep a calendar of non-working days per country in sync.

      ## Prerequisites
      - None for the public service at `https://date.nager.at`. It needs no account and no API key.
      - Optionally, a self-hosted Nager.Date instance (for example the `nager/nager-date` Docker image). Point the connection's Base URL at it.

      ## Authentication
      None. The public API is anonymous.

      | Field | Required | Default | Description |
      |---|---|---|---|
      | Base URL | No | `https://date.nager.at` | Address of the Nager.Date service. Leave off `/api/v3`. |

      The connection test calls `GET /api/v3/AvailableCountries` and reports how many countries the service supports, so a wrong Base URL is visible before any runbook runs.

      ## Triggers
      None. This connector is outbound only.

      ## Actions

      ### List Public Holidays
      Returns every holiday Nager.Date knows for one country in one calendar year, from `GET /api/v3/PublicHolidays/{year}/{countryCode}`.

      **Use case**: before scheduling a change or a maintenance window, check whether the date is a public holiday in the affected country.

      #### Input Parameters

      | Parameter | Type | Required | Default | Description |
      |-----------|------|----------|---------|-------------|
      | country_code | String | Yes | - | ISO 3166-1 alpha-2 code, for example `US`, `DE` or `IN`. Case does not matter. |
      | year | Integer | Yes | - | The calendar year, for example `2026`. |

      #### Output

      | Field Name | Type | Description |
      |---|---|---|
      | `country_code` | String | The country code that was requested, upper-cased. |
      | `year` | Integer | The year that was requested. |
      | `count` | Integer | Number of holidays returned. |
      | `holidays` | Object[] | One object per holiday, fields below. |

      Each entry in `holidays`:

      | Field Name | Type | Description |
      |---|---|---|
      | `date` | Date | The date of the holiday. |
      | `local_name` | String | Name in the country's own language. |
      | `name` | String | Common English name. |
      | `country_code` | String | ISO 3166-1 alpha-2 code. |
      | `global` | Boolean | `true` for a nationwide holiday, `false` for one that applies only in some subdivisions. |
      | `counties` | String[] | ISO 3166-2 subdivision codes the holiday applies to. Empty when `global` is `true`. |
      | `types` | String[] | One or more of `Public`, `Bank`, `School`, `Authorities`, `Optional`, `Observance`. |
      | `fixed` | Boolean | Deprecated by Nager.Date. May be absent. |
      | `launch_year` | Integer | Deprecated by Nager.Date. The year the holiday was introduced, often empty. |

      #### Operational notes
      - Not every holiday is a day off for everyone. Filter on `types` containing `Public` when you only want statutory non-working days, and on `global` when regional holidays should not count.
      - An unsupported country code fails the job with a message naming the code. Nager.Date lists supported codes at `/api/v3/AvailableCountries`.
      - A supported country with no data for the requested year returns an empty `holidays` list and `count` 0. That is a normal answer, not an error.

      ## Rate Limiting and Error Handling
      Nager.Date does not publish a rate limit. If it ever answers `429` or `503`, the connector waits for the `Retry-After` interval, or 60 seconds when the header is absent, and retries. `404` fails the job immediately as an unsupported country code, `400` as a rejected year or code, and any other non-success status fails immediately with the response body.

      ## Best Practices
      - Fetch a year once per run and filter it in the runbook, rather than calling the action once per date.
      - Holidays are legislated and occasionally change mid-year, so refresh any cached list periodically.

      ## References
      - [Nager.Date API](https://date.nager.at/Api) documents the endpoint, parameters and response model.
      - [Nager.Date on GitHub](https://github.com/nager/Nager.Date) for issues, data corrections and the self-hosting image.
    END_OF_DESCRIPTION

    outbound_connection do
      config_schema do
        field :base_url, 'Base URL', :uri,
              visibility: 'optional',
              default: DEFAULT_BASE_URL,
              hint: 'Address of the Nager.Date service. Leave off /api/v3. ' \
                    'Change it only for a self-hosted instance.'
      end

      # The public API is anonymous, so there is no authenticator and no authenticate block.

      config_tester do
        response = http_get(helpers.nager_url(AVAILABLE_COUNTRIES_ROUTE), nil, nil, open_timeout: 2, timeout: 5)
        if response.status == 200
          countries = helpers.parse_nager_array(response)
          { status: :success, message: "Connection successful. Nager.Date supports #{countries.size} countries." }
        else
          { status: :failed,
            message: "Nager.Date country list returned HTTP #{response.status}: '#{response.body}'", }
        end
      end
    end

    action '01a1d15a-f8c5-7743-a796-4349187f3415' do
      name 'List Public Holidays'
      avatar '/assets/icons/nager-date.svg'

      description <<~END_OF_DESCRIPTION
        Returns every holiday Nager.Date knows for one country in one calendar year. Filter `types` on `Public` for statutory days off, and on `global` to exclude holidays that apply only in some subdivisions.
      END_OF_DESCRIPTION

      # pattern: is enforced by the input mapping before run executes, so the run block does not
      # re-validate the code. It only upper-cases it, because the pattern accepts either case.
      input_schema do
        field :country_code, 'Country code', :string,
              required: true,
              pattern: /\A[A-Za-z]{2}\z/,
              hint: 'ISO 3166-1 alpha-2 code, for example US, DE or IN.'
        field :year, 'Year', :integer,
              required: true,
              hint: 'The calendar year, for example 2026.'
      end

      output_schema 'holidays' do
        field :country_code, 'Country code', :string, required: true
        field :year, 'Year', :integer, required: true
        field :count, 'Count', :integer, required: true
        field :holidays, 'Holidays', :nested, array: true do
          field :date, 'Date', :date
          field :local_name, 'Local name', :string
          field :name, 'Name', :string
          field :country_code, 'Country code', :string
          field :global, 'Global', :boolean,
                hint: 'True for a nationwide holiday, false when it applies only in some subdivisions.'
          field :counties, 'Counties', :string, array: true,
                                                hint: 'ISO 3166-2 subdivision codes. Empty for nationwide holidays.'
          field :types, 'Types', :string, array: true,
                                          hint: "One or more of #{HOLIDAY_TYPES.join(', ')}."
          # Deprecated by Nager.Date but still sent. Declared so they are not silently dropped.
          field :fixed, 'Fixed', :boolean, hint: 'Deprecated by Nager.Date.'
          field :launch_year, 'Launch year', :integer, hint: 'Deprecated by Nager.Date.'
        end
      end

      run do
        country_code = input[:country_code].to_s.upcase
        year = input[:year]

        response = http_get(helpers.nager_url("#{PUBLIC_HOLIDAYS_ROUTE}/#{year}/#{country_code}"))
        backoff_if_needed(response, api_name: API_NAME)

        holidays = helpers.holidays_from(response, country_code, year)
        helpers.log_unmodelled_keys(holidays)
        log('Fetched %<count>s holidays for %<country>s in %<year>s',
            { count: holidays.size, country: country_code, year: year })

        [{ output: { country_code: country_code,
                     year: year,
                     count: holidays.size,
                     holidays: camel_to_snake(holidays), },
           schema_reference: 'holidays', }]
      end

      helper :holidays_from do |response, country_code, year|
        case response.status
        when 200
          helpers.parse_nager_array(response)
        when 204
          []
        when 404
          fail_job!("Country code '#{country_code}' is not supported by Nager.Date. " \
                    'See /api/v3/AvailableCountries for the supported codes.')
        when 400
          fail_job!("Nager.Date rejected year #{year} for '#{country_code}': '#{response.body}'")
        else
          fail_job!("Nager.Date HTTP error: #{response.status} '#{response.body}'")
        end
      end

      # Undeclared keys are stripped by the output mapping, so this log line is the only signal
      # that Nager.Date started sending something the runbook will never see. Null values are
      # compacted away first so a key the API sends as null on every record is not a false positive.
      helper :log_unmodelled_keys do |holidays|
        declared = action.output_schema('holidays').field(:holidays).fields.map { |field| field.id.to_s }
        records = holidays.select { |holiday| holiday.is_a?(Hash) }.map(&:compact)
        unknown = camel_to_snake(records).flat_map(&:keys).map(&:to_s).uniq
                                         .reject { |key| declared.include?(key) }
        log('Nager.Date returned keys this action does not model: %<keys>s', { keys: unknown.join(', ') }) if
          unknown.any?
      end
    end

    helper :api_base do
      raw = outbound_connection.config&.dig(:base_url).to_s.strip
      url = raw.presence || DEFAULT_BASE_URL
      url = url.sub(%r{/+\z}, '').chomp(API_BASE_PATH).sub(%r{/+\z}, '')

      "#{url}#{API_BASE_PATH}"
    end

    helper :nager_url do |route|
      "#{helpers.api_base}#{route}"
    end

    helper :parse_nager_array do |response|
      parsed = parse_json_response(response.body,
                                   error_message: "Nager.Date response was not valid JSON: '#{response.body}'")
      fail_job!("Nager.Date response was not a JSON array: '#{response.body}'") unless parsed.is_a?(Array)

      parsed
    end
  end
end
