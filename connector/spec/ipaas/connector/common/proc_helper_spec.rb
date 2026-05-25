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
end
