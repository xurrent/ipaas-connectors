module IPaaS
  module Connector
    module Common
      class Serializer
        ALLOWED_CLASSES = [Symbol, Time, Date, DateTime, Regexp, IPaaS::Encryption::SecretString].freeze
        ALLOWED_CLASS_NAMES = ALLOWED_CLASSES.map(&:name).freeze
        ALLOWED_CLASS_SET = ALLOWED_CLASSES.to_set.freeze

        class TolerantVisitor < Psych::Visitors::NoAliasRuby
          [:Mapping, :Scalar, :Sequence].each do |shape|
            define_method(:"visit_Psych_Nodes_#{shape}") do |node|
              super(node)
            rescue Psych::DisallowedClass
              UnresolvedNode.for_node(node)
            end
          end
        end

        EMITTABLE_CLASSES = [Hash, Array, String, Numeric, NilClass, TrueClass, FalseClass,
                             Symbol, Time, Date, Regexp,].freeze

        class NodePreservingTree < Psych::Visitors::YAMLTree
          def accept(target)
            return replay(target.node) if target.is_a?(UnresolvedNode)

            reject_native_object!(target)
            super
          end

          private

          def reject_native_object!(target)
            return if target.respond_to?(:encode_with)
            return if EMITTABLE_CLASSES.any? { |klass| target.is_a?(klass) }

            raise IPaaS::Error, "Refusing to write #{target.class} as a native Ruby object tag"
          end

          def replay(node)
            case node
            when Psych::Nodes::Scalar then replay_scalar(node)
            when Psych::Nodes::Sequence then replay_sequence(node)
            when Psych::Nodes::Mapping then replay_mapping(node)
            end
          end

          def replay_scalar(node)
            @emitter.scalar(node.value, node.anchor, node.tag, node.plain, node.quoted, node.style)
          end

          def replay_sequence(node)
            @emitter.start_sequence(node.anchor, node.tag, node.implicit, node.style)
            node.children.each { |child| replay(child) }
            @emitter.end_sequence
          end

          def replay_mapping(node)
            @emitter.start_mapping(node.anchor, node.tag, node.implicit, node.style)
            node.children.each { |child| replay(child) }
            @emitter.end_mapping
          end
        end

        SUBSTITUTION_KEY = :ipaas_tolerant_substitution

        class << self
          def reset_tolerant_substitution!
            Thread.current[SUBSTITUTION_KEY] = false
          end

          def record_tolerant_substitution!
            Thread.current[SUBSTITUTION_KEY] = true
          end

          def tolerant_substitution_occurred?
            Thread.current[SUBSTITUTION_KEY] == true
          end

          def parse(value, with_uuid: false, tolerant: false, name: nil)
            case value
            when String, File
              load_yaml(value, tolerant)
            else
              value
            end.tap do |v|
              if with_uuid && v.is_a?(Hash) && !v.key?('uuid') && !v.key?(:uuid)
                v['uuid'] = uuid_from_name(value, name) || SecureRandom.uuid_v7
              end
            end
          end

          def dump(value)
            visitor = NodePreservingTree.create
            visitor << value
            visitor.tree.yaml
          end

          def to_h(value, *attributes)
            attributes.each_with_object({}) do |attr, hash|
              result = value.send(attr)
              next hash unless result.present? || result == false # keep 'false' values in the output

              hash[attr] = dereference(result)
            end
          end

          private

          def dereference(result)
            return result.map { |item| dereference(item) } if result.is_a?(Array)
            return result.to_h_ref if result.respond_to?(:to_h_ref)

            result
          end

          def load_yaml(value, tolerant)
            content = value.is_a?(File) ? value.read : value
            YamlLimits.apply!(content)
            YAML.load(content, permitted_classes: ALLOWED_CLASSES)
          rescue Psych::DisallowedClass
            raise unless tolerant

            tolerant_load(content)
          end

          def tolerant_load(content)
            document = Psych.parse(content)
            return unless document

            loader = Psych::ClassLoader::Restricted.new(ALLOWED_CLASS_NAMES.dup, [])
            result = TolerantVisitor.new(Psych::ScalarScanner.new(loader), loader).accept(document)
            record_tolerant_substitution! if UnresolvedNode.within?(result)
            result
          ensure
            UnresolvedNode.forget_checked_nodes!
          end

          def uuid_from_name(value, name)
            path = value.is_a?(File) ? value.path : name
            return unless path&.end_with?('.yaml', '.yml')

            File.basename(path, '.*')
          end
        end
      end
    end
  end
end
