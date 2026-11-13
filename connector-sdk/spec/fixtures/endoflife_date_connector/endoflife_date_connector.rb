class EndoflifeDateConnector < IPaaS::Connector::Definition
  connector '01a1d2c9-68c7-71ec-8c2c-aa7df921ca0f' do
    name 'endoflife.date'
    avatar '/assets/icons/endoflife-date.svg'
    description <<~END_OF_DESCRIPTION
      ## Overview
      Keep end-of-support dates in your CMDB current without manual research. This connector looks up
      support lifecycles for hundreds of operating systems, databases, frameworks and devices on
      endoflife.date, so a runbook can fill in each CI's end-of-support date, flag software that's out of
      support, and give service desks and asset managers time to plan upgrades before support ends.

      The actions return each support phase separately (end of active support, end of life and end of
      extended support), so each organization can decide which date maps to its CIs' end-of-support date.

      Connects to the public [endoflife.date](https://endoflife.date) API (v1) to look up end-of-life
      and support dates for software, operating systems and hardware. Use it to check whether a
      release cycle found in your environment is still supported, when support ends, and what the
      latest version is, or to map a CPE or purl identifier reported by a discovery tool to an
      endoflife.date product.

      ## Prerequisites
      - Outbound HTTPS access from Xurrent iPaaS to `https://endoflife.date`.
      - endoflife.date product names are listed at [endoflife.date](https://endoflife.date); the
        product name is the last part of the product page address (for example `ubuntu` in
        `https://endoflife.date/ubuntu`). Use **List products** to look them up in a runbook.

      ## Authentication
      None. The endoflife.date API is public and does not require a key. The connection has no
      fields to fill in; use **Test connection** to confirm iPaaS can reach the API.

      ## Triggers
      None. This connector is outbound only.

      ## Not found
      Actions that look something up by name (a product, release cycle, category, tag or identifier
      type) do not fail when endoflife.date doesn't know it. They succeed with `found` set to
      `false`, so a runbook checking many assets keeps going. Branch on `found` in later steps.

      ## Actions

      ### Get release cycle

      Returns the support lifecycle of one release cycle of a product, for example Ubuntu 22.04
      or Node.js 20, using `GET /api/v1/products/{product}/releases/{release}`.

      | Input | Type | Required | Description |
      |---|---|---|---|
      | `product` | String | Yes | Product name, for example `ubuntu`, `nodejs`, `windows-server`. Aliases are followed automatically. |
      | `release` | String | Yes | Release cycle name, for example `22.04` or `20`. |

      Output: `found`, `product` (as requested), the **release cycle fields** below, `schema_version`
      and `generated_at`.

      ### Get latest release cycle

      Returns the newest release cycle of a product, using
      `GET /api/v1/products/{product}/releases/latest`.

      | Input | Type | Required | Description |
      |---|---|---|---|
      | `product` | String | Yes | Product name. |

      Output: same as **Get release cycle**.

      #### Release cycle fields

      | Field | Type | Description |
      |---|---|---|
      | `name` | String | Release cycle name |
      | `codename` | String | Codename, if any |
      | `label` | String | Display label, for example `22.04 'Jammy Jellyfish' (LTS)` |
      | `release_date` | Date | Release date of the cycle |
      | `is_lts` | Boolean | Whether the cycle receives long-term support |
      | `lts_from` | Date | Start of the LTS phase, if later than the release date |
      | `is_eoas` | Boolean | Whether active support has ended (only for products with an active support phase) |
      | `eoas_from` | Date | End of active support date |
      | `is_eol` | Boolean | Whether the cycle is end of life |
      | `eol_from` | Date | End-of-life date |
      | `is_discontinued` | Boolean | Whether the cycle is discontinued (mainly hardware) |
      | `discontinued_from` | Date | Discontinuation date |
      | `is_eoes` | Boolean | Whether extended support has ended (only for products with an extended support phase) |
      | `eoes_from` | Date | End of extended support date |
      | `is_maintained` | Boolean | Whether the cycle still has any level of support, including extended support |
      | `latest` | Object | Latest version of the cycle: `name`, `date`, `link` (release notes) |
      | `custom` | Object | Product-specific fields, if the product defines any. Keys vary by product and are passed through unchanged. |

      Date fields are empty when endoflife.date does not know the date. Fields marked "only for
      products with..." are empty for products without that phase.

      ### Get product

      Returns everything endoflife.date knows about a product, including all its release cycles,
      using `GET /api/v1/products/{product}`.

      | Input | Type | Required | Description |
      |---|---|---|---|
      | `product` | String | Yes | Product name. Aliases are followed automatically. |

      | Output | Type | Description |
      |---|---|---|
      | `found` | Boolean | Whether the product exists |
      | `product` | String | Product name as requested |
      | `name` | String | Canonical product name (differs from `product` when an alias was used) |
      | `label` | String | Display name, for example `Ubuntu` |
      | `aliases` | Array of String | Alternative names |
      | `category` | String | Category, for example `os` |
      | `tags` | Array of String | Tags, always including the category |
      | `version_command` | String | Command that shows the installed version, if known |
      | `identifiers` | Array | Known identifiers: `id` (for example a CPE or purl) and `type` |
      | `labels` | Object | Names of the support phases: `eoas`, `discontinued`, `eol`, `eoes` |
      | `links` | Object | `icon`, `html` (endoflife.date page), `release_policy` |
      | `releases` | Array | Every release cycle, each with the release cycle fields above |
      | `schema_version`, `generated_at`, `last_modified` | | API schema version, when the data was generated, when the product was last changed |

      ### List products

      Lists products, optionally only those in one category or with one tag, using
      `GET /api/v1/products`, `/categories/{category}` or `/tags/{tag}`.

      | Input | Type | Required | Description |
      |---|---|---|---|
      | `category` | String | No | Only products in this category, for example `os` or `database`. See **List categories**. |
      | `tag` | String | No | Only products with this tag, for example `microsoft`. See **List tags**. |

      Set a category or a tag, not both. Leave both empty to list every product.

      | Output | Type | Description |
      |---|---|---|
      | `found` | Boolean | `false` when the category or tag doesn't exist |
      | `category`, `tag` | String | The filter used, if any |
      | `total` | Integer | Number of products returned |
      | `products` | Array | `name`, `label`, `aliases`, `category`, `tags`, `uri` for each product |
      | `schema_version`, `generated_at` | | API schema version and generation time |

      ### List categories / List tags / List identifier types

      List all category names, tag names, or identifier types (such as `cpe`, `purl`, `repology`),
      using `GET /api/v1/categories`, `/tags` or `/identifiers`. No inputs.

      Output: `total`, a list of `name` and `uri` (in `categories`, `tags` or `identifier_types`),
      `schema_version` and `generated_at`.

      ### Find products by identifier

      Lists identifiers of one type with the product each belongs to, using
      `GET /api/v1/identifiers/{identifier_type}`. Give an `identifier` to find the product for
      a specific CPE or purl, for example one reported by a discovery tool.

      | Input | Type | Required | Description |
      |---|---|---|---|
      | `identifier_type` | String | Yes | Identifier type, for example `cpe`, `purl` or `repology`. See **List identifier types**. |
      | `identifier` | String | No | Return only entries matching this identifier. A more specific identifier also matches, so `cpe:/o:canonical:ubuntu_linux:22.04` matches the listed `cpe:/o:canonical:ubuntu_linux`, and `pkg:npm/express@4.18.2` matches `pkg:npm/express` (but not `pkg:npm/express-session`). Matching is exact and case-sensitive, as identifiers appear on endoflife.date. |

      | Output | Type | Description |
      |---|---|---|
      | `found` | Boolean | `false` when the identifier type doesn't exist, or nothing matches `identifier` |
      | `identifier_type`, `identifier` | String | As requested |
      | `total` | Integer | Number of entries returned |
      | `identifiers` | Array | `identifier` and `product` (`name`, `uri`) for each entry |
      | `schema_version`, `generated_at` | | API schema version and generation time |

      ## Error handling

      | HTTP status | Connector behaviour |
      |---|---|
      | 404 Not Found | Succeeds with `found: false` (see "Not found") |
      | 301 Moved Permanently | Follows the redirect (product renamed or alias used) |
      | 429 Too Many Requests | Waits for `Retry-After` (60 s if absent) and retries |
      | 502 / 503 | Waits and retries (temporary hosting issue) |
      | Other | Fails with the HTTP status |

      ## Credits
      Data from [endoflife.date](https://endoflife.date), licensed under the
      [MIT License](https://github.com/endoflife-date/endoflife.date/blob/master/LICENSE).

      ## References
      - [endoflife.date](https://endoflife.date)
      - [endoflife.date API v1 documentation](https://endoflife.date/docs/api/v1/)
      - [endoflife.date API changelog](https://github.com/endoflife-date/endoflife.date/blob/master/CHANGELOG_API.md)
    END_OF_DESCRIPTION

    outbound_connection do
      config_tester do
        response = http_get("#{helpers.eol_base_url}/", nil, nil, open_timeout: 2, timeout: 5)
        if response.status == 200
          { status: :success, message: 'Connection successful. The endoflife.date API is reachable.' }
        elsif response.status == 429
          { status: :failed, message: 'endoflife.date is rate limiting requests (HTTP 429). Try again shortly.' }
        else
          { status: :error, message: "endoflife.date API check failed (HTTP #{response.status})." }
        end
      end
    end

    # Defined before the actions: iPaaS builds each output_schema as soon as its action is declared,
    # and helpers resolve at call time, so a schema can only use helpers that already exist.
    helper :eol_base_url do
      'https://endoflife.date/api/v1'
    end

    # Lowercase is safe for product, category, tag and identifier type names: all are lowercase.
    helper :eol_segment do |value|
      value.to_s.strip.downcase
    end

    # Renamed products and aliases answer with a 301; follow a few hops, but only on endoflife.date.
    helper :eol_get do |url, hops|
      response = http_get(url)
      backoff_if_needed(response, api_name: 'endoflife.date', server_error_statuses: [502, 503])
      next response unless [301, 302, 307, 308].include?(response.status)

      location = response.headers['location'].to_s
      location = "https://endoflife.date#{location}" if location.start_with?('/')
      fail_job!("endoflife.date redirected too many times (last: #{location}).") if hops >= 3
      unless location.start_with?('https://endoflife.date/')
        fail_job!("endoflife.date redirected to an unexpected address: '#{location}'.")
      end
      helpers.eol_get(location, hops + 1)
    end

    # Returns the parsed body, or nil when endoflife.date answers 404 (its 404 body is HTML).
    helper :eol_fetch do |path|
      response = helpers.eol_get("#{helpers.eol_base_url}#{path}", 0)
      next nil if response.status == 404

      helpers.eol_parse(response)
    end

    helper :eol_parse do |response|
      fail_job!("endoflife.date request failed (HTTP #{response.status}).") unless response.status == 200
      begin
        body = JSON.parse(response.body)
      rescue JSON::ParserError
        fail_job!('endoflife.date returned a response that is not JSON.')
      end
      fail_job!('endoflife.date returned an unexpected response.') unless body.is_a?(Hash)
      body.with_indifferent_access
    end

    helper :release_field_ids do
      %w[name codename label release_date is_lts lts_from is_eoas eoas_from is_eol eol_from
         is_discontinued discontinued_from is_eoes eoes_from is_maintained latest custom]
    end

    helper :add_release_fields do |target|
      target.field :name, 'Release cycle', :string
      target.field :codename, 'Codename', :string
      target.field :label, 'Label', :string
      target.field :release_date, 'Release date', :date
      target.field :is_lts, 'Is LTS', :boolean
      target.field :lts_from, 'LTS from', :date
      target.field :is_eoas, 'Active support ended', :boolean
      target.field :eoas_from, 'End of active support', :date
      target.field :is_eol, 'Is end of life', :boolean
      target.field :eol_from, 'End of life', :date
      target.field :is_discontinued, 'Is discontinued', :boolean
      target.field :discontinued_from, 'Discontinued from', :date
      target.field :is_eoes, 'Extended support ended', :boolean
      target.field :eoes_from, 'End of extended support', :date
      target.field :is_maintained, 'Is maintained', :boolean
      target.field :latest, 'Latest version', :nested
      latest = target.field(:latest)
      latest.field :name, 'Version', :string
      latest.field :date, 'Release date', :date
      latest.field :link, 'Release notes link', :string
      target.field :custom, 'Custom fields', :hash
    end

    helper :release_response do |body, product, release|
      if body.nil?
        [{ output: { found: false, product: product, name: release } }]
      else
        result = camel_to_snake(body[:result] || {}, ['custom']).with_indifferent_access
        helpers.log_unmodelled([result], helpers.release_field_ids, 'release cycle')
        [{
          output: result.merge(
            found: true,
            product: product,
            schema_version: body[:schema_version],
            generated_at: body[:generated_at]
          ),
        }]
      end
    end

    helper :add_uri_list_fields do |schema, list_id, list_label|
      schema.field :total, 'Total', :integer
      schema.field list_id, list_label, :nested, array: true
      items = schema.field(list_id)
      items.field :name, 'Name', :string
      items.field :uri, 'API link', :string
      schema.field :schema_version, 'Schema version', :string
      schema.field :generated_at, 'Generated at', :date_time
    end

    helper :uri_list_response do |path, list_id|
      body = helpers.eol_fetch(path)
      fail_job!("endoflife.date has no list at #{path} (HTTP 404).") if body.nil?
      items = Array(camel_to_snake(body[:result] || []))
      helpers.log_unmodelled(items, %w[name uri], list_id.to_s)
      [{
        output: {
          total: body[:total],
          list_id => items,
          schema_version: body[:schema_version],
          generated_at: body[:generated_at],
        },
      }]
    end

    # Undeclared keys are dropped silently, so name any the API sends that this connector doesn't model.
    helper :log_unmodelled do |records, modelled, what|
      extra = records.flat_map do |record|
        record.is_a?(Hash) ? record.reject { |key, value| modelled.include?(key.to_s) || value.nil? }.keys : []
      end
      extra = extra.map(&:to_s).uniq
      log("endoflife.date returned #{what} fields this connector does not model: #{extra.join(', ')}") if extra.any?
    end

    action '01a1d2c9-68db-7bae-8b27-6752a10ea0b5' do
      name 'Get release cycle'
      avatar '/assets/icons/endoflife-date.svg'
      description <<~END_OF_DESCRIPTION
        Returns the support lifecycle of one release cycle of a product, for example Ubuntu 22.04
        or Node.js 20: whether it is end of life, the end-of-life date, LTS status, whether it is
        still maintained, and the latest version of the cycle.

        Succeeds with `found` set to `false` when endoflife.date does not know the product or release.
      END_OF_DESCRIPTION

      input_schema do
        field :product, 'Product', :string,
              required: true,
              hint: 'endoflife.date product name, for example ubuntu, nodejs or windows-server. ' \
                    'It is the last part of the product page address on endoflife.date.'
        field :release, 'Release cycle', :string,
              required: true,
              hint: 'Release cycle name as shown on endoflife.date, for example 22.04 or 20.'
      end

      output_schema do
        field :found, 'Found', :boolean, required: true
        field :product, 'Product', :string, required: true
        helpers.add_release_fields(self)
        field :schema_version, 'Schema version', :string
        field :generated_at, 'Generated at', :date_time
      end

      run do
        product = helpers.eol_segment(input[:product])
        # endoflife.date publishes a cycle such as "a/b" under the path "a-b".
        release = input[:release].to_s.strip.tr('/', '-')
        body = helpers.eol_fetch("/products/#{product}/releases/#{release}")
        helpers.release_response(body, product, release)
      end
    end

    action '01a1d2ed-53db-7cbd-bfa7-b20997bab05c' do
      name 'Get latest release cycle'
      avatar '/assets/icons/endoflife-date.svg'
      description <<~END_OF_DESCRIPTION
        Returns the newest release cycle of a product, with the same fields as **Get release cycle**.

        Succeeds with `found` set to `false` when endoflife.date does not know the product.
      END_OF_DESCRIPTION

      input_schema do
        field :product, 'Product', :string,
              required: true,
              hint: 'endoflife.date product name, for example ubuntu, nodejs or windows-server.'
      end

      output_schema do
        field :found, 'Found', :boolean, required: true
        field :product, 'Product', :string, required: true
        helpers.add_release_fields(self)
        field :schema_version, 'Schema version', :string
        field :generated_at, 'Generated at', :date_time
      end

      run do
        product = helpers.eol_segment(input[:product])
        body = helpers.eol_fetch("/products/#{product}/releases/latest")
        helpers.release_response(body, product, nil)
      end
    end

    action '01a1d2ed-53fc-7cd9-9375-842ac90f1caf' do
      name 'Get product'
      avatar '/assets/icons/endoflife-date.svg'
      description <<~END_OF_DESCRIPTION
        Returns everything endoflife.date knows about a product: label, category, tags, known
        identifiers (CPE, purl), links, and every release cycle with its support dates.

        Succeeds with `found` set to `false` when endoflife.date does not know the product.
      END_OF_DESCRIPTION

      input_schema do
        field :product, 'Product', :string,
              required: true,
              hint: 'endoflife.date product name, for example ubuntu, nodejs or windows-server.'
      end

      output_schema do
        field :found, 'Found', :boolean, required: true
        field :product, 'Product', :string, required: true
        field :name, 'Name', :string
        field :label, 'Label', :string
        field :aliases, 'Aliases', :string, array: true
        field :category, 'Category', :string
        field :tags, 'Tags', :string, array: true
        field :version_command, 'Version command', :string
        field :identifiers, 'Identifiers', :nested, array: true do
          field :id, 'Identifier', :string
          field :type, 'Type', :string
        end
        field :labels, 'Phase labels', :nested do
          field :eoas, 'Active support', :string
          field :discontinued, 'Discontinued', :string
          field :eol, 'End of life', :string
          field :eoes, 'Extended support', :string
        end
        field :links, 'Links', :nested do
          field :icon, 'Icon', :string
          field :html, 'endoflife.date page', :string
          field :release_policy, 'Release policy', :string
        end
        field :releases, 'Releases', :nested, array: true
        helpers.add_release_fields(field(:releases))
        field :schema_version, 'Schema version', :string
        field :generated_at, 'Generated at', :date_time
        field :last_modified, 'Last modified', :date_time
      end

      run do
        product = helpers.eol_segment(input[:product])
        body = helpers.eol_fetch("/products/#{product}")
        if body.nil?
          [{ output: { found: false, product: product } }]
        else
          result = camel_to_snake(body[:result] || {}, ['custom']).with_indifferent_access
          helpers.log_unmodelled([result], %w[name label aliases category tags version_command identifiers
                                              labels links releases], 'product')
          helpers.log_unmodelled(Array(result[:releases]), helpers.release_field_ids, 'release cycle')
          [{
            output: result.merge(
              found: true,
              product: product,
              schema_version: body[:schema_version],
              generated_at: body[:generated_at],
              last_modified: body[:last_modified]
            ),
          }]
        end
      end
    end

    action '01a1d2ed-541c-7cb2-9215-74ae0e287076' do
      name 'List products'
      avatar '/assets/icons/endoflife-date.svg'
      description <<~END_OF_DESCRIPTION
        Lists endoflife.date products, optionally only those in one category or with one tag.
        Set a category or a tag, not both. Leave both empty to list every product.

        Succeeds with `found` set to `false` when the category or tag doesn't exist.
      END_OF_DESCRIPTION

      input_schema do
        field :category, 'Category', :string,
              hint: 'Only products in this category, for example os or database. Use List categories to see them all.'
        field :tag, 'Tag', :string,
              hint: 'Only products with this tag, for example microsoft. Use List tags to see them all.'
      end

      output_schema do
        field :found, 'Found', :boolean, required: true
        field :category, 'Category', :string
        field :tag, 'Tag', :string
        field :total, 'Total', :integer
        field :products, 'Products', :nested, array: true do
          field :name, 'Name', :string
          field :label, 'Label', :string
          field :aliases, 'Aliases', :string, array: true
          field :category, 'Category', :string
          field :tags, 'Tags', :string, array: true
          field :uri, 'API link', :string
        end
        field :schema_version, 'Schema version', :string
        field :generated_at, 'Generated at', :date_time
      end

      run do
        category = helpers.eol_segment(input[:category]).presence
        tag = helpers.eol_segment(input[:tag]).presence
        fail_job!('Set a category or a tag, not both.') if category && tag

        path = if category
                 "/categories/#{category}"
               elsif tag
                 "/tags/#{tag}"
               else
                 '/products'
               end
        body = helpers.eol_fetch(path)
        if body.nil?
          [{ output: { found: false, category: category, tag: tag, total: 0, products: [] } }]
        else
          products = Array(camel_to_snake(body[:result] || []))
          helpers.log_unmodelled(products, %w[name label aliases category tags uri], 'product')
          [{
            output: {
              found: true,
              category: category,
              tag: tag,
              total: body[:total],
              products: products,
              schema_version: body[:schema_version],
              generated_at: body[:generated_at],
            },
          }]
        end
      end
    end

    action '01a1d2ed-543b-7290-aedb-4a3ccc557b9a' do
      name 'List categories'
      avatar '/assets/icons/endoflife-date.svg'
      description 'Lists all endoflife.date product categories, for example os, database or framework.'

      output_schema do
        helpers.add_uri_list_fields(self, :categories, 'Categories')
      end

      run do
        helpers.uri_list_response('/categories', :categories)
      end
    end

    action '01a1d2ed-545b-7ddd-b968-ac921883831c' do
      name 'List tags'
      avatar '/assets/icons/endoflife-date.svg'
      description 'Lists all endoflife.date product tags, for example microsoft or linux-distribution.'

      output_schema do
        helpers.add_uri_list_fields(self, :tags, 'Tags')
      end

      run do
        helpers.uri_list_response('/tags', :tags)
      end
    end

    action '01a1d2ed-5478-709b-9009-0aef4ed32cd9' do
      name 'List identifier types'
      avatar '/assets/icons/endoflife-date.svg'
      description 'Lists the identifier types endoflife.date knows, such as cpe, purl and repology.'

      output_schema do
        helpers.add_uri_list_fields(self, :identifier_types, 'Identifier types')
      end

      run do
        helpers.uri_list_response('/identifiers', :identifier_types)
      end
    end

    action '01a1d2ed-5497-77f8-bee3-775277ee081c' do
      name 'Find products by identifier'
      avatar '/assets/icons/endoflife-date.svg'
      description <<~END_OF_DESCRIPTION
        Lists identifiers of one type (for example CPE or purl) with the endoflife.date product each
        belongs to. Give an identifier to find the product for a specific CPE or purl, for example
        one reported by a discovery tool. A more specific identifier also matches, so
        `cpe:/o:canonical:ubuntu_linux:22.04` matches the listed `cpe:/o:canonical:ubuntu_linux`.

        Succeeds with `found` set to `false` when the identifier type doesn't exist or nothing matches.
      END_OF_DESCRIPTION

      input_schema do
        field :identifier_type, 'Identifier type', :string,
              required: true,
              hint: 'For example cpe, purl or repology. Use List identifier types to see them all.'
        field :identifier, 'Identifier', :string,
              hint: 'Optional. Return only entries matching this CPE, purl or other identifier. ' \
                    'Case-sensitive, as identifiers appear on endoflife.date.'
      end

      output_schema do
        field :found, 'Found', :boolean, required: true
        field :identifier_type, 'Identifier type', :string, required: true
        field :identifier, 'Identifier', :string
        field :total, 'Total', :integer
        field :identifiers, 'Identifiers', :nested, array: true do
          field :identifier, 'Identifier', :string
          field :product, 'Product', :nested do
            field :name, 'Name', :string
            field :uri, 'API link', :string
          end
        end
        field :schema_version, 'Schema version', :string
        field :generated_at, 'Generated at', :date_time
      end

      run do
        identifier_type = helpers.eol_segment(input[:identifier_type])
        wanted = input[:identifier].to_s.strip.presence
        body = helpers.eol_fetch("/identifiers/#{identifier_type}")
        entries = body.nil? ? [] : Array(camel_to_snake(body[:result] || []))
        entries = entries.select { |entry| helpers.identifier_match(wanted, entry[:identifier].to_s) } if wanted
        [{
          output: {
            found: !body.nil? && entries.any?,
            identifier_type: identifier_type,
            identifier: wanted,
            total: entries.size,
            identifiers: entries,
            schema_version: body && body[:schema_version],
            generated_at: body && body[:generated_at],
          },
        }]
      end

      # A listed identifier matches the wanted one exactly, or as a prefix that ends at a
      # separator, so a versioned CPE or purl finds its product without matching look-alikes.
      helper :identifier_match do |wanted, listed|
        next false if listed.empty?
        next true if wanted == listed
        next false unless wanted.start_with?(listed)

        ':@/?#'.include?(wanted[listed.length])
      end
    end

  end
end
