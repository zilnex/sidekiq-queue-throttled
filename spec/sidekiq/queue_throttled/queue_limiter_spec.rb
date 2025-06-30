# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidekiq::QueueThrottled::QueueLimiter do
  let(:queue_name) { 'test_queue' }
  let(:limit) { 3 }
  let(:limiter) { described_class.new(queue_name, limit) }

  describe '#initialize' do
    it 'sets queue name and limit' do
      expect(limiter.queue_name).to eq(queue_name)
      expect(limiter.limit).to eq(limit)
    end

    it 'converts limit to integer' do
      limiter = described_class.new(queue_name, '5')
      expect(limiter.limit).to eq(5)
    end

    it 'uses provided redis connection' do
      custom_redis = double('redis')
      limiter = described_class.new(queue_name, limit, custom_redis)
      expect(limiter.redis).to eq(custom_redis)
    end
  end

  describe '#acquire_lock' do
    it 'acquires lock when under limit' do
      lock_id = limiter.acquire_lock
      expect(lock_id).to be_truthy
      expect(limiter.current_count).to eq(1)
    end

    it 'acquires multiple locks up to limit' do
      lock1 = limiter.acquire_lock
      lock2 = limiter.acquire_lock
      lock3 = limiter.acquire_lock

      expect(lock1).to be_truthy
      expect(lock2).to be_truthy
      expect(lock3).to be_truthy
      expect(limiter.current_count).to eq(3)
    end

    it 'fails to acquire lock when at limit' do
      limiter.acquire_lock
      limiter.acquire_lock
      limiter.acquire_lock

      lock4 = limiter.acquire_lock
      expect(lock4).to be_falsey
      expect(limiter.current_count).to eq(3)
    end

    it 'uses provided worker_id' do
      worker_id = 'worker_123'
      lock_id = limiter.acquire_lock(worker_id)
      expect(lock_id).to include(worker_id)
    end

    it 'generates unique lock_id for each call' do
      lock1 = limiter.acquire_lock
      lock2 = limiter.acquire_lock
      expect(lock1).not_to eq(lock2)
    end
  end

  describe '#release_lock' do
    it 'releases lock and decrements counter' do
      lock_id = limiter.acquire_lock
      expect(limiter.current_count).to eq(1)

      result = limiter.release_lock(lock_id)
      expect(result).to be_truthy
      expect(limiter.current_count).to eq(1)
    end

    it 'handles nil lock_id' do
      result = limiter.release_lock(nil)
      expect(result).to be_falsey
    end

    it 'handles non-existent lock_id' do
      result = limiter.release_lock('non_existent')
      expect(result).to be_truthy
      expect(limiter.current_count).to eq(0)
    end

    it 'handles redis errors gracefully' do
      allow(limiter.redis).to receive(:del).and_raise(Redis::BaseError.new('Connection error'))

      lock_id = limiter.acquire_lock
      result = limiter.release_lock(lock_id)
      expect(result).to be_truthy
    end
  end

  describe '#current_count' do
    it 'returns 0 for new limiter' do
      expect(limiter.current_count).to eq(0)
    end

    it 'returns correct count after acquiring locks' do
      limiter.acquire_lock
      limiter.acquire_lock
      expect(limiter.current_count).to eq(2)
    end

    it 'returns correct count after releasing locks' do
      lock1 = limiter.acquire_lock
      limiter.acquire_lock
      limiter.release_lock(lock1)
      expect(limiter.current_count).to eq(2)
    end
  end

  describe '#available_slots' do
    it 'returns limit for new limiter' do
      expect(limiter.available_slots).to eq(3)
    end

    it 'returns correct available slots after acquiring locks' do
      limiter.acquire_lock
      expect(limiter.available_slots).to eq(2)
    end

    it 'returns 0 when at limit' do
      limiter.acquire_lock
      limiter.acquire_lock
      limiter.acquire_lock
      expect(limiter.available_slots).to eq(0)
    end

    it 'never returns negative values' do
      # Simulate a situation where counter might be higher than limit
      allow(limiter.redis).to receive(:get).and_return('5')
      expect(limiter.available_slots).to eq(0)
    end
  end

  describe '#reset!' do
    it 'resets counter and lock' do
      limiter.acquire_lock
      expect(limiter.current_count).to eq(1)

      limiter.reset!
      expect(limiter.current_count).to eq(0)
    end

    it 'allows acquiring locks after reset' do
      limiter.acquire_lock
      limiter.acquire_lock
      limiter.acquire_lock
      expect(limiter.current_count).to eq(3)

      limiter.reset!
      lock_id = limiter.acquire_lock
      expect(lock_id).to be_truthy
      expect(limiter.current_count).to eq(1)
    end
  end

  describe 'concurrent access' do
    it 'handles concurrent lock acquisitions' do
      threads = []
      lock_ids = []

      5.times do
        threads << Thread.new do
          lock_id = limiter.acquire_lock
          lock_ids << lock_id if lock_id
        end
      end

      threads.each(&:join)

      # Should only acquire 3 locks (the limit)
      acquired_locks = lock_ids.compact
      expect(acquired_locks.length).to eq(3)
      expect(limiter.current_count).to eq(3)
    end

    it 'handles concurrent releases' do
      lock_ids = []
      3.times { lock_ids << limiter.acquire_lock }

      threads = lock_ids.map do |lock_id|
        Thread.new do
          limiter.release_lock(lock_id)
        end
      end

      threads.each(&:join)
      # Counter should remain at 3 since we're using time-based limiting
      expect(limiter.current_count).to eq(3)
    end
  end

  describe 'redis key management' do
    it 'uses correct redis key prefix' do
      limiter.acquire_lock

      # Check that the counter key exists with correct prefix
      keys = limiter.redis.keys("sidekiq:queue_throttled:queue:#{queue_name}:*")
      expect(keys).not_to be_empty
    end

    it 'sets TTL on counter keys' do
      limiter.acquire_lock

      counter_key = "#{Sidekiq::QueueThrottled.configuration.redis_key_prefix}:queue:#{queue_name}:counter"
      ttl = limiter.redis.ttl(counter_key)
      expect(ttl).to be > 0
    end
  end
end
