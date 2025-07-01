# frozen_string_literal: true

require 'sidekiq'
require 'redis'
require 'concurrent'
require 'json'
require 'logger'

require_relative 'queue_throttled/version'
require_relative 'queue_throttled/configuration'
require_relative 'queue_throttled/queue_limiter'
require_relative 'queue_throttled/job_throttler'
require_relative 'queue_throttled/middleware'
require_relative 'queue_throttled/job'

# Auto-load Rails integration if Rails is available
begin
  require 'rails'
  require_relative 'queue_throttled/railtie'
rescue LoadError
  # Rails is not available, which is fine for non-Rails applications
end

module Sidekiq
  module QueueThrottled
    class << self
      def configure(config_source = nil)
        yield configuration if block_given?
        configuration.load_configuration!(config_source)
        configuration.validate!
      end

      def configuration
        @configuration ||= Configuration.new
      end

      attr_writer :configuration, :logger, :redis

      def logger
        @logger ||= begin
          logger = Logger.new($stdout)
          logger.level = Logger::INFO
          logger
        end
      end

      def redis
        @redis ||= Sidekiq.redis { |conn| conn }
      end
    end
  end
end

# Auto-load the middleware when the gem is required
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Sidekiq::QueueThrottled::Middleware
  end
end

# Auto-load configuration from sidekiq.yml if it exists
Sidekiq::QueueThrottled.configure
