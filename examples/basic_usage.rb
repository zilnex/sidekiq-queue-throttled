# frozen_string_literal: true

# Basic usage example for sidekiq-queue-throttled

require 'sidekiq/queue_throttled'

# Configure queue limits
Sidekiq::QueueThrottled.configure do |config|
  config.set_queue_limit(:email_queue, 10)
  config.set_queue_limit(:processing_queue, 5)
  config.set_queue_limit(:api_queue, 20)
end

# Example job with concurrency throttling
class UserNotificationJob
  include Sidekiq::Job
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: :email_queue

  # Allow maximum 3 concurrent jobs per user
  sidekiq_throttle(
    concurrency: {
      limit: 3,
      key_suffix: ->(user_id) { user_id }
    }
  )

  def perform(user_id, message)
    puts "Sending notification to user #{user_id}: #{message}"
    # Simulate work
    sleep(rand(1..3))
  end
end

# Example job with rate throttling
class APICallJob
  include Sidekiq::Job
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: :api_queue

  # Allow maximum 100 jobs per hour per API key
  sidekiq_throttle(
    rate: {
      limit: 100,
      period: 3600, # 1 hour in seconds
      key_suffix: ->(api_key) { api_key }
    }
  )

  def perform(api_key, endpoint, _data)
    puts "Making API call to #{endpoint} with key #{api_key}"
    # Simulate API call
    sleep(rand(0.1..0.5))
  end
end

# Example job with complex throttling
class DataProcessingJob
  include Sidekiq::Job
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: :processing_queue

  # Allow maximum 5 concurrent jobs per organization per data type
  sidekiq_throttle(
    concurrency: {
      limit: 5,
      key_suffix: ->(org_id, data_type) { "#{org_id}:#{data_type}" }
    }
  )

  def perform(org_id, data_type, _data)
    puts "Processing #{data_type} data for organization #{org_id}"
    # Simulate data processing
    sleep(rand(2..5))
  end
end

# Example of enqueuing jobs
if __FILE__ == $PROGRAM_NAME
  puts 'Enqueuing example jobs...'

  # Enqueue user notification jobs
  5.times do |i|
    UserNotificationJob.perform_async(123, "Test message #{i}")
  end

  # Enqueue API call jobs
  10.times do |i|
    APICallJob.perform_async('api_key_123', '/users', { id: i })
  end

  # Enqueue data processing jobs
  3.times do |i|
    DataProcessingJob.perform_async(456, 'users', { batch: i })
  end

  puts 'Jobs enqueued! Check your Sidekiq dashboard to see throttling in action.'
end
