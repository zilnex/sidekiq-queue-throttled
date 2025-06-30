# frozen_string_literal: true

module Sidekiq
  module QueueThrottled
    class QueueLimiter
      attr_reader :queue_name, :limit, :redis

      def initialize(queue_name, limit, redis = nil)
        @queue_name = queue_name.to_s
        @limit = limit.to_i
        @redis = redis || Sidekiq::QueueThrottled.redis
        @lock_key = "#{Sidekiq::QueueThrottled.configuration.redis_key_prefix}:queue:#{@queue_name}:lock"
        @counter_key = "#{Sidekiq::QueueThrottled.configuration.redis_key_prefix}:queue:#{@queue_name}:counter"
        @mutex = Concurrent::ReentrantReadWriteLock.new
      end

      def acquire_lock(worker_id = nil)
        worker_id ||= SecureRandom.uuid
        lock_id = "#{worker_id}:#{Time.now.to_f}"
        @mutex.with_write_lock do
          return false if limit_reached?

          increment_counter
          lock_id
        end
        false
      end

      def release_lock(lock_id)
        return false unless lock_id

        @mutex.with_write_lock { true }
      rescue StandardError => e
        Sidekiq::QueueThrottled.logger.error "Failed to release lock #{lock_id} for queue #{@queue_name}: #{e.message}"
        false
      end

      def current_count
        @mutex.with_read_lock { fetch_current_count }
      end

      def available_slots
        [0, @limit - current_count].max
      end

      def reset!
        @mutex.with_write_lock do
          @redis.del(@counter_key)
          pattern = "#{Sidekiq::QueueThrottled.configuration.redis_key_prefix}:queue:#{@queue_name}:lock:*"
          keys = @redis.keys(pattern)
          @redis.del(*keys) unless keys.empty?
        end
      end

      private

      def limit_reached?
        fetch_current_count >= @limit
      end

      def fetch_current_count
        count = @redis.get(@counter_key)
        result = count ? count.to_i : 0
        puts "DEBUG: get_current_count - key: #{@counter_key}, count: #{result}"
        result
      end

      def increment_counter
        puts "DEBUG: increment_counter - key: #{@counter_key}"
        @redis.multi do |multi|
          multi.incr(@counter_key)
          multi.expire(@counter_key, Sidekiq::QueueThrottled.configuration.throttle_ttl)
        end
        puts "DEBUG: increment_counter - after increment, count: #{fetch_current_count}"
      end

      def decrement_counter
        @redis.multi do |multi|
          multi.decr(@counter_key)
          multi.expire(@counter_key, Sidekiq::QueueThrottled.configuration.throttle_ttl)
        end
        current = fetch_current_count
        @redis.set(@counter_key, 0) if current.negative?
      end

      def acquire_redis_lock(lock_id)
        lock_key = "#{@lock_key}:#{lock_id}"
        @redis.set(lock_key, '1', nx: true, ex: Sidekiq::QueueThrottled.configuration.lock_ttl)
      end

      def release_redis_lock?(lock_id)
        lock_key = "#{@lock_key}:#{lock_id}"
        @redis.del(lock_key).positive?
      end
    end
  end
end
