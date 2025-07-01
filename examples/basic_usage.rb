# frozen_string_literal: true

# Basic usage example for sidekiq-queue-throttled gem
# This example shows how to use the gem in a non-Rails application

require 'sidekiq'
require 'sidekiq/queue_throttled'

# Configure the gem
# The gem will automatically try to load configuration from:
# 1. Any configuration you provide as an argument
# 2. Sidekiq's configuration options
# 3. sidekiq.yml file in common locations

# Option 1: Automatic configuration (recommended)
Sidekiq::QueueThrottled.configure

# Option 2: Configuration with custom limits
Sidekiq::QueueThrottled.configure({
                                    limits: {
                                      'high' => 10,
                                      'default' => 50,
                                      'low' => 100
                                    }
                                  })

# Option 3: Configuration with block
Sidekiq::QueueThrottled.configure do |config|
  config.set_queue_limit(:high, 10)
  config.set_queue_limit(:default, 50)
  config.set_queue_limit(:low, 100)

  # Customize other settings
  config.retry_delay = 10
  config.throttle_ttl = 7200
end

# Example job with queue-level throttling
class HighPriorityJob
  include Sidekiq::Worker

  sidekiq_options queue: 'high'

  def perform(data)
    puts "Processing high priority job with data: #{data}"
    # Your job logic here
  end
end

# Example job with job-level throttling
class EmailJob
  include Sidekiq::Worker
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: 'email'

  # Configure concurrency limiting
  sidekiq_throttle concurrency: { limit: 3, key_suffix: :user_id }

  def perform(user_id, email_data)
    puts "Sending email to user #{user_id}"
    # Your email sending logic here
  end
end

# Example job with rate limiting
class ApiCallJob
  include Sidekiq::Worker
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: 'api_calls'

  # Configure rate limiting (10 calls per minute per API key)
  sidekiq_throttle rate: { limit: 10, period: 60, key_suffix: :api_key }

  def perform(api_key, endpoint, data)
    puts "Making API call to #{endpoint} with key #{api_key}"
    # Your API call logic here
  end
end

# Enqueue jobs
HighPriorityJob.perform_async('important data')
EmailJob.perform_async(123, { subject: 'Hello', body: 'World' })
ApiCallJob.perform_async('api_key_123', '/users', { name: 'John' })

# The gem will automatically:
# 1. Apply queue-level limits from configuration
# 2. Apply job-level throttling based on sidekiq_throttle configuration
# 3. Reschedule jobs when limits are reached
# 4. Properly handle job lifecycle to prevent jobs from staying in "running" state
