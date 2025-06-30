# frozen_string_literal: true

module Sidekiq
  module QueueThrottled
    class JobThrottler
      attr_reader :job_class, :throttle_config, :redis

      def initialize(job_class, throttle_config, redis = nil)
        @job_class = job_class
        @throttle_config = throttle_config
        @redis = redis || Sidekiq::QueueThrottled.redis
        @mutex = Concurrent::ReentrantReadWriteLock.new
      end

      def can_process?(args)
        return true unless @throttle_config

        @mutex.with_read_lock do
          check_concurrency_limit(args) && check_rate_limit(args)
        end
      end

      def acquire_slot(args)
        return true unless @throttle_config

        @mutex.with_write_lock do
          return false unless can_process?(args)

          if @throttle_config[:concurrency]
            acquire_concurrency_slot(args)
          elsif @throttle_config[:rate]
            acquire_rate_slot(args)
          else
            true
          end
        end
      end

      def release_slot(args)
        return true unless @throttle_config

        @mutex.with_write_lock do
          if @throttle_config[:concurrency]
            release_concurrency_slot(args)
          end
          # Rate limiting slots are not released - they expire naturally
        end

        true
      rescue StandardError => e
        Sidekiq::QueueThrottled.logger.error "Failed to release slot for job #{@job_class}: #{e.message}"
        false
      end

      private

      def check_concurrency_limit(args)
        return true unless @throttle_config[:concurrency]

        config = @throttle_config[:concurrency]
        limit = config[:limit]
        key_suffix = resolve_key_suffix(config[:key_suffix], args)
        current_count = get_concurrency_count(key_suffix)

        current_count < limit
      end

      def check_rate_limit(args)
        return true unless @throttle_config[:rate]

        config = @throttle_config[:rate]
        limit = config[:limit]
        period = config[:period] || 60
        key_suffix = resolve_key_suffix(config[:key_suffix], args)

        current_count = get_rate_count(key_suffix, period)
        current_count < limit
      end

      def acquire_concurrency_slot(args)
        config = @throttle_config[:concurrency]
        key_suffix = resolve_key_suffix(config[:key_suffix], args)
        key = concurrency_key(key_suffix)

        @redis.multi do |multi|
          multi.incr(key)
          multi.expire(key, Sidekiq::QueueThrottled.configuration.throttle_ttl)
        end

        true
      end

      def release_concurrency_slot(args)
        config = @throttle_config[:concurrency]
        key_suffix = resolve_key_suffix(config[:key_suffix], args)
        key = concurrency_key(key_suffix)

        @redis.multi do |multi|
          multi.decr(key)
          multi.expire(key, Sidekiq::QueueThrottled.configuration.throttle_ttl)
        end

        true
      end

      def acquire_rate_slot(args)
        config = @throttle_config[:rate]
        period = config[:period] || 60
        key_suffix = resolve_key_suffix(config[:key_suffix], args)
        key = rate_key(key_suffix, period)

        @redis.multi do |multi|
          multi.incr(key)
          multi.expire(key, period)
        end

        true
      end

      def get_concurrency_count(key_suffix)
        key = concurrency_key(key_suffix)
        count = @redis.get(key)
        count ? count.to_i : 0
      end

      def get_rate_count(key_suffix, period)
        key = rate_key(key_suffix, period)
        count = @redis.get(key)
        count ? count.to_i : 0
      end

      def concurrency_key(key_suffix)
        "#{Sidekiq::QueueThrottled.configuration.redis_key_prefix}:concurrency:#{@job_class}:#{key_suffix}"
      end

      def rate_key(key_suffix, period)
        window = Time.now.to_i / period
        "#{Sidekiq::QueueThrottled.configuration.redis_key_prefix}:rate:#{@job_class}:#{key_suffix}:#{window}"
      end

      def resolve_key_suffix(key_suffix, args)
        case key_suffix
        when Proc
          key_suffix.call(*args)
        when Symbol
          args.first.send(key_suffix) if args.first.respond_to?(key_suffix)
        when String
          key_suffix
        else
          'default'
        end.to_s
      end
    end
  end
end
