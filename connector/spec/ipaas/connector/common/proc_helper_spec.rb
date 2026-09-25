require 'spec_helper'

describe IPaaS::Connector::Common::ProcHelper do
  def refused_path(name)
    "Access to '#{name}' is not allowed in expressions; only an approved set of classes is available. " \
      'Please file a request if access is needed.'
  end

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

  context 'recursion guard' do
    after { Thread.current[:executing_procs] = [] }

    def preload_stack(depth)
      Thread.current[:executing_procs] =
        Array.new(depth) { described_class.new(Object.new, "'x'") }
    end

    it 'raises a catchable RecursiveProcError once nesting reaches the limit' do
      preload_stack(described_class::MAX_PROC_DEPTH)
      expect { described_class.new(Object.new, "'ok'").execute }
        .to raise_error(described_class::RecursiveProcError, /refers back to itself/)
      expect(described_class::RecursiveProcError.ancestors).to include(StandardError)
    end

    it 'does not pop a frame it never pushed when it guards' do
      preload_stack(described_class::MAX_PROC_DEPTH)
      expect { described_class.new(Object.new, "'ok'").execute }
        .to raise_error(described_class::RecursiveProcError)
      expect(Thread.current[:executing_procs].size).to eq(described_class::MAX_PROC_DEPTH)
    end

    it 'allows nesting just below the limit' do
      preload_stack(described_class::MAX_PROC_DEPTH - 1)
      expect(described_class.new(Object.new, "'ok'").execute).to eq('ok')
    end
  end

  context 'deeply nested expression' do
    before(:each) { described_class.validated_before.clear }

    def deeply_nested(depth) = "#{'(' * depth}1#{')' * depth}"

    # The guard turns a stack overflow into a field error. Overflowing for real to get there costs
    # a deep stack and the memory to unwind it, and lands differently on different machines, so
    # inject it. That real sources reach it is covered by `.unevaluable_reason` above.
    def overflow_the_parse!
      allow_any_instance_of(described_class).to receive(:parse_ast).and_raise(SystemStackError)
    end

    describe '.unevaluable_reason' do
      it 'names nesting for a body that nests past the limit' do
        past_limit = 'true ? 1 : ' * (described_class::MAX_NESTING_DEPTH + 1)
        expect(described_class.unevaluable_reason("#{past_limit}1")).to eq(:too_deeply_nested)
      end

      it 'accepts a large but shallow body, so size alone is not what refuses' do
        shallow = "'#{'a' * (described_class::MAX_SOURCE_BYTES + 1)}'"
        expect(shallow.bytesize).to be > described_class::MAX_SOURCE_BYTES
        expect(described_class.unevaluable_reason(shallow)).to be_nil
      end

      # A body that will not parse can never load, and evaluating it to find out why recurses
      # far deeper than parsing it does. Nesting was never measured, so it must not be claimed.
      it 'names the parse failure, not nesting, for a body holding a syntax error' do
        expect(described_class.unevaluable_reason("'a'\ndef (\n")).to eq(:unparseable)
      end

      # Ripper raises here rather than returning nil, so an unrescued call escapes validation
      # entirely instead of refusing the source.
      it 'names the parse failure for a body naming an encoding that does not exist' do
        expect(described_class.unevaluable_reason("# encoding: not-a-real-encoding\n1 + 1"))
          .to eq(:unparseable)
      end

      it 'names the parse failure for a body no parse tree can be built for' do
        expect(described_class.unevaluable_reason("#{'(' * 20_000}1")).to eq(:unparseable)
      end
    end

    it 'refuses a source too large to parse safely' do
      oversized = "'#{'a' * (described_class::MAX_SOURCE_BYTES + 1)}'"
      helper = described_class.new(Object.new, oversized)
      expect(helper.valid?).to be(false)
      expect(helper.errors).to eq([described_class::TOO_LARGE_MESSAGE])
    end

    # The pill check reads comments through a full parse, so the size refusal only keeps an
    # unbounded source away from the parsers if it stops the checks after it from running.
    it 'refuses an oversized source without parsing it, even when it holds a data pill' do
      oversized = "mapping[\#{trigger_output}]\n#{"a = 1\n" * (described_class::MAX_SOURCE_BYTES / 3)}"
      expect(oversized.bytesize).to be > described_class::MAX_SOURCE_BYTES

      expect(IPaaS::Connector::Common::SourceParser).not_to receive(:read)
      helper = described_class.new(Object.new, oversized)
      expect(helper.valid?).to be(false)
      expect(helper.errors).to eq([described_class::TOO_LARGE_MESSAGE])
    end

    it 'accepts a source below the size cap, so the cap is what rejects' do
      helper = described_class.new(Object.new, "'#{'a' * (described_class::MAX_SOURCE_BYTES - 100)}'")
      expect(helper.valid?).to be(true)
    end

    # Two Ripper sexp nodes per parenthesis, plus four for the program and the constant, so these
    # two counts sit either side of the limit and nothing between them is untested.
    def last_accepted_nesting = (described_class::MAX_NESTING_DEPTH - 4) / 2

    it 'accepts a source at the limit, so the limit is what rejects' do
      helper = described_class.new(Object.new, deeply_nested(last_accepted_nesting))
      expect(helper.valid?).to be(true)
      expect(helper.errors).to be_empty
    end

    it 'refuses a source one level past the limit' do
      helper = described_class.new(Object.new, deeply_nested(last_accepted_nesting + 1))
      expect(helper.valid?).to be(false)
      expect(helper.errors).to eq([described_class::TOO_COMPLEX_MESSAGE])
    end

    # Fixing the pill would leave the author with the restructure still to do, so the refusal that
    # demands it is the one worth reporting. The reverse order holds where a pill is why the source
    # will not parse at all, which the example on that is about.
    it 'reports needing a restructure over a data pill, when a source has both' do
      helper = described_class.new(Object.new, "#{deeply_nested(250)}\n\#{pill}")

      expect(helper.valid?).to be(false)
      expect(helper.errors).to eq([described_class::TOO_COMPLEX_MESSAGE])
    end

    it 'counts nesting the parser recurses over, not source length' do
      flat = (0..described_class::MAX_NESTING_DEPTH).map { |i| "a#{i} = #{i}" }.join("\n")
      helper = described_class.new(Object.new, flat)
      expect(helper.valid?).to be(true)
      expect(helper.errors).to be_empty
    end

    it 'refuses a bracket-free deep expression, which no bracket count would catch' do
      past_limit = 'true ? 1 : ' * (described_class::MAX_NESTING_DEPTH + 1)
      helper = described_class.new(Object.new, "#{past_limit}1")
      expect(helper.valid?).to be(false)
      expect(helper.errors).to eq([described_class::TOO_COMPLEX_MESSAGE])
    end

    it 'reports a field error instead of letting SystemStackError escape' do
      overflow_the_parse!

      helper = described_class.new(Object.new, '1 + 1')
      valid = nil
      expect { valid = helper.valid? }.not_to raise_error
      expect(valid).to be(false)
      expect(helper.errors).to eq([described_class::TOO_COMPLEX_MESSAGE])
    end

    it 'does not cache the rejection, so the source is re-checked rather than passing later' do
      overflow_the_parse!

      described_class.new(Object.new, '1 + 1').valid?
      expect(described_class.validated_before).to be_empty
      expect(described_class.new(Object.new, '1 + 1').valid?).to be(false)
    end

    it 'leaves the process able to validate and to keep rejecting rule violations' do
      overflowing = described_class.new(Object.new, '1 + 1')
      allow(overflowing).to receive(:parse_ast).and_raise(SystemStackError)
      expect(overflowing.valid?).to be(false)

      expect(described_class.new(Object.new, '1 + 1').valid?).to be(true)
      rejected = described_class.new(Object.new, '$foo')
      expect(rejected.valid?).to be(false)
      expect(rejected.errors).to eq(["Access to '$foo' not allowed."])
    end

    it 'accepts an expression with nothing to parse' do
      expect(described_class.new(Object.new, '').valid?).to be(true)
      expect(described_class.new(Object.new, '# only a comment').valid?).to be(true)
    end

    it 'does not relabel an ordinary syntax error as a complexity failure' do
      helper = described_class.new(Object.new, 'def (')
      expect(helper.valid?).to be(false)
      expect(helper.errors).not_to include(described_class::TOO_COMPLEX_MESSAGE)
      expect(helper.errors.join).to match(/line 1: .*syntax error/)
    end

    it 'reports a field error for a bad encoding even when the source holds a data pill' do
      helper = described_class.new(Object.new, "# encoding: not-a-real-encoding\n\"\#{pill}\"")
      valid = nil
      expect { valid = helper.valid? }.not_to raise_error
      expect(valid).to be(false)
      expect(helper.errors.join).to include('not-a-real-encoding')
    end

    it 'reports a field error naming the encoding rather than letting ArgumentError escape' do
      helper = described_class.new(Object.new, "# encoding: not-a-real-encoding\n1 + 1")
      valid = nil
      expect { valid = helper.valid? }.not_to raise_error
      expect(valid).to be(false)
      expect(helper.errors.join).to include('not-a-real-encoding')
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

    it 'should pass a single false param to the proc' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, '->(v) { v }')
      expect(helper.execute(false)).to eq(false)
    end

    it 'should pass a single zero param to the proc' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, '->(v) { v }')
      expect(helper.execute(0)).to eq(0)
    end

    it 'should mirror the code as source' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "'Hello World!'")
      expect(helper.source).to eq("'Hello World!'")
    end

    describe 'if_valid' do
      it 'should validate the methods' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'params.send(:foo)')
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
        proc = 'params.send(:foo).each do |f| f.bar end'
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
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'params.send(:foo)')
        expect(helper).to receive(:validate_nodes).twice.and_call_original
        expect(helper.execute_if_valid).to be_nil
        expect(helper.errors).to eq(["Method 'send' not allowed."])
        expect(helper.execute_if_valid).to be_nil
        expect(helper.errors).to eq(["Method 'send' not allowed."])
      end
    end

    it 'should validate the methods' do
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'params.send(:foo)')
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
                           [refused_path('ENV')].to_s)
      end

      it 'should not allow environment variable to be read' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = ENV["PATH"]')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('ENV')].to_s)
      end

      it 'should not allow environment variable to be used as parameters' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = a[ENV["PATH"]]')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('ENV')].to_s)
      end

      it 'should not allow environment variables to be listed' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = ENV.keys')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('ENV')].to_s)
      end

      it 'should not allow environment variables to be changed' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'ENV["abc"] = "abc"')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('ENV')].to_s)
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
                           [refused_path('ENVx')].to_s)
      end

      it 'should not allow local variable set to ENVx' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'a = ENVx')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('ENVx')].to_s)
      end

      it 'should not allow access to ENVx' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, '"#{ENVx.values}"')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('ENVx')].to_s)
      end
    end

    describe 'access to classes with uppercase names' do
      # A path is matched whole, so `A::DATA` is judged as its own path and not as the global `DATA`
      # a scope such as `URI::` could resolve to; neither is on the list.
      it 'should not allow access when nested in a module' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'A::DATA.values.keys')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('A::DATA')].to_s)
      end

      it 'should not allow access at top level' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'DATA.values.keys')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('DATA')].to_s)
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
                               [refused_path(const)].to_s)
          end
        end
      end

      it 'should not allow access to ARGV' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'ARGV[0] == "a"')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('ARGV')].to_s)
      end

      it 'should not allow access to TOPLEVEL_BINDING' do
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'TOPLEVEL_BINDING.to_s')
        expect do
          helper.execute
        end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                           [refused_path('TOPLEVEL_BINDING')].to_s)
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
                               [refused_path(const)].to_s)
          end

          it "should not allow calling methods on #{const}" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, %(#{const} + "a"))
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                               [refused_path(const)].to_s)
          end

          it "should not allow string #{const} as argument" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, %({}[#{const}]))
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                               [refused_path(const)].to_s)
          end

          it "should not allow #{const} to be assigned to local variable" do
            helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, "a = #{const}")
            expect do
              helper.execute
            end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                               [refused_path(const)].to_s)
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
      proc = 'params.send(:foo).each do |f| f.bar end'
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
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, 'params.send(:foo)')
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
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, connector: spec_connector)
      expect(helper.execute).to eq('Hello World!')
    end

    it 'should execute proc with params' do
      proc = ->(n) { n * 2 }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, connector: spec_connector)
      expect(helper.execute(4)).to eq(8)
    end

    it 'should retrieve the Ruby source code for a proc' do
      proc = -> { 'Hello World!' }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, connector: spec_connector)
      expect(helper.source).to eq("proc = -> { 'Hello World!' }")
    end

    describe 'if_valid' do
      it 'should validate the methods' do
        proc = -> { params.send(:foo) }
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, connector: spec_connector)
        expect(helper.execute_if_valid).to be_nil
        expect(helper.errors).to eq(["Method 'send' not allowed."])
      end

      it 'should report validation errors using the on_invalid callback' do
        invalid = []
        proc = -> { params.send(:foo).each(&:bar) }
        helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, on_invalid: ->(msg) { invalid << msg },
                                                                            connector: spec_connector)
        expect(helper.execute_if_valid).to be_nil
        expect(invalid).to eq(["Method 'bar' not allowed.", "Method 'send' not allowed."])
      end
    end

    it 'should validate the methods' do
      proc = -> { params.send(:foo) }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, connector: spec_connector)
      expect do
        helper.execute
      end.to raise_error(IPaaS::Connector::Common::ProcHelper::InvalidProcCalled,
                         %(["Method 'send' not allowed."]))
    end

    it 'should report validation errors using the on_invalid callback' do
      invalid = []
      proc = -> { params.send(:foo).each(&:bar) }
      helper = IPaaS::Connector::Common::ProcHelper.new(Object.new, proc, on_invalid: ->(msg) { invalid << msg },
                                                                          connector: spec_connector)
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

  context 'bare data pill interpolation' do
    it 'flags a data pill used outside a string' do
      source = <<~'RUBY'
        mapping = { "critical" => "top" }
        impact = mapping[
        #{trigger_output&.drill(:query_params)}
        ] || "low"
      RUBY
      helper = described_class.new(Object.new, source)
      expect(helper.valid?).to be(false)
      expect(helper.errors.join("\n")).to include('outside a string')
    end

    # Pin the actionable wording so it can't silently drop again. Checks both fix paths so a
    # refactor can't remove one without failing the test.
    it 'includes actionable fix instructions in the error message' do
      source = "mapping[\n\#{trigger_output}\n]"
      helper = described_class.new(Object.new, source)
      expect(helper.valid?).to be(false)
      expect(helper.errors.join("\n")).to include('Remove the surrounding #{}')
      expect(helper.errors.join("\n")).to include('double-quoted string')
    end

    # Bare pill as the ENTIRE proc: ast is nil (whole expression is a Ruby comment).
    # This is the canonical bug shape and covers the nil-ast branch of parse_ast.
    it 'flags a bare pill as the entire proc with exactly one error message' do
      helper = described_class.new(Object.new, '#{trigger_output}')
      expect(helper.valid?).to be(false)
      expect(helper.errors.length).to eq(1)
      expect(helper.errors.join("\n")).to include('outside a string')
    end

    it 'flags a trailing bare data pill' do
      helper = described_class.new(Object.new, 'result = mapping #{trigger_output}')
      expect(helper.valid?).to be(false)
      expect(helper.errors.join("\n")).to include('outside a string')
    end

    # Here the `#{...}` comment eats the closing `]`, leaving a source that will not parse. The
    # actionable pill message must win over the syntax error, and must be the only error.
    it 'flags a single-line bare data pill with the actionable message, not the parser error' do
      helper = described_class.new(Object.new, 'mapping[#{trigger_output}]')
      expect(helper.valid?).to be(false)
      expect(helper.errors.length).to eq(1)
      expect(helper.errors.join("\n")).to include('outside a string')
    end

    it 'does not flag a data pill used inside a double-quoted string' do
      helper = described_class.new(Object.new, '"count: #{1 + 1}"')
      expect(helper.valid?).to be(true)
      expect(helper.errors.join("\n")).not_to include('outside a string')
    end

    # A literal `#{...}` inside single quotes is not interpolation and must not be flagged
    # (Ruby never lexes it as a comment). Contrast case for the comment scan.
    it 'does not flag a literal #{} inside a single-quoted string' do
      helper = described_class.new(Object.new, %q('prefix #{trigger_output} suffix'))
      expect(helper.valid?).to be(true)
      expect(helper.errors.join("\n")).not_to include('outside a string')
    end

    it 'does not flag an ordinary comment' do
      helper = described_class.new(Object.new, '1 + 1 # add the numbers')
      expect(helper.valid?).to be(true)
      expect(helper.errors.join("\n")).not_to include('outside a string')
    end
  end

  context 'node validation' do
    before(:each) { described_class.validated_before.clear }

    it 'hands the procedure to the node validator, so a rule may read the scope of a block' do
      procedure = -> { 1 }
      helper = described_class.new(Object.new, procedure, connector: spec_connector)
      expect(IPaaS::Connector::Common::ProcRules::NodeValidator).to receive(:new)
        .with(hash_including(procedure: procedure)).and_call_original

      expect(helper.valid?).to be(true)
    end

    it 'hands a String proc over as the procedure too' do
      helper = described_class.new(Object.new, "'x'")
      expect(IPaaS::Connector::Common::ProcRules::NodeValidator).to receive(:new)
        .with(hash_including(procedure: "'x'")).and_call_original

      expect(helper.valid?).to be(true)
    end
  end

  describe 'validation store per definition site' do
    let(:connector) { spec_connector }
    let(:other_connector) { IPaaS::Connector::Connector.new('other-connector') }

    before(:each) { described_class.validated_before.clear }

    def gem_block
      IPaaS::Connector::TriggerTemplate._config_schema_default_fields
    end

    def string_born_block
      described_class.new(Object.new, '-> { 1 }').execute
    end

    def key_of(helper)
      helper.send(:validation_cache_key)
    end

    describe 'GEM_LIB' do
      it 'names the gem lib directory, so a gem block is gem code and a spec block is not' do
        expect(described_class::GEM_LIB).to end_with('/connector/lib/')
        expect(gem_block.source_location.first).to start_with(described_class::GEM_LIB)
        expect(__FILE__).not_to start_with(described_class::GEM_LIB)
      end
    end

    describe 'a block from a connector file' do
      it 'records its verdict in the connector store and not in the process-wide cache' do
        block = -> { 1 }
        helper = described_class.new(Object.new, block, connector: connector)

        expect(helper.valid?).to be(true)
        expect(connector.proc_validations.include?(key_of(helper))).to be(true)
        expect(described_class.validated_before).to be_empty
      end

      it 'does not serve one connector a verdict recorded for another' do
        block = -> { 1 }
        described_class.new(Object.new, block, connector: connector).valid?

        second = described_class.new(Object.new, block, connector: other_connector)
        expect(second).to receive(:validate_nodes).and_call_original
        expect(second.valid?).to be(true)
        expect(other_connector.proc_validations.size).to eq(1)
      end

      it 'serves the same connector its own verdict without parsing again' do
        block = -> { 1 }
        described_class.new(Object.new, block, connector: connector).valid?

        second = described_class.new(Object.new, block, connector: connector)
        expect(second).not_to receive(:validate_nodes)
        expect(second.valid?).to be(true)
      end

      it 'raises and logs before judging anything when no connector is given' do
        block = -> { 1 }
        block_line = __LINE__ - 1
        helper = described_class.new(Object.new, block)
        expect(helper).not_to receive(:validate_nodes)
        expect(IPaaS.default_logger).to receive(:warn)
          .with("#{described_class::UNEXPECTED_PREFIX}: no connector owns the block from #{__FILE__}:#{block_line}")

        expect { helper.valid? }.to raise_error(described_class::MissingValidationStore,
                                                'No connector owns this block, so its validation cannot be recorded.')
        expect(described_class.validated_before).to be_empty
      end

      it 'raises when the connector given is not a Connector, whatever it answers' do
        block = -> { 1 }
        impostor = double(proc_validations: Set.new)
        helper = described_class.new(Object.new, block, connector: impostor)
        allow(IPaaS.default_logger).to receive(:warn)

        expect { helper.valid? }.to raise_error(described_class::MissingValidationStore)
      end
    end

    describe 'a String proc' do
      it 'records its verdict in the process-wide cache even when a connector is given' do
        described_class.new(Object.new, '1 + 1', connector: connector).valid?

        expect(described_class.validated_before.size).to eq(1)
        expect(connector.proc_validations.size).to eq(0)
      end
    end

    describe 'a block from a gem file' do
      it 'records its verdict in the process-wide cache even when a connector is given' do
        described_class.new(Object.new, gem_block, connector: connector).valid?

        expect(described_class.validated_before.size).to eq(1)
        expect(connector.proc_validations.size).to eq(0)
      end

      it 'needs no connector' do
        expect(described_class.new(Object.new, gem_block).valid?).to be(true)
      end
    end

    describe 'a block born inside a String proc' do
      it 'is refused and logged, with a connector or without, and nothing is recorded' do
        block = string_born_block
        expect(block.source_location.first).to eq(described_class::STRING_PROC_FILE)
        described_class.validated_before.clear
        expect(IPaaS.default_logger).to receive(:warn)
          .with(a_string_including('block born inside an expression')).twice

        [connector, nil].each do |owner|
          helper = described_class.new(Object.new, block, connector: owner)

          expect(helper.valid?).to be(false)
          expect(helper.errors).to eq([described_class::UNATTRIBUTED_BLOCK_MESSAGE])
        end
        expect(described_class.validated_before).to be_empty
        expect(connector.proc_validations.size).to eq(0)
      end

      it 'answers false again for a helper that already refused it, rather than raising' do
        block = string_born_block
        helper = described_class.new(Object.new, block, connector: connector)
        allow(IPaaS.default_logger).to receive(:warn)

        expect(helper.valid?).to be(false)
        expect(helper.valid?).to be(false)
        expect(helper.errors).to eq([described_class::UNATTRIBUTED_BLOCK_MESSAGE])
        expect { helper.execute }.to raise_error(described_class::InvalidProcCalled,
                                                 /cannot be validated/)
      end

      it 'refuses it even when its key is already recorded in the process-wide cache' do
        block = string_born_block
        helper = described_class.new(Object.new, block, connector: connector)
        described_class.validated_before.add(key_of(helper))
        allow(IPaaS.default_logger).to receive(:warn)

        expect(helper.valid?).to be(false)
        expect(helper.errors).to eq([described_class::UNATTRIBUTED_BLOCK_MESSAGE])
      end

      it 'logs the refusal before handing the message to a sink that raises' do
        block = string_born_block
        helper = described_class.new(Object.new, block, on_invalid: ->(message) { raise message })
        expect(IPaaS.default_logger).to receive(:warn)
          .with(a_string_including('block born inside an expression'))

        expect { helper.valid? }.to raise_error(RuntimeError, /cannot be validated/)
      end

      it 'refuses it without a store whatever the invalid sink returns' do
        block = string_born_block
        helper = described_class.new(Object.new, block, on_invalid: ->(_message) { true })
        allow(IPaaS.default_logger).to receive(:warn).and_return(true)

        expect(helper.valid?).to be(false)
        expect(helper.errors).to eq([described_class::UNATTRIBUTED_BLOCK_MESSAGE])
      end
    end

    describe 'inspect' do
      it 'names the origin of the block without following the connector' do
        block = -> { 1 }
        block_line = __LINE__ - 1
        helper = described_class.new(Object.new, block, connector: connector)

        expect(helper.inspect).to eq("ProcHelper (#{__FILE__}:#{block_line})")
        expect(described_class.new(Object.new, '1 + 1').inspect).to eq('ProcHelper (an expression field)')
      end
    end

    describe 'the key' do
      let(:gem_file) { IPaaS::Connector::OutboundConnectionTemplate.instance_method(:connector).source_location.first }

      # A gem block is exempt from the class allow-list, so its verdict must not answer for an expression
      # of the same text, which shares the process-wide store.
      it 'keeps a gem block\'s verdict from answering for an expression with the same text' do
        gem_block = eval('proc { 1 }', binding, gem_file, 1) # rubocop:disable Style/EvalWithLocation
        allow(described_class).to receive(:proc_source).and_call_original
        allow(described_class).to receive(:proc_source).with(gem_block).and_return('Psych.parse')

        expect(described_class.new(Object.new, gem_block).valid?).to be(true)
        expression = described_class.new(Object.new, 'Psych.parse')
        expect(expression.valid?).to be(false)
        expect(expression.errors).to contain_exactly(refused_path('Psych'))
      end

      it 'is the source digest and the field class in both stores' do
        global = described_class.new(Object.new, '1 + 1')
        global.valid?
        expect(described_class.validated_before).to include("#{Digest::SHA256.hexdigest('1 + 1')}:other")

        block = -> { 1 }
        scoped = described_class.new(Object.new, block, connector: connector)
        scoped.valid?
        expect(connector.proc_validations.include?("#{Digest::SHA256.hexdigest(scoped.source)}:other")).to be(true)
      end
    end
  end
end
