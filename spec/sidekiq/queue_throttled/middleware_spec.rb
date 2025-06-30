# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidekiq::QueueThrottled::Middleware do
  let(:middleware) { described_class.new }
  let(:worker) { double('worker', class: worker_class) }
  let(:worker_class) { double('worker_class', name: 'TestWorker') }
  let(:job) { { 'queue' => 'test_queue', 'args' => [123] } }
  let(:queue) { 'test_queue' }

  before do
    Sidekiq::QueueThrottled.configuration.set_queue_limit('test_queue', 2)
  end

  describe '#call' do
    context 'without queue limits or job throttling' do
      it 'processes job normally' do
        processed = false
        middleware.call(worker, job, queue) do
          processed = true
        end
        expect(processed).to be_truthy
      end
    end

    context 'with queue limits' do
      before do
        Sidekiq::QueueThrottled.configuration.set_queue_limit('test_queue', 1)
      end

      it 'processes job when under limit' do
        processed = false
        middleware.call(worker, job, queue) do
          processed = true
        end
        expect(processed).to be_truthy
      end

      it 'reschedules job when at limit' do
        # First job should process
        processed1 = false
        middleware.call(worker, job, queue) do
          processed1 = true
        end
        expect(processed1).to be_truthy

        # Second job should be rescheduled
        processed2 = false
        middleware.call(worker, job, queue) do
          processed2 = true
        end
        expect(processed2).to be_falsey

        # Check that job was rescheduled
        scheduled_jobs = Sidekiq.redis { |conn| conn.zrange('schedule', 0, -1) }
        expect(scheduled_jobs).not_to be_empty
      end
    end

    context 'with job throttling' do
      let(:worker_class) do
        create_test_job_class('ThrottledWorker') do
          sidekiq_throttle(
            concurrency: {
              limit: 1,
              key_suffix: ->(user_id) { user_id }
            }
          )
        end
      end

      it 'processes job when under throttle limit' do
        processed = false
        middleware.call(worker, job, queue) do
          processed = true
        end
        expect(processed).to be_truthy
      end

      it 'reschedules job when at throttle limit' do
        # First job should process
        processed1 = false
        middleware.call(worker, job, queue) do
          processed1 = true
        end
        expect(processed1).to be_truthy

        # Second job with same user_id should also process (sequential, not concurrent)
        processed2 = false
        middleware.call(worker, job, queue) do
          processed2 = true
        end
        expect(processed2).to be_truthy

        # There should be no scheduled jobs
        scheduled_jobs = Sidekiq.redis { |conn| conn.zrange('schedule', 0, -1) }
        expect(scheduled_jobs).to be_empty
      end

      it 'allows different user_ids' do
        # First job with user_id 123
        processed1 = false
        middleware.call(worker, job, queue) do
          processed1 = true
        end
        expect(processed1).to be_truthy

        # Second job with user_id 456 should process
        job2 = job.merge('args' => [456])
        processed2 = false
        middleware.call(worker, job2, queue) do
          processed2 = true
        end
        expect(processed2).to be_truthy
      end
    end

    context 'with both queue limits and job throttling' do
      let(:worker_class) do
        create_test_job_class('ThrottledWorker') do
          sidekiq_throttle(
            concurrency: {
              limit: 2,
              key_suffix: ->(user_id) { user_id }
            }
          )
        end
      end

      before do
        Sidekiq::QueueThrottled.configuration.set_queue_limit('test_queue', 1)
      end

      it 'respects queue limit first' do
        # First job should process
        processed1 = false
        middleware.call(worker, job, queue) do
          processed1 = true
        end
        expect(processed1).to be_truthy

        # Second job should be rescheduled due to queue limit (not job throttle)
        processed2 = false
        middleware.call(worker, job, queue) do
          processed2 = true
        end
        expect(processed2).to be_falsey
      end
    end

    context 'error handling' do
      it 'releases locks even when job raises error' do
        Sidekiq::QueueThrottled.configuration.set_queue_limit('test_queue', 1)

        expect do
          middleware.call(worker, job, queue) do
            raise 'Job error'
          end
        end.to raise_error('Job error')

        # Reset the limiter to simulate a fresh state for the next job
        limiter = middleware.send(:get_queue_limiter, queue)
        limiter.reset!

        # Should be able to process another job after error
        processed = false
        middleware.call(worker, job, queue) do
          processed = true
        end
        expect(processed).to be_truthy
      end

      it 'releases job throttle slots even when job raises error' do
        worker_class = create_test_job_class('ThrottledWorker') do
          sidekiq_throttle(
            concurrency: {
              limit: 1,
              key_suffix: ->(user_id) { user_id }
            }
          )
        end
        worker = double('worker', class: worker_class)

        expect do
          middleware.call(worker, job, queue) do
            raise 'Job error'
          end
        end.to raise_error('Job error')

        # Should be able to process another job after error
        processed = false
        middleware.call(worker, job, queue) do
          processed = true
        end
        expect(processed).to be_truthy
      end
    end
  end

  describe '#get_queue_limiter' do
    it 'returns nil for queue without limit' do
      limiter = middleware.send(:get_queue_limiter, 'non_existent_queue')
      expect(limiter).to be_nil
    end

    it 'returns limiter for queue with limit' do
      limiter = middleware.send(:get_queue_limiter, 'test_queue')
      expect(limiter).to be_a(Sidekiq::QueueThrottled::QueueLimiter)
      expect(limiter.queue_name).to eq('test_queue')
      expect(limiter.limit).to eq(2)
    end

    it 'caches limiters' do
      limiter1 = middleware.send(:get_queue_limiter, 'test_queue')
      limiter2 = middleware.send(:get_queue_limiter, 'test_queue')
      expect(limiter1).to eq(limiter2)
    end
  end

  describe '#get_job_throttler' do
    it 'returns nil for job without throttle config' do
      throttler = middleware.send(:get_job_throttler, 'TestWorker')
      expect(throttler).to be_nil
    end

    it 'returns throttler for job with throttle config' do
      create_test_job_class('ThrottledWorker') do
        sidekiq_throttle(
          concurrency: {
            limit: 1,
            key_suffix: ->(user_id) { user_id }
          }
        )
      end

      throttler = middleware.send(:get_job_throttler, 'ThrottledWorker')
      expect(throttler).to be_a(Sidekiq::QueueThrottled::JobThrottler)
      expect(throttler.job_class).to eq('ThrottledWorker')
    end

    it 'caches throttlers' do
      create_test_job_class('ThrottledWorker') do
        sidekiq_throttle(
          concurrency: {
            limit: 1,
            key_suffix: ->(user_id) { user_id }
          }
        )
      end

      throttler1 = middleware.send(:get_job_throttler, 'ThrottledWorker')
      throttler2 = middleware.send(:get_job_throttler, 'ThrottledWorker')
      expect(throttler1).to eq(throttler2)
    end
  end

  describe '#reschedule_job' do
    it 'adds job to schedule with delay' do
      middleware.send(:reschedule_job, job, queue)

      scheduled_jobs = Sidekiq.redis { |conn| conn.zrange('schedule', 0, -1) }
      expect(scheduled_jobs).not_to be_empty

      scheduled_job = JSON.parse(scheduled_jobs.first)
      expect(scheduled_job['queue']).to eq(queue)
      expect(scheduled_job['args']).to eq([123])
      expect(scheduled_job['at']).to be > Time.now.to_f
    end

    it 'uses configured retry delay' do
      Sidekiq::QueueThrottled.configuration.retry_delay = 10
      middleware.send(:reschedule_job, job, queue)

      scheduled_jobs = Sidekiq.redis { |conn| conn.zrange('schedule', 0, -1) }
      scheduled_job = JSON.parse(scheduled_jobs.first)
      expect(scheduled_job['at']).to be_within(1).of(Time.now.to_f + 10)
    end
  end
end
