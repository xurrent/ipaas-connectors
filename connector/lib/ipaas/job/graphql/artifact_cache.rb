require 'digest'

module IPaaS
  module Job
    module GraphQL
      # Connector-agnostic GraphQL caching: the derived-artifact bundle, its generation token,
      # the root-field options cache, and the digest/validation helpers. Pure functions — each
      # takes the cache +store+ (+nil+ for an unconfigured action) plus already-resolved values,
      # so connectors compose them through thin DSL wrappers. Reads fail closed on an absent
      # generation, so an orphaned (pre-refresh) entry is never served.
      module ArtifactCache
        extend IPaaS::Connector::Common::ProcRules::ProcSafe

        proc_safe :gql_cache_read, :gql_cache_write, :gql_cache_clear,
                  :gql_invalidate,
                  :gql_load_bundle, :gql_write_bundle_part,
                  :gql_read_root_options, :gql_write_root_options,
                  :gql_warm_for_regeneration?

        # Derived artifacts persist a week so the warm path serves without re-introspecting;
        # the generation token invalidates sooner.
        BUNDLE_TTL = 7.days.to_i

        class << self
          # A +nil+ store (unconfigured action) is intentional: reads ⇒ nil, writes/clears ⇒ no-op.
          def gql_cache_read(store, key)
            store&.cache_read(key)
          end

          def gql_cache_write(store, key, value, ttl)
            store ? store.cache_write(key, value, ttl) : value
          end

          def gql_cache_clear(store, key)
            store&.cache_clear(key)
          end

          # Shared generation token for all derived caches; +nil+ means none established yet.
          def gql_bundle_generation(store)
            gql_cache_read(store, 'gql_bundle_gen')
          end

          # Not atomic across processes, but a lost increment only costs an extra rebuild and
          # never serves stale: prior entries live under the old generation, unread under the new.
          def gql_bump_bundle_generation(store)
            gql_cache_write(store, 'gql_bundle_gen', gql_bundle_generation(store).to_i + 1, BUNDLE_TTL)
          end

          # The Refresh schema reset: clears the given keys (the cached schema and the negative
          # cache) and bumps the generation, orphaning every derived bundle and root-options
          # entry so the rebuild repopulates under the new generation.
          def gql_invalidate(store, *clear_keys)
            clear_keys.each { |key| gql_cache_clear(store, key) }
            gql_bump_bundle_generation(store)
          end

          # Returns the bundle part for a selection under the current generation, or +nil+ so the
          # caller falls back to the schema. The selection-presence gate stays connector-side.
          def gql_load_bundle(store, operation, part, selection_name:, include_fields:, required_keys:)
            gen = gql_bundle_generation(store)
            return nil if gen.nil? # fail closed: no generation ⇒ never read an orphan

            bundle = gql_cache_read(store, gql_bundle_cache_key(operation, part, selection_name, include_fields, gen))
            return nil unless bundle.is_a?(Hash)
            # reject a shape-incompatible entry (older / cross-version) so the caller rebuilds
            return nil unless required_keys.all? { |k| bundle.key?(k) }

            descriptor_key = part == 'in' ? 'input_fields' : 'output_fields'
            return nil unless gql_valid_descriptor_list?(bundle[descriptor_key])

            bundle
          end

          # Establishes the generation when absent so the first write is readable.
          def gql_write_bundle_part(store, operation, part, selection_name:, include_fields:, bundle:)
            gen = gql_bundle_generation(store) || gql_bump_bundle_generation(store)
            gql_cache_write(store, gql_bundle_cache_key(operation, part, selection_name, include_fields, gen),
                            bundle, BUNDLE_TTL)
            bundle
          end

          def gql_read_root_options(store, operation)
            gen = gql_bundle_generation(store)
            return nil if gen.nil? # fail closed

            cached = gql_cache_read(store, gql_root_options_cache_key(operation, gen))
            return nil if cached.nil?

            cached.map { |opt| { id: opt['id'], label: opt['label'] } }
          end

          def gql_write_root_options(store, operation, options)
            gen = gql_bundle_generation(store) || gql_bump_bundle_generation(store)
            gql_cache_write(store, gql_root_options_cache_key(operation, gen), options, BUNDLE_TTL)
          end

          # True when a regeneration can skip fetching the schema: the selector options are
          # cached and, once a selection is made, both bundle parts are present.
          def gql_warm_for_regeneration?(store, operation, selection_present:, selection_name:, include_fields:,
                                         required_keys_in:, required_keys_out:)
            return false if gql_read_root_options(store, operation).nil?
            return true unless selection_present

            !gql_load_bundle(store, operation, 'in',
                             selection_name: selection_name, include_fields: include_fields,
                             required_keys: required_keys_in).nil? &&
              !gql_load_bundle(store, operation, 'out',
                               selection_name: selection_name, include_fields: include_fields,
                               required_keys: required_keys_out).nil?
          end

          # Digest over the inputs that fully determine a bundle part.
          def gql_bundle_cache_key(operation, part, selection_name, include_fields, gen)
            digest = Digest::SHA256.hexdigest(
              [operation.to_s, selection_name.to_s, gql_stable_json(include_fields)].join("\n"),
            )
            "gql_bundle_#{part}_#{gen}_#{digest}"
          end

          def gql_root_options_cache_key(operation, gen)
            "gql_root_fields_#{operation}_#{gen}"
          end

          # Canonical JSON with sorted string keys: logically-equal hashes serialize identically,
          # and an explicit false leaf stays distinct from an absent key (+{a: false}+ ≠ +{}+).
          def gql_stable_json(value)
            case value
            when Hash
              normalized = value.transform_keys(&:to_s)
              pairs = normalized.keys.sort.map { |k| "#{k.to_json}:#{gql_stable_json(normalized[k])}" }
              "{#{pairs.join(',')}}"
            when Array
              "[#{value.map { |v| gql_stable_json(v) }.join(',')}]"
            else
              value.to_json
            end
          end

          # Whether a descriptor list is structurally restorable, so a malformed cross-version
          # bundle fails closed in +gql_load_bundle+ instead of raising mid-restore.
          def gql_valid_descriptor_list?(value)
            value.is_a?(Array) && value.all? { |descriptor| valid_descriptor?(descriptor) }
          end

          private

          def valid_descriptor?(descriptor)
            descriptor.is_a?(Hash) &&
              descriptor['id'].is_a?(String) && descriptor['label'].is_a?(String) &&
              descriptor['type'].is_a?(String) && valid_descriptor_enumeration?(descriptor) &&
              (!descriptor.key?('fields') || gql_valid_descriptor_list?(descriptor['fields']))
          end

          def valid_descriptor_enumeration?(descriptor)
            return true unless descriptor.key?('enumeration')

            descriptor['enumeration'].is_a?(Array) &&
              descriptor['enumeration'].all? { |e| e.is_a?(Hash) && e.key?('id') && e.key?('label') }
          end
        end
      end
    end
  end
end
