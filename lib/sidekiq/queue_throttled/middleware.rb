# frozen_string_literal: true

module Sidekiq
  module QueueThrottled
    class Middleware
      def initialize
        @queue_limiters = Concurrent::Map.new
        @job_throttlers = Concurrent::Map.new
      end

      def call(worker, job, queue)
        queue_name = job['queue'] || queue
        job_class = worker.class.name

        # Check queue-level limits
        queue_limiter = get_queue_limiter(queue_name)
        if queue_limiter
          lock_id = queue_limiter.acquire_lock
          unless lock_id
            Sidekiq::QueueThrottled.logger.info "Queue limit reached for #{queue_name}, rescheduling job"
            reschedule_job(job, queue_name)
            return nil
          end
        end

        # Check job-level throttling
        job_throttler = get_job_throttler(job_class)
        if job_throttler && !job_throttler.acquire_slot(job['args'])
          Sidekiq::QueueThrottled.logger.info "Job throttling limit reached for #{job_class}, rescheduling job"
          reschedule_job(job, queue_name)
          return nil
        end

        # Process the job
        begin
          yield
        ensure
          # Release locks
          queue_limiter&.release_lock(lock_id)
          job_throttler&.release_slot(job['args'])
        end
      end

      private

      def get_queue_limiter(queue_name)
        limit = Sidekiq::QueueThrottled.configuration.queue_limit(queue_name)
        return nil unless limit

        @queue_limiters.compute_if_absent(queue_name) do
          QueueLimiter.new(queue_name, limit)
        end
      end

      def get_job_throttler(job_class)
        throttle_config = get_throttle_config(job_class)
        return nil unless throttle_config

        @job_throttlers.compute_if_absent(job_class) do
          JobThrottler.new(job_class, throttle_config)
        end
      end

      def get_throttle_config(job_class)
        # Handle string class names
        if job_class.is_a?(String)
          begin
            klass = Object.const_get(job_class)
            return klass.sidekiq_throttle_config if klass.respond_to?(:sidekiq_throttle_config)
          rescue NameError
            # For test classes that don't have proper constant names
            return nil
          end
        elsif job_class.respond_to?(:sidekiq_throttle_config)
          # Handle actual class objects
          return job_class.sidekiq_throttle_config
        end
        nil
      end

      def reschedule_job(job, queue_name)
        delay = Sidekiq::QueueThrottled.configuration.retry_delay
        job['at'] = Time.now.to_f + delay
        job['queue'] = queue_name

        Sidekiq.redis do |conn|
          conn.zadd('schedule', job['at'], job.to_json)
        end
      end
    end
  end
end
