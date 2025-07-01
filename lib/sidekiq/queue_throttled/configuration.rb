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
        # Try to get config from Sidekiq's configuration if not provided
        sidekiq_config ||= Sidekiq.options if defined?(Sidekiq.options)

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

      def load_from_yaml_file!(file_path = nil)
        # Try to find sidekiq.yml in common locations
        file_path ||= find_sidekiq_config_file
        return unless file_path && File.exist?(file_path)

        yaml_content = File.read(file_path)
        load_from_yaml!(yaml_content)
      end

      def load_configuration!(config_source = nil)
        # Load from provided config source first
        if config_source.is_a?(Hash)
          load_from_sidekiq_config!(config_source)
        elsif config_source.is_a?(String)
          if File.exist?(config_source)
            load_from_yaml_file!(config_source)
          else
            load_from_yaml!(config_source)
          end
        end

        # Then try to load from Sidekiq's configuration
        load_from_sidekiq_config!

        # Finally, try to load from sidekiq.yml file
        load_from_yaml_file!
      end

      def validate!
        @queue_limits.each do |queue_name, limit|
          unless limit.is_a?(Integer) && limit.positive?
            raise ArgumentError, "Queue limit for '#{queue_name}' must be a positive integer, got: #{limit}"
          end
        end
      end

      private

      def find_sidekiq_config_file
        # Common locations for sidekiq.yml
        possible_paths = [
          'config/sidekiq.yml',
          'sidekiq.yml',
          File.expand_path('config/sidekiq.yml'),
          File.expand_path('sidekiq.yml')
        ]

        # Also check if we're in a Rails app
        if defined?(Rails)
          possible_paths.unshift(
            Rails.root.join('config', 'sidekiq.yml').to_s
          )
        end

        possible_paths.find { |path| File.exist?(path) }
      end
    end
  end
end
