# frozen_string_literal: true

# Rails integration example for sidekiq-queue-throttled
# This file demonstrates how to use the gem in a Rails application

# In a Rails application, the gem will be automatically loaded
# when the application starts. You don't need to explicitly require it.

# Example Rails job class
class UserNotificationJob
  include Sidekiq::Job
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: :notifications

  # Allow maximum 3 concurrent jobs per user
  sidekiq_throttle(
    concurrency: {
      limit: 3,
      key_suffix: ->(user_id) { user_id }
    }
  )

  def perform(user_id, message)
    Rails.logger.info "Sending notification to user #{user_id}: #{message}"
    # Your notification logic here
  end
end

# Example of how to configure the gem in config/initializers/sidekiq_queue_throttled.rb
# (This would be in a separate file in a real Rails app)

Sidekiq::QueueThrottled.configure do |config|
  # Set queue limits
  config.set_queue_limit(:notifications, 10)
  config.set_queue_limit(:processing, 5)
  config.set_queue_limit(:api_calls, 20)

  # Configure Redis key prefix
  config.redis_key_prefix = 'myapp:sidekiq:queue_throttled'

  # Configure TTL values
  config.throttle_ttl = 3600 # 1 hour
  config.lock_ttl = 300 # 5 minutes
  config.retry_delay = 5
end

# Use Rails logger
Sidekiq::QueueThrottled.logger = Rails.logger

# Example usage in a Rails controller or service
# class NotificationsController < ApplicationController
#   def send_notification
#     user_id = params[:user_id]
#     message = params[:message]
#
#     UserNotificationJob.perform_async(user_id, message)
#     render json: { status: 'queued' }
#   end
# end
