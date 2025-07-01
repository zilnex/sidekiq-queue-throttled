# Sidekiq Queue Throttled

A production-ready Sidekiq gem that combines queue-level concurrency limits with job-level throttling capabilities. This gem provides the best of both `sidekiq-limit_fetch` and `sidekiq-throttled` in a single, well-tested package.

## Features

- **Queue-level limits**: Set maximum concurrent jobs per queue
- **Job-level throttling**: Limit jobs by concurrency or rate
- **Redis-based**: Scalable across multiple Sidekiq processes
- **Production-ready**: Comprehensive error handling and logging
- **Thread-safe**: Uses concurrent primitives for safety
- **Configurable**: Flexible configuration options

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-queue-throttled'
```

And then execute:

```bash
$ bundle install
```

### Rails Applications

For Rails applications, the gem will be automatically loaded when your application starts. No additional configuration is required.

### Non-Rails Applications

For non-Rails applications, you need to explicitly require the gem:

```ruby
require 'sidekiq/queue_throttled'
```

## Configuration

### Queue Limits

Configure queue limits in your `sidekiq.yml`:

```yaml
:concurrency: 25
:queues:
  - [default, 1]
  - [high, 2]
  - [low, 1]

:limits:
  default: 100
  high: 50
  low: 200
```

Or configure programmatically:

```ruby
Sidekiq::QueueThrottled.configure do |config|
  config.set_queue_limit(:default, 100)
  config.set_queue_limit(:high, 50)
  config.set_queue_limit(:low, 200)
end
```

### Job Throttling

Include the `Sidekiq::QueueThrottled::Job` module in your job classes:

```ruby
class MyJob
  include Sidekiq::Job
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: :my_queue

  # Concurrency-based throttling
  sidekiq_throttle(
    concurrency: { 
      limit: 10, 
      key_suffix: -> (user_id) { user_id } 
    }
  )

  def perform(user_id)
    # Your job logic here
  end
end
```

## Usage Examples

### Basic Queue Limiting

```ruby
# sidekiq.yml
:limits:
  email_queue: 10
  processing_queue: 5

# This ensures email_queue never has more than 10 concurrent jobs
# and processing_queue never has more than 5 concurrent jobs
```

### Concurrency-based Job Throttling

```ruby
class UserNotificationJob
  include Sidekiq::Job
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: :notifications

  # Allow maximum 3 concurrent jobs per user
  sidekiq_throttle(
    concurrency: { 
      limit: 3, 
      key_suffix: -> (user_id) { user_id } 
    }
  )

  def perform(user_id, message)
    # Send notification to user
  end
end
```

### Rate-based Job Throttling

```ruby
class APICallJob
  include Sidekiq::Job
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: :api_calls

  # Allow maximum 100 jobs per hour per API key
  sidekiq_throttle(
    rate: { 
      limit: 100, 
      period: 3600, # 1 hour in seconds
      key_suffix: -> (api_key) { api_key } 
    }
  )

  def perform(api_key, endpoint)
    # Make API call
  end
end
```

### Complex Throttling with Multiple Parameters

```ruby
class DataProcessingJob
  include Sidekiq::Job
  include Sidekiq::QueueThrottled::Job

  sidekiq_options queue: :processing

  # Allow maximum 5 concurrent jobs per organization per data_type
  sidekiq_throttle(
    concurrency: { 
      limit: 5, 
      key_suffix: -> (org_id, data_type) { "#{org_id}:#{data_type}" } 
    }
  )

  def perform(org_id, data_type, data)
    # Process data
  end
end
```

## Configuration Options

### Global Configuration

```ruby
Sidekiq::QueueThrottled.configure do |config|
  # Redis key prefix for all keys
  config.redis_key_prefix = "sidekiq:queue_throttled"
  
  # TTL for throttle counters (in seconds)
  config.throttle_ttl = 3600 # 1 hour
  
  # TTL for queue locks (in seconds)
  config.lock_ttl = 300 # 5 minutes
  
  # Delay before rescheduling blocked jobs (in seconds)
  config.retry_delay = 5
end
```

### Custom Logger

```ruby
Sidekiq::QueueThrottled.logger = Rails.logger
```

### Custom Redis Connection

```ruby
Sidekiq::QueueThrottled.redis = Redis.new(url: ENV['REDIS_URL'])
```

## API Reference

### Queue Limiter

```ruby
limiter = Sidekiq::QueueThrottled::QueueLimiter.new(queue_name, limit)

# Acquire a lock (returns lock_id or false)
lock_id = limiter.acquire_lock?

# Release a lock
limiter.release_lock(lock_id)

# Get current count
current_count = limiter.current_count

# Get available slots
available = limiter.available_slots

# Reset counters
limiter.reset!
```

### Job Throttler

```ruby
throttler = Sidekiq::QueueThrottled::JobThrottler.new(job_class, throttle_config)

# Check if job can be processed
can_process = throttler.can_process?(args)

# Acquire a slot
acquired = throttler.acquire_slot(args)

# Release a slot
throttler.release_slot(args)
```

## Monitoring and Debugging

### Redis Keys

The gem uses the following Redis key patterns:

- Queue counters: `sidekiq:queue_throttled:queue:{queue_name}:counter`
- Queue locks: `sidekiq:queue_throttled:queue:{queue_name}:lock`
- Concurrency counters: `sidekiq:queue_throttled:concurrency:{job_class}:{key_suffix}`
- Rate counters: `sidekiq:queue_throttled:rate:{job_class}:{key_suffix}:{window}`

### Logging

The gem logs important events:

```
INFO: Queue limit reached for email_queue, rescheduling job
INFO: Job throttling limit reached for UserNotificationJob, rescheduling job
ERROR: Failed to release lock for queue email_queue: Redis connection error
```

## Testing

```ruby
# In your test setup
require 'sidekiq/queue_throttled'

RSpec.configure do |config|
  config.before(:each) do
    # Reset all counters
    Sidekiq::QueueThrottled.redis.flushdb
  end
end

# Test queue limits
RSpec.describe "Queue Limiting" do
  it "respects queue limits" do
    limiter = Sidekiq::QueueThrottled::QueueLimiter.new("test_queue", 2)
    
    expect(limiter.acquire_lock?).to be_truthy
    expect(limiter.acquire_lock?).to be_truthy
    expect(limiter.acquire_lock?).to be_falsey # Limit reached
  end
end
```

## Performance Considerations

- **Redis Operations**: The gem uses Redis for coordination, so ensure your Redis instance can handle the load
- **Memory Usage**: Counters are stored in Redis with TTL, so memory usage is bounded
- **Network Latency**: Consider Redis network latency when setting TTL values
- **Concurrent Access**: The gem uses thread-safe primitives for concurrent access

## Troubleshooting

### "uninitialized constant Sidekiq::QueueThrottled" Error

If you encounter this error when trying to use the gem:

```
uninitialized constant Sidekiq::QueueThrottled (NameError)
```

**For Rails applications:**
- Make sure the gem is properly added to your Gemfile
- Restart your Rails server after adding the gem
- The gem should auto-load when your Rails application starts

**For non-Rails applications:**
- Explicitly require the gem at the top of your file:
  ```ruby
  require 'sidekiq/queue_throttled'
  ```

**For IRB/Console:**
- If you're testing in IRB or Rails console, make sure to restart the console after adding the gem to your Gemfile

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes and version history. 
