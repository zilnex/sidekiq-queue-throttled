# frozen_string_literal: true

module Sidekiq
  module QueueThrottled
    class Configuration
      attr_accessor :queue_limits, :redis_key_prefix, :throttle_ttl, :lock_ttl, :retry_delay

      def initialize
        @queue_limits = {}
        @redis_key_prefix = 'sidekiq:queue_throttled'
        @throttle_ttl = 3600 # 1 hour
        @lock_ttl = 300 # 5 minutes
        @retry_delay = 5 # 5 seconds
      end

      def queue_limit(queue_name)
        @queue_limits[queue_name.to_s] || @queue_limits[queue_name.to_sym]
      end

      def set_queue_limit(queue_name, limit)
        @queue_limits[queue_name.to_s] = limit.to_i
      end

      def load_from_sidekiq_config!(sidekiq_config = nil)
        limits = sidekiq_config&.dig(:limits) || sidekiq_config&.dig('limits')
        return unless limits

        limits.each do |queue_name, limit|
          set_queue_limit(queue_name, limit)
        end
      end

      def load_from_yaml!(yaml_content)
        require 'yaml'
        config = YAML.safe_load(yaml_content)
        limits = config['limits'] || config[:limits]
        return unless limits

        limits.each do |queue_name, limit|
          set_queue_limit(queue_name, limit)
        end
      end

      def validate!
        @queue_limits.each do |queue_name, limit|
          unless limit.is_a?(Integer) && limit.positive?
            raise ArgumentError, "Queue limit for '#{queue_name}' must be a positive integer, got: #{limit}"
          end
        end
      end
    end
  end
end
