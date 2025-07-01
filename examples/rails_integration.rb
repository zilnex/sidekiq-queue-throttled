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

# In your Rails application, you can configure the gem in several ways:

# 1. Automatic configuration (recommended)
# The gem will automatically load configuration from:
# - config/sidekiq.yml (if it exists)
# - Sidekiq's configuration options
# - Any additional configuration you provide

# In config/initializers/sidekiq_queue_throttled.rb:
Sidekiq::QueueThrottled.configure do |config|
  # You can override or add additional configuration here
  config.retry_delay = 10 # Increase retry delay to 10 seconds
  config.throttle_ttl = 7200 # Increase TTL to 2 hours
end

# 2. Configuration with custom config source
# You can also pass a configuration hash or YAML file path:
Sidekiq::QueueThrottled.configure({
                                    limits: {
                                      'email' => 5,
                                      'processing' => 3,
                                      'api_calls' => 10
                                    }
                                  })

# 3. Configuration with YAML file path
Sidekiq::QueueThrottled.configure('config/custom_sidekiq.yml')

# 4. Configuration with YAML content string
yaml_config = <<~YAML
  limits:
    email: 5
    processing: 3
    api_calls: 10
YAML
Sidekiq::QueueThrottled.configure(yaml_config)

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
