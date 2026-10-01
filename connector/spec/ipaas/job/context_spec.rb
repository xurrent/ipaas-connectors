require 'spec_helper'

module SpecialInclusion
  extend ActiveSupport::Concern

  included do
    def special_included_method
      'my speciality'
    end
  end
end

describe IPaaS::Job::Context do
  class TestContext
    include IPaaS::Job::Context
  end

  let(:context) { TestContext.new }

  describe 'log' do
    it 'should log an info message' do
      expect_any_instance_of(Logger).to receive(:info).with('foo')
      context.log('foo')
    end

    it 'should allow interpolation' do
      expect_any_instance_of(Logger).to receive(:info).with('foo bie')
      context.log('foo %<bar>s', { bar: 'bie' })
    end

    it 'should allow message indifferent interpolation' do
      expect_any_instance_of(Logger).to receive(:info).with('foo bie')
      context.log('foo %<bar>s', { bar: 'bie' }.with_indifferent_access)
    end

    it 'returns nothing of what the logger returns' do
      context.logger = instance_double(Logger, info: Object.new)

      expect(context.log('foo')).to be_nil
    end
  end

  describe 'log routing precedence' do
    let(:sink) { spy('ambient sink') }

    it 'routes log to the ambient logger when no explicit logger is set' do
      IPaaS::Job::Context.with_ambient_logger(sink) do
        context.log('inside the window')
      end

      expect(sink).to have_received(:info).with('inside the window')
    end

    it 'falls back to the default logger outside the ambient window' do
      expect_any_instance_of(Logger).to receive(:info).with('outside the window')

      context.log('outside the window')

      expect(sink).not_to have_received(:info)
    end

    it 'prefers an explicitly assigned logger over the ambient logger' do
      explicit = spy('explicit logger')
      context.logger = explicit

      IPaaS::Job::Context.with_ambient_logger(sink) do
        context.log('to explicit')
      end

      expect(explicit).to have_received(:info).with('to explicit')
      expect(sink).not_to have_received(:info)
    end

    it 'consults an ambient logger installed after an earlier default-routed call' do
      # An earlier default-routed call must not pin the default into @logger, which would
      # shadow an ambient logger installed afterwards.
      expect_any_instance_of(Logger).to receive(:info).with('before window')
      context.log('before window')

      IPaaS::Job::Context.with_ambient_logger(sink) do
        context.log('inside window')
      end

      expect(sink).to have_received(:info).with('inside window')
    end
  end

  describe '.with_ambient_logger' do
    let(:sink) { spy('ambient sink') }

    it 'exposes the installed logger to ambient_logger within the block' do
      IPaaS::Job::Context.with_ambient_logger(sink) do
        expect(IPaaS::Job::Context.ambient_logger).to be(sink)
      end
    end

    it 'restores the previous ambient logger after the block' do
      expect(IPaaS::Job::Context.ambient_logger).to be_nil

      IPaaS::Job::Context.with_ambient_logger(sink) {}

      expect(IPaaS::Job::Context.ambient_logger).to be_nil
    end

    it 'restores the previous ambient logger even when the block raises' do
      boom = Class.new(StandardError)

      expect do
        IPaaS::Job::Context.with_ambient_logger(sink) { raise boom, 'boom' }
      end.to raise_error(boom)

      expect(IPaaS::Job::Context.ambient_logger).to be_nil
    end

    it 'restores the outer logger when a nested block exits' do
      outer = spy('outer')
      inner = spy('inner')

      IPaaS::Job::Context.with_ambient_logger(outer) do
        IPaaS::Job::Context.with_ambient_logger(inner) do
          expect(IPaaS::Job::Context.ambient_logger).to be(inner)
        end
        expect(IPaaS::Job::Context.ambient_logger).to be(outer)
      end
    end

    it 'does not leak the ambient logger to other threads' do
      seen_in_other_thread = :unset

      IPaaS::Job::Context.with_ambient_logger(sink) do
        seen_in_other_thread = Thread.new { IPaaS::Job::Context.ambient_logger }.value
      end

      expect(seen_in_other_thread).to be_nil
    end

    it 'isolates the ambient logger per fiber so concurrent request fibers stay separate' do
      # Fiber-local storage: a separate fiber does not see this fiber's sink. This is what
      # keeps requests isolated on a server that multiplexes them as fibers on shared threads.
      seen_in_other_fiber = :unset

      IPaaS::Job::Context.with_ambient_logger(sink) do
        seen_in_other_fiber = Fiber.new { IPaaS::Job::Context.ambient_logger }.resume
      end

      expect(seen_in_other_fiber).to be_nil
    end
  end

  describe 'discard_trigger_event!' do
    it 'should log an info message and raise an exception' do
      expect_any_instance_of(Logger).to receive(:info).with('foo')
      expect do
        context.discard_trigger_event!('foo')
      end.to raise_error(IPaaS::Job::DiscardTriggerEvent, 'foo')
    end

    it 'should allow message interpolation' do
      expect_any_instance_of(Logger).to receive(:info).with('foo bie')
      expect do
        context.discard_trigger_event!('foo %<bar>s', { bar: 'bie' })
      end.to raise_error(IPaaS::Job::DiscardTriggerEvent, 'foo bie')
    end

    it 'should allow message indifferent interpolation' do
      expect_any_instance_of(Logger).to receive(:info).with('foo bie')
      expect do
        context.discard_trigger_event!('foo %<bar>s', { bar: 'bie' }.with_indifferent_access)
      end.to raise_error(IPaaS::Job::DiscardTriggerEvent, 'foo bie')
    end
  end

  describe 'fail_job!' do
    it 'should log an error message and raise an exception' do
      expect_any_instance_of(Logger).to receive(:error).with('foo')
      expect do
        context.fail_job!('foo')
      end.to raise_error(IPaaS::Job::FailJob, 'foo')
    end

    it 'should allow message interpolation' do
      expect_any_instance_of(Logger).to receive(:error).with('foo bie')
      expect do
        context.fail_job!('foo %<bar>s', { bar: 'bie' })
      end.to raise_error(IPaaS::Job::FailJob, 'foo bie')
    end

    it 'should allow message indifferent interpolation' do
      expect_any_instance_of(Logger).to receive(:error).with('foo bie')
      expect do
        context.fail_job!('foo %<bar>s', { bar: 'bie' }.with_indifferent_access)
      end.to raise_error(IPaaS::Job::FailJob, 'foo bie')
    end
  end

  describe 'finish_job!' do
    it 'should log an info message and raise an exception' do
      expect_any_instance_of(Logger).to receive(:info).with('foo')
      expect do
        context.finish_job!('foo')
      end.to raise_error(IPaaS::Job::FinishJob, 'foo')
    end

    it 'should allow message interpolation' do
      expect_any_instance_of(Logger).to receive(:info).with('foo bie')
      expect do
        context.finish_job!('foo %<bar>s', { bar: 'bie' })
      end.to raise_error(IPaaS::Job::FinishJob, 'foo bie')
    end

    it 'should allow message indifferent interpolation' do
      expect_any_instance_of(Logger).to receive(:info).with('foo bie')
      expect do
        context.finish_job!('foo %<bar>s', { bar: 'bie' }.with_indifferent_access)
      end.to raise_error(IPaaS::Job::FinishJob, 'foo bie')
    end

    it 'should provide a default log message on finish_job!' do
      expect_any_instance_of(Logger).to receive(:info).with('Runbook execution completed')
      expect do
        context.finish_job!
      end.to raise_error(IPaaS::Job::FinishJob, 'Runbook execution completed')
    end
  end

  describe 'backoff' do
    it 'should log a message and raise an exception with default retry after' do
      Timecop.freeze do
        expect_any_instance_of(Logger).to receive(:info).with('foo')
        expect { context.backoff('foo') }
          .to raise_error(IPaaS::Job::RescheduleJob, 'foo') do |e|
          expect(e.reschedule_after).to eq(1.minute.from_now)
        end
      end
    end

    it 'should allow message interpolation' do
      expect_any_instance_of(Logger).to receive(:info).with('foo bie')
      expect do
        context.backoff('foo %<bar>s', { bar: 'bie' })
      end.to raise_error(IPaaS::Job::RescheduleJob, 'foo bie')
    end

    it 'should allow message indifferent interpolation' do
      expect_any_instance_of(Logger).to receive(:info).with('foo bie')
      expect do
        context.backoff('foo %<bar>s', { bar: 'bie' }.with_indifferent_access)
      end.to raise_error(IPaaS::Job::RescheduleJob, 'foo bie')
    end

    it 'should provide a default log message on backoff' do
      expect_any_instance_of(Logger).to receive(:info).with('Rescheduling as backoff was called.')
      expect do
        context.backoff
      end.to raise_error(IPaaS::Job::RescheduleJob, 'Rescheduling as backoff was called.')
    end

    it 'should log a message and raise an exception with custom retry after' do
      Timecop.freeze do
        expect_any_instance_of(Logger).to receive(:info).with('foo')
        expect { context.backoff('foo', retry_after: 5.minutes) }
          .to raise_error(IPaaS::Job::RescheduleJob, 'foo') do |e|
          expect(e.reschedule_after).to eq(5.minutes.from_now)
        end
      end
    end
  end

  context 'job context identifier' do
    it 'allows identifier to be set and retrieved' do
      expect(context.job_context_identifier).to be_nil

      context.job_context_identifier = 'foo bar'
      expect(context.job_context_identifier).to eq('foo bar')

      context.job_context_identifier = 'bar bar'
      expect(context.job_context_identifier).to eq('bar bar')

      context.job_context_identifier = ''
      expect(context.job_context_identifier).to be_nil
    end

    it 'does not log when setting same value' do
      expect_any_instance_of(Logger).not_to receive(:info)

      context.job_context_identifier = ''
    end

    it 'allows identifier to be cleared' do
      context.job_context_identifier = 'bar'
      expect(context.job_context_identifier).to eq('bar')

      context.job_context_identifier = ' '
      expect(context.job_context_identifier).to be_nil
    end
  end

  context 'dynamic extensions' do
    it 'should add extensions to already loaded classes' do
      expect(context).not_to respond_to(:special_included_method)
      IPaaS::Job::Context.extension(SpecialInclusion)
      expect(context).to respond_to(:special_included_method)
      expect(context.special_included_method).to eq('my speciality')
    end
  end
end
