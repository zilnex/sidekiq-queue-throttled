# frozen_string_literal: true

module Sidekiq
  module QueueThrottled
    module Job
      def self.included(base)
        base.extend(ClassMethods)
        base.class_eval do
          # Simple class attribute implementation
          class << self
            attr_accessor :sidekiq_throttle_config
          end

          def self.sidekiq_throttle_config
            @sidekiq_throttle_config
          end

          def self.sidekiq_throttle_config=(value)
            @sidekiq_throttle_config = value
          end
        end
      end

      module ClassMethods
        def sidekiq_throttle(options = {})
          validate_throttle_options!(options)
          self.sidekiq_throttle_config = options
        end

        private

        def validate_throttle_options!(options)
          return if options.empty?

          if options[:concurrency] && options[:rate]
            raise ArgumentError, 'Cannot specify both concurrency and rate limits'
          end

          if options[:concurrency]
            validate_concurrency_options!(options[:concurrency])
          end

          if options[:rate]
            validate_rate_options!(options[:rate])
          end
        end

        def validate_concurrency_options!(concurrency)
          unless concurrency.is_a?(Hash)
            raise ArgumentError, 'Concurrency must be a hash'
          end

          unless concurrency[:limit].is_a?(Integer) && concurrency[:limit].positive?
            raise ArgumentError, 'Concurrency limit must be a positive integer'
          end

          unless concurrency[:key_suffix]
            raise ArgumentError, 'Concurrency key_suffix is required'
          end
        end

        def validate_rate_options!(rate)
          unless rate.is_a?(Hash)
            raise ArgumentError, 'Rate must be a hash'
          end

          unless rate[:limit].is_a?(Integer) && rate[:limit].positive?
            raise ArgumentError, 'Rate limit must be a positive integer'
          end

          unless rate[:period].nil? || (rate[:period].is_a?(Integer) && rate[:period].positive?)
            raise ArgumentError, 'Rate period must be a positive integer'
          end

          unless rate[:key_suffix]
            raise ArgumentError, 'Rate key_suffix is required'
          end
        end
      end
    end
  end
end
