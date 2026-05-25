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
