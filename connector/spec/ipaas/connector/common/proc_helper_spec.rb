require 'spec_helper'

describe IPaaS::Connector::Common::ProcHelper do
  context 'action reference extractor' do
    it 'extracts single quoted references' do
      refs = IPaaS::Connector::Common::ProcHelper.action_references(<<~RUBY)
        action_output('a') + action_output('action1', output_schema_reference: 'loop')
      RUBY
      expect(refs).to contain_exactly('a', 'action1')
    end

    it 'extracts double quoted references' do
      refs = IPaaS::Connector::Common::ProcHelper.action_references(<<~RUBY)
        action_output("b") + action_output("other_action", output_schema_reference: 'loop')
      RUBY
      expect(refs).to contain_exactly('b', 'other_action')
    end
  end

  context 'action reference replacer' do
    it 'replaces single quoted references' do
      replacer = IPaaS::Connector::Common::ProcHelper.create_action_ref_replacer('old_action', 'new_action')
      replaced = replacer.call(<<~RUBY)
        action_output('old_action') + action_output('action1', output_schema_reference: 'loop')
        action_output('other_action') + action_output('old_action', output_schema_reference: 'loop')
      RUBY

      expect(replaced).to eq(<<~RUBY)
        action_output('new_action') + action_output('action1', output_schema_reference: 'loop')
        action_output('other_action') + action_output('new_action', output_schema_reference: 'loop')
      RUBY
    end

    it 'replaces double quoted references' do
      replacer = IPaaS::Connector::Common::ProcHelper.create_action_ref_replacer('old_action', 'new_action')
      replaced = replacer.call(<<~RUBY)
        action_output("old_action") + action_output("action1", output_schema_reference: 'loop')
        action_output("other_action") + action_output("old_action", output_schema_reference: 'loop')
      RUBY

      expect(replaced).to eq(<<~RUBY)
        action_output("new_action") + action_output("action1", output_schema_reference: 'loop')
        action_output("other_action") + action_output("new_action", output_schema_reference: 'loop')
      RUBY
    end

    it 'replaces references with mixed quoting' do
      replacer = IPaaS::Connector::Common::ProcHelper.create_action_ref_replacer('old_action', 'new_action')
      replaced = replacer.call(<<~RUBY)
        action_output('old_action') + action_output('action1', output_schema_reference: 'loop')
        action_output('other_action') + action_output("old_action", output_schema_reference: 'loop')
      RUBY

      expect(replaced).to eq(<<~RUBY)
        action_output('new_action') + action_output('action1', output_schema_reference: 'loop')
        action_output('other_action') + action_output("new_action", output_schema_reference: 'loop')
      RUBY
    end
  end

  context 'proc from string' do
    it 'should execute basic proc' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "'Hello World!'")
      expect(helper.execute).to eq('Hello World!')
    end

    it 'should execute proc with params' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, '->(n) { n * 2 }')
      expect(helper.execute(4)).to eq(8)
    end

    it 'should mirror the code as source' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "'Hello World!'")
      expect(helper.source).to eq("'Hello World!'")
    end

    describe 'if_valid' do
      it 'should validate the methods' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'Obj.send(:foo)')
        expect(helper.execute_if_valid).to be_nil
        expect(helper.errors).to eq(["Method 'send' not allowed."])
      end

      it 'should allow and execute procs using drill' do
        proc = "{ items: [{ name: 'Foo' }, { name: 'Bar' }] }.drill(:items, :name)"
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
        expect(helper.execute_if_valid).to eq(%w[Foo Bar])
        expect(helper.errors).to be_empty
      end

      it 'should validate save navigation methods' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'self&.send(:foo)')
        expect(helper.execute_if_valid).to be_nil
        expect(helper.errors).to eq(["Method 'send' not allowed."])
      end

      it 'should report validation errors using the on_invalid callback' do
        invalid = []
        proc = 'Object.send(:foo).each do |f| f.bar end'
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, on_invalid: ->(msg) { invalid << msg })
        expect(helper.execute_if_valid).to be_nil
        expect(invalid).to eq(["Method 'bar' not allowed.", "Method 'send' not allowed."])
      end

      it 'should validate the same source only once' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, '"Bye World!"')
        expect(helper).to receive(:validate_nodes).once
        expect(helper.execute_if_valid).to eq('Bye World!')
        expect(helper.execute_if_valid).to eq('Bye World!')
      end

      it 'should validate the same source multiple times in case it is invalid' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'Obj.send(:foo)')
        expect(helper).to receive(:validate_nodes).twice.and_call_original
        expect(helper.execute_if_valid).to be_nil
        expect(helper.errors).to eq(["Method 'send' not allowed."])
        expect(helper.execute_if_valid).to be_nil
        expect(helper.errors).to eq(["Method 'send' not allowed."])
      end
    end

    it 'should validate the methods' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'Obj.send(:foo)')
      expect do
        helper.execute
      end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                         %(["Method 'send' not allowed."]))
    end

    describe 'method definition' do
      it 'should not allow methods to be defined' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'def my_method(a, b); a + b; end')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Method definition 'my_method' not allowed."]))
      end

      it 'should not allow functions to be defined' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'def my_method(a, b) = a + b')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Method definition 'my_method' not allowed."]))
      end

      it 'should not allow methods to be defined on objects' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'def action.my_method(a, b); a + b; end')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Method definition 'action.my_method' not allowed."]))
      end
    end

    describe 'ENV access' do
      it 'should not allow local variable to be assigned environment variables' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = ENV')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Access to 'ENV' not allowed."]))
      end

      it 'should not allow environment variable to be read' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = ENV["PATH"]')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Access to 'ENV' not allowed."]))
      end

      it 'should not allow environment variable to be used as parameters' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = a[ENV["PATH"]]')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Access to 'ENV' not allowed."]))
      end

      it 'should not allow environment variables to be listed' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = ENV.keys')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Access to 'ENV' not allowed."]))
      end

      it 'should not allow environment variables to be changed' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'ENV["abc"] = "abc"')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Calling methods on 'ENV' not allowed."]))
      end
    end

    describe 'ENVx' do
      before(:all) do
        class ENVx
          def self.values
            {}
          end
        end
      end

      after(:all) do
        Object.send(:remove_const, :ENVx)
      end

      it 'should not allow calling methods on ENVx' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'ENVx.values.keys')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Calling methods on 'ENVx' not allowed."]))
      end

      it 'should not allow local variable set to ENVx' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = ENVx')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Access to 'ENVx' not allowed."]))
      end

      it 'should not allow access to ENVx' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, '"#{ENVx.values}"')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Access to 'ENVx' not allowed."]))
      end
    end

    describe 'access to classes with uppercase names' do
      before(:all) do
        module A
          class DATA
            def self.values
              {}
            end
          end
        end

        class DATA
          def self.values
            {}
          end
        end
      end

      after(:all) do
        A.send(:remove_const, :DATA)
        Object.send(:remove_const, :A)
        Object.send(:remove_const, :DATA)
      end

      it 'should allow access when nested in a module' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'A::DATA.values.keys')
        expect(helper.execute).to eq([])
      end

      it 'should not allow access at top level' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'DATA.values.keys')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Calling methods on 'DATA' not allowed."]))
      end
    end

    describe 'global constant' do
      it 'should not allow constant to be defined' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'MY_CONST = "abc"')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Defining a constant 'MY_CONST' is not allowed."]))
      end

      describe 'global streams' do
        [
          :STDIN, :STDOUT, :STDERR,
        ].each do |const|
          it "should not allow access to #{const}" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "#{const} << 'Hello World!'")
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                               %(["Calling methods on '#{const}' not allowed."]))
          end
        end
      end

      it 'should not allow access to ARGV' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'ARGV[0] == "a"')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Calling methods on 'ARGV' not allowed."]))
      end

      it 'should not allow access to TOPLEVEL_BINDING' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'TOPLEVEL_BINDING.to_s')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           %(["Calling methods on 'TOPLEVEL_BINDING' not allowed."]))
      end

      describe 'global strings' do
        [
          :ARGF, :DATA,
          :RUBY_RELEASE_DATE, :RUBY_DESCRIPTION,
          :RUBY_VERSION, :RUBY_PLATFORM, :RUBY_PATCH_LEVEL, :RUBY_REVISION, :RUBY_ENGINE, :RUBY_ENGINE_VERSION,
        ].each do |const|
          it "should not allow interpretation with #{const}" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, %("#\{#{const}}"))
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                               %(["Access to '#{const}' not allowed."]))
          end

          it "should not allow calling methods on #{const}" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, %(#{const} + "a"))
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                               %(["Calling methods on '#{const}' not allowed."]))
          end

          it "should not allow string #{const} as argument" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, %({}[#{const}]))
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                               %(["Access to '#{const}' not allowed."]))
          end

          it "should not allow #{const} to be assigned to local variable" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "a = #{const}")
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                               %(["Access to '#{const}' not allowed."]))
          end
        end
      end
    end

    describe 'global variables' do
      [
        :$stdout, :$stdin, :$stderr, :$LOADED_FEATURES, :$LOAD_PATH, :$PROGRAM_NAME, :$FILENAME, :$DEBUG,
        :$>, :$<, :$:, :$?, :$@, :$_, :$., :$!, :$$, :$*, :$-I, :$-W, :$-a, :$-d, :$-i, :$-l, :$-p, :$-v, :$-w, :$0,
      ].each do |var|
        it "should not allow method call on #{var}" do
          helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "#{var}.to_s")
          expect do
            helper.execute
          end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                             %(["Access to '#{var}' not allowed."]))
        end

        it "should not allow #{var} to be assigned to local variable" do
          helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "a = #{var}")
          expect do
            helper.execute
          end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                             %(["Access to '#{var}' not allowed."]))
        end

        it "should not allow access to #{var}" do
          helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, %("#\{#{var}}"))
          expect do
            helper.execute
          end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                             %(["Access to '#{var}' not allowed."]))
        end
      end

      describe 'with message that was hard to match in spec' do
        [:$"].each do |var|
          it "should not allow method call on #{var}" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "#{var}.to_s")
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled)
          end

          it "should not allow access to #{var}" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, %("#\{#{var}}"))
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled)
          end
        end
      end
    end

    describe 'program execution' do
      def check_program_execution_error(proc_string, message: %(["Running a program is not allowed."]))
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc_string)
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled, message)
      end

      it 'should not system commands via backticks' do
        check_program_execution_error('`ls -la /`')
      end

      it 'should not system commands via %x()' do
        check_program_execution_error('%x(ls -la /)')
      end

      it 'should not system commands via %x{}' do
        check_program_execution_error('%x{ls -la /}')
      end

      it 'should not system commands via %x--' do
        check_program_execution_error('%x-ls /-')
      end

      it 'reports system command execution only once' do
        check_program_execution_error('`ls -la /`;`ls -la /`')
      end

      it 'should not system commands via system()' do
        check_program_execution_error("system('ls /')", message: %(["Method 'system' not allowed."]))
      end

      it 'should not system commands via exec()' do
        check_program_execution_error("exec('ls /')", message: %(["Method 'exec' not allowed."]))
      end
    end

    it 'should validate save navigation methods' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'self&.send(:foo)')
      expect do
        helper.execute
      end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                         %(["Method 'send' not allowed."]))
    end

    it 'should report validation errors using the on_invalid callback' do
      invalid = []
      proc = 'Object.send(:foo).each do |f| f.bar end'
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, on_invalid: ->(msg) { invalid << msg })
      expect do
        helper.execute
      end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                         %(["Method 'bar' not allowed.", "Method 'send' not allowed."]))
      expect(invalid).to eq(["Method 'bar' not allowed.", "Method 'send' not allowed."])
    end

    it 'should validate the same source only once' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, '"Hi World!"')
      expect(helper).to receive(:validate_nodes).once
      expect(helper.execute).to eq('Hi World!')
      expect(helper.execute).to eq('Hi World!')
    end

    it 'should validate the same source multiple times in case it is invalid' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'Obj.send(:foo)')
      expect(helper).to receive(:validate_nodes).twice.and_call_original
      expect do
        helper.execute
      end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                         %(["Method 'send' not allowed."]))
      expect(helper.errors).to eq(["Method 'send' not allowed."])
      expect do
        helper.execute
      end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                         %(["Method 'send' not allowed."]))
      expect(helper.errors).to eq(["Method 'send' not allowed."])
    end
  end

  context 'debug context' do
    def in_test_uuid_scope(scope_hash = {})
      IPaaS::Connector::Connector.uuid_scope(scope_hash) do
        yield scope_hash
      end
    end

    it 'can fill debug context' do
      proc = -> { 'Hello World!' }
      IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
      debug_context = IPaaS::Connector::Common::ProcHelper.proc_debug_context(proc)
      expect(debug_context.keys).to contain_exactly(:file_content, :source_location, :line_content)
      expect(debug_context[:source_location][0]).to eq(__FILE__)
    end

    it 'can include uuid_scope' do
      allow(IPaaS).to receive(:solution_directory).and_return(__dir__)

      in_test_uuid_scope({ a: 'a' }) do
        proc = -> { 'Hello World!' }
        IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
        debug_context = IPaaS::Connector::Common::ProcHelper.proc_debug_context(proc)
        expect(debug_context.keys).to contain_exactly(:file_content, :source_location, :line_content, :cache_postfix)
        expect(debug_context[:cache_postfix])
          .to eq(IPaaS::Connector::Common::SourceLines.uuid_scope_postfix_for_error_msg)
      end
    end

    describe 'exception handling' do
      it 'capture context on error' do
        proc = -> { 'Hello World!' }
        expected_location = proc.source_location
        expected_source = proc.source
        calls = 0
        allow_any_instance_of(Proc).to receive(:source) do
          calls += 1
          raise 'Broken' unless calls > 1
          expected_source
        end

        expect { IPaaS::Connector::Common::ProcHelper.new(Object.new, proc) }
          .to raise_error(IPaaS::Connector::Common::ProcHelper::ProcSourceError) do |e|
          expect(e.message).to eq("Error retrieving proc source RuntimeError: 'Broken'")
          exception_context = e.context
          expect(exception_context.keys).to contain_exactly(:source_location, :line_content, :file_content)
          expect(exception_context[:source_location]).to eq(expected_location)
          expect(exception_context[:file_content]).to be_present
          expect(exception_context[:line_content]).to eq(expected_source.rstrip)
        end
      end

      it 'handles error even from withing error handler' do
        expect(MethodSource).to receive(:lines_for).and_raise('Oops').exactly(2).times
        proc = -> { 'Hello World!' }
        expect { IPaaS::Connector::Common::ProcHelper.new(Object.new, proc) }
          .to raise_error(IPaaS::Connector::Common::ProcHelper::ProcSourceError) do |e|
          expect(e.message)
            .to eq("Unable to get debug context: RuntimeError: 'Oops'. Original exception: RuntimeError: 'Oops'.")
          expect(e.context.keys).to contain_exactly(:source_location)
          expect(e.context[:source_location][0]).to eq(__FILE__)
        end
      end
    end
  end

  context 'connector proc' do
    it 'should execute basic proc' do
      proc = -> { 'Hello World!' }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
      expect(helper.execute).to eq('Hello World!')
    end

    it 'should execute proc with params' do
      proc = ->(n) { n * 2 }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
      expect(helper.execute(4)).to eq(8)
    end

    it 'should retrieve the Ruby source code for a proc' do
      proc = -> { 'Hello World!' }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
      expect(helper.source).to eq("proc = -> { 'Hello World!' }")
    end

    describe 'if_valid' do
      it 'should validate the methods' do
        proc = -> { Obj.send(:foo) }
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
        expect(helper.execute_if_valid).to be_nil
        expect(helper.errors).to eq(["Method 'send' not allowed."])
      end

      it 'should report validation errors using the on_invalid callback' do
        invalid = []
        proc = -> { Object.send(:foo).each(&:bar) }
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, on_invalid: ->(msg) { invalid << msg })
        expect(helper.execute_if_valid).to be_nil
        expect(invalid).to eq(["Method 'bar' not allowed.", "Method 'send' not allowed."])
      end
    end

    it 'should validate the methods' do
      proc = -> { Obj.send(:foo) }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc)
      expect do
        helper.execute
      end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                         %(["Method 'send' not allowed."]))
    end

    it 'should report validation errors using the on_invalid callback' do
      invalid = []
      proc = -> { Object.send(:foo).each(&:bar) }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, on_invalid: ->(msg) { invalid << msg })
      expect do
        helper.execute
      end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                         %(["Method 'bar' not allowed.", "Method 'send' not allowed."]))
      expect(invalid).to eq(["Method 'bar' not allowed.", "Method 'send' not allowed."])
    end
  end

  context 'nested procs' do
    it 'should run the nested proc in the context of the enclosing context when no context is provided' do
      proc_a = '"Hello #{helpers.proc_b}"'
      context = double(action: 'World!', helpers: double)
      context.helpers.define_singleton_method(:proc_b) do
        IPaaS::Connector::Common::ProcHelper.new(nil, 'action').execute
      end
      result = IPaaS::Connector::Common::ProcHelper.new(context, proc_a).execute
      expect(result).to eq('Hello World!')
    end

    it 'should run the nested proc in the provided context' do
      proc_a = '"Hello #{helpers.proc_b}"'
      context = double(action: 'World!', helpers: double)
      moon_context = double(action: 'Moon!')
      context.helpers.define_singleton_method(:proc_b) do
        IPaaS::Connector::Common::ProcHelper.new(moon_context, 'action').execute
      end
      result = IPaaS::Connector::Common::ProcHelper.new(context, proc_a).execute
      expect(result).to eq('Hello Moon!')
    end
  end

  describe '.validated_before cache' do
    let(:context) { Object.new }

    def new_field(id:, type:, required: false, array: false)
      IPaaS::Connector::Schema::Field.new(id: id, label: id.to_s, type: type, required: required, array: array)
    end

    before(:each) { described_class.validated_before.clear }

    describe 'field equivalence-class separation' do
      it 'reuses one cache entry for two distinct field instances with the same (required, type)' do
        source = '"Plain"'
        field_a = new_field(id: :a, type: :string)
        field_b = new_field(id: :b, type: :string)

        IPaaS::Connector::Common::ProcHelper.new(context, source, field: field_a).execute_if_valid

        # Second helper must hit the cache from the first; entry_count
        # alone could pass if mark_valid silently deduped while still
        # re-running validate_nodes.
        helper_b = IPaaS::Connector::Common::ProcHelper.new(context, source, field: field_b)
        expect(helper_b).not_to receive(:validate_nodes)
        helper_b.execute_if_valid

        expect(described_class.validated_before.size).to eq(1)
      end

      it 'separates entries when one field is required-boolean and the other is not' do
        source = '"Plain"'
        non_boolean = new_field(id: :a, type: :string, required: true)
        required_boolean = new_field(id: :b, type: :boolean, required: true)

        IPaaS::Connector::Common::ProcHelper.new(context, source, field: non_boolean).execute_if_valid
        IPaaS::Connector::Common::ProcHelper.new(context, source, field: required_boolean).execute_if_valid

        expect(described_class.validated_before.size).to eq(2)
      end

      it 'does NOT serve a stale non-required-boolean entry to a required-boolean lookup with &.present?' do
        source = 'value&.present?'
        non_required_boolean = new_field(id: :a, type: :string)
        helper_first = IPaaS::Connector::Common::ProcHelper.new(context, source, field: non_required_boolean)
        helper_first.valid?
        expect(helper_first.errors).to eq([])

        required_boolean = new_field(id: :b, type: :boolean, required: true)
        helper_required_boolean = IPaaS::Connector::Common::ProcHelper.new(context, source, field: required_boolean)

        expect(helper_required_boolean.valid?).to be(false)
        expect(helper_required_boolean.errors).to include(a_string_matching(/Safe navigation/))
      end

      it 'still serves a cached entry to fields that only differ in id or array' do
        source = '"Plain"'
        first = new_field(id: :a, type: :string, array: false)
        IPaaS::Connector::Common::ProcHelper.new(context, source, field: first).execute_if_valid

        differs_in_id_and_array = new_field(id: :z, type: :string, array: true)
        helper = IPaaS::Connector::Common::ProcHelper.new(context, source, field: differs_in_id_and_array)
        expect(helper).not_to receive(:validate_nodes)
        helper.execute_if_valid
      end
    end

    describe 'late ProcSafe registration safety' do
      # `ProcSafe.registry` only grows. A method becoming registered later
      # can promote a previously-invalid source to valid; the previously
      # invalid verdict was never cached, so no stale entry can poison it.
      it 'does not cache an invalid verdict, so later registration sees a fresh validation' do
        method_name = :"plan_d_late_registered_#{SecureRandom.hex(4)}"
        source = "#{method_name}()"

        first = IPaaS::Connector::Common::ProcHelper.new(context, source)
        expect(first.valid?).to be(false)
        expect(described_class.validated_before.size).to eq(0)

        IPaaS::Connector::Common::ProcRules::ProcSafe.registry << method_name
        begin
          second = IPaaS::Connector::Common::ProcHelper.new(context, source)
          expect(second.valid?).to be(true)
          expect(described_class.validated_before.size).to eq(1)
        ensure
          IPaaS::Connector::Common::ProcRules::ProcSafe.registry.delete(method_name)
        end
      end
    end
  end

  describe 'cache-key contract guard' do
    it 'pins ProcRules::FIELD_RULES to [NoSafePresentRule] so a new rule forces this spec to be re-read' do
      expect(IPaaS::Connector::Common::ProcRules::FIELD_RULES)
        .to eq([IPaaS::Connector::Common::ProcRules::NoSafePresentRule])
    end

    it 'pins NoSafePresentRule#should_validate? to reading only FIELD_VALIDATION_ATTRIBUTES' do
      # `method_source` (already used elsewhere in ProcHelper) reads the
      # method body from the on-disk source file.
      source = IPaaS::Connector::Common::ProcRules::NoSafePresentRule
               .instance_method(:should_validate?).source
      # Most-specific alternation first so `field.try(:required)` captures
      # `required` before the broader `field.<word>` pattern grabs `try`.
      referenced_attrs = source.scan(/field\.try\(\s*:([a-z_]+)|field&?\.([a-z_]+)/)
                               .flatten.compact.map(&:to_sym).uniq

      expect(referenced_attrs).to match_array(IPaaS::Connector::Common::ProcHelper::FIELD_VALIDATION_ATTRIBUTES)
    end

    # The attribute-name guard above does not pin that `field_validation_class`
    # computes the SAME predicate as `should_validate?` — both independently
    # re-encode `required && type == :boolean`. If the rule's predicate later
    # diverged while still reading those two attributes (e.g. `type == :string`),
    # the cache classifier would silently serve stale verdicts. This walks the
    # (required, type) matrix and asserts the classifier collapses to
    # `:required_boolean` exactly when the rule would activate.
    it 'keeps field_validation_class in lockstep with NoSafePresentRule#should_validate?' do
      context = Object.new
      types = [:boolean, :string, :integer]
      fields = [nil] + [true, false].product(types).map do |required, type|
        IPaaS::Connector::Schema::Field.new(id: :f, label: 'f', type: type, required: required)
      end

      fields.each do |field|
        rule = IPaaS::Connector::Common::ProcRules::NoSafePresentRule.new(context, field: field)
        helper = IPaaS::Connector::Common::ProcHelper.new(context, '"x"', field: field)

        classified_required_boolean = helper.send(:field_validation_class) == :required_boolean
        message = "field_validation_class diverged from should_validate? for #{field.inspect}"

        expect(classified_required_boolean).to eq(rule.send(:should_validate?)), message
      end
    end
  end

  describe '.captured_variables' do
    it 'returns local variables captured by the proc binding' do
      captured = Object.new
      proc = -> { 'Hello World!' }

      expect(described_class.captured_variables(proc)).to eq(captured: captured)
    end

    it 'ignores proc local variables when they do not capture local variables' do
      nested = create_proc_without_captured_variables
      proc = -> { 'Hello World!' }

      expect(described_class.captured_variables(proc)).to eq({})
      expect(nested).to be_a(Proc)
    end

    it 'returns local variables captured by nested proc local variables' do
      nested = create_proc_with_captured_variables
      proc = -> { 'Hello World!' }

      expect(described_class.captured_variables(proc)).to eq(captured: :captured)
      expect(nested).to be_a(Proc)
    end

    it 'does not loop endlessly when nested proc local variables are cyclic' do
      nested = create_proc_with_mutually_cyclic_proc_binding

      expect(described_class.captured_variables(nested)).to eq({})
      expect(nested).to be_a(Proc)
    end

    def create_proc_without_captured_variables
      -> { 'Hello World!' }
    end

    def create_proc_with_captured_variables
      captured = :captured
      -> { captured }
    end

    def create_proc_with_mutually_cyclic_proc_binding
      first = -> { second }
      second = -> { first }
      second.object_id
      first
    end
  end
end
