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
          raise ArgumentError, 'Cannot specify both concurrency and rate limits' if both_limits?(options)

          validate_concurrency_options!(options[:concurrency]) if options[:concurrency]
          validate_rate_options!(options[:rate]) if options[:rate]
        end

        def both_limits?(options)
          options[:concurrency] && options[:rate]
        end

        def validate_concurrency_options!(concurrency)
          raise ArgumentError, 'Concurrency must be a hash' unless concurrency.is_a?(Hash)

          unless concurrency[:limit].is_a?(Integer) && concurrency[:limit].positive?
            raise ArgumentError,
                  'Concurrency limit must be a positive integer'
          end
          raise ArgumentError, 'Concurrency key_suffix is required' unless concurrency[:key_suffix]
        end

        def validate_rate_options!(rate)
          raise ArgumentError, 'Rate must be a hash' unless rate.is_a?(Hash)
          raise ArgumentError, 'Rate limit must be a positive integer' unless valid_rate_limit?(rate)
          raise ArgumentError, 'Rate period must be a positive integer' unless valid_rate_period?(rate)
          raise ArgumentError, 'Rate key_suffix is required' unless rate[:key_suffix]
        end

        def valid_rate_limit?(rate)
          rate[:limit].is_a?(Integer) && rate[:limit].positive?
        end

        def valid_rate_period?(rate)
          rate[:period].nil? || (rate[:period].is_a?(Integer) && rate[:period].positive?)
        end
      end
    end
  end
end
