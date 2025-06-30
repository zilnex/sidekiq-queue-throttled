# frozen_string_literal: true

require 'bundler/setup'
require 'sidekiq/queue_throttled'
require 'rspec'
require 'timecop'
require 'pry'

# Set up Redis for tests - use passwordless Redis for CI, passworded for local dev
redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379/0'

# Configure Sidekiq to use Redis
Sidekiq.configure_client { |c| c.redis = { url: redis_url } }
Sidekiq.configure_server { |c| c.redis = { url: redis_url } }
Sidekiq::QueueThrottled.redis = Redis.new(url: redis_url)

# Configure RSpec
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.order = :random
  Kernel.srand config.seed

  # Reset Redis before each test
  config.before(:each) do
    Sidekiq::QueueThrottled.redis.flushdb
    Sidekiq::QueueThrottled.configuration = Sidekiq::QueueThrottled::Configuration.new
  end
end

# Helper methods for testing
module TestHelpers
  def create_test_job_class(name = 'TestJob', &block)
    klass = Class.new do
      include Sidekiq::Job
      include Sidekiq::QueueThrottled::Job

      define_method(:perform) do |*args|
        # Default implementation
      end

      class_eval(&block) if block_given?
    end

    # Set the class name for better error messages and constant lookup
    klass.define_singleton_method(:name) { name }

    # Store the class in a constant so it can be looked up
    Object.const_set(name, klass) unless Object.const_defined?(name)

    klass
  end

  def wait_for_condition(timeout = 5, &condition)
    start_time = Time.now
    while Time.now - start_time < timeout
      return true if condition.call

      sleep 0.1
    end
    false
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
