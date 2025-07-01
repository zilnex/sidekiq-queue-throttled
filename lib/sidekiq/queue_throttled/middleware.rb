# frozen_string_literal: true

module Sidekiq
  module QueueThrottled
    class Middleware
      def initialize
        @queue_limiters = Concurrent::Map.new
        @job_throttlers = Concurrent::Map.new
      end

      def call(worker, job, queue, &block)
        queue_name = job['queue'] || queue
        job_class = worker.class.name

        return reschedule_and_return(job, queue_name, 'queue') unless queue_slot_available?(queue_name, job)
        return reschedule_and_return(job, queue_name, 'job') unless job_slot_available?(job_class, job['args'], job)

        process_job(job, queue_name, job_class, &block)
      end

      private

      def queue_slot_available?(queue_name, job)
        queue_limiter = get_queue_limiter(queue_name)
        return true unless queue_limiter

        lock_id = queue_limiter.acquire_lock?
        job['lock_id'] = lock_id if lock_id
        !!lock_id
      end

      def job_slot_available?(job_class, args, job)
        job_throttler = get_job_throttler(job_class)
        return true unless job_throttler

        acquired = job_throttler.acquire_slot(args)
        job['job_throttle_acquired'] = acquired
        acquired
      end

      def process_job(job, queue_name, job_class, &_block)
        queue_limiter = get_queue_limiter(queue_name)
        job_throttler = get_job_throttler(job_class)
        lock_id = job['lock_id']
        begin
          yield
        ensure
          queue_limiter&.release_lock(lock_id)
          job_throttler&.release_slot(job['args'])
        end
      end

      def reschedule_and_return(job, queue_name, type)
        msg = type == 'queue' ? 'Queue limit reached' : 'Job throttling limit reached'
        Sidekiq::QueueThrottled.logger.info "#{msg} for #{queue_name}, rescheduling job"
        reschedule_job(job, queue_name)
        nil
      end

      def get_queue_limiter(queue_name)
        limit = Sidekiq::QueueThrottled.configuration.queue_limit(queue_name)
        return nil unless limit

        @queue_limiters.compute_if_absent(queue_name) { QueueLimiter.new(queue_name, limit) }
      end

      def get_job_throttler(job_class)
        throttle_config = throttle_config_for(job_class)
        return nil unless throttle_config

        @job_throttlers.compute_if_absent(job_class) { JobThrottler.new(job_class, throttle_config) }
      end

      def throttle_config_for(job_class)
        if job_class.is_a?(String)
          klass = safe_const_get(job_class)
          return klass.sidekiq_throttle_config if klass.respond_to?(:sidekiq_throttle_config)
        elsif job_class.respond_to?(:sidekiq_throttle_config)
          return job_class.sidekiq_throttle_config
        end
        nil
      end

      def safe_const_get(class_name)
        Object.const_get(class_name)
      rescue NameError
        nil
      end

      def reschedule_job(job, queue_name)
        delay = Sidekiq::QueueThrottled.configuration.retry_delay
        job['at'] = Time.now.to_f + delay
        job['queue'] = queue_name
        Sidekiq.redis { |conn| conn.zadd('schedule', job['at'], job.to_json) }
      end
    end
  end
end
