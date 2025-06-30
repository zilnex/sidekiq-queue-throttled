# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidekiq::QueueThrottled::JobThrottler do
  let(:job_class) { 'TestJob' }
  let(:throttler) { described_class.new(job_class, throttle_config) }

  describe '#initialize' do
    let(:throttle_config) { nil }

    it 'initializes without throttle config' do
      expect(throttler.job_class).to eq(job_class)
      expect(throttler.throttle_config).to be_nil
    end

    it 'uses provided redis connection' do
      custom_redis = double('redis')
      throttler = described_class.new(job_class, nil, custom_redis)
      expect(throttler.redis).to eq(custom_redis)
    end
  end

  describe '#can_process?' do
    context 'without throttle config' do
      let(:throttle_config) { nil }

      it 'returns true' do
        expect(throttler.can_process?([1, 2, 3])).to be_truthy
      end
    end

    context 'with concurrency config' do
      let(:throttle_config) do
        {
          concurrency: {
            limit: 2,
            key_suffix: ->(user_id) { user_id }
          }
        }
      end

      it 'returns true when under limit' do
        expect(throttler.can_process?([123])).to be_truthy
      end

      it 'returns false when at limit' do
        throttler.acquire_slot([123])
        throttler.acquire_slot([123])
        expect(throttler.can_process?([123])).to be_falsey
      end

      it 'allows different key suffixes' do
        throttler.acquire_slot([123])
        throttler.acquire_slot([123])
        expect(throttler.can_process?([456])).to be_truthy
      end
    end

    context 'with rate config' do
      let(:throttle_config) do
        {
          rate: {
            limit: 2,
            period: 60,
            key_suffix: ->(api_key) { api_key }
          }
        }
      end

      it 'returns true when under limit' do
        expect(throttler.can_process?(['key123'])).to be_truthy
      end

      it 'returns false when at limit' do
        throttler.acquire_slot(['key123'])
        throttler.acquire_slot(['key123'])
        expect(throttler.can_process?(['key123'])).to be_falsey
      end

      it 'resets after period' do
        throttler.acquire_slot(['key123'])
        throttler.acquire_slot(['key123'])

        Timecop.travel(Time.now + 61) do
          expect(throttler.can_process?(['key123'])).to be_truthy
        end
      end
    end

    context 'with invalid key_suffix' do
      let(:throttle_config) do
        {
          concurrency: {
            limit: 1,
            key_suffix: nil
          }
        }
      end

      it 'uses default key' do
        expect(throttler.can_process?([123])).to be_truthy
        throttler.acquire_slot([123])
        expect(throttler.can_process?([456])).to be_falsey # Same default key
      end
    end
  end

  describe '#acquire_slot' do
    context 'without throttle config' do
      let(:throttle_config) { nil }

      it 'returns true' do
        expect(throttler.acquire_slot([1, 2, 3])).to be_truthy
      end
    end

    context 'with concurrency config' do
      let(:throttle_config) do
        {
          concurrency: {
            limit: 2,
            key_suffix: ->(user_id) { user_id }
          }
        }
      end

      it 'acquires slot when under limit' do
        expect(throttler.acquire_slot([123])).to be_truthy
      end

      it 'fails to acquire slot when at limit' do
        throttler.acquire_slot([123])
        throttler.acquire_slot([123])
        expect(throttler.acquire_slot([123])).to be_falsey
      end

      it 'allows different key suffixes' do
        throttler.acquire_slot([123])
        throttler.acquire_slot([123])
        expect(throttler.acquire_slot([456])).to be_truthy
      end
    end

    context 'with rate config' do
      let(:throttle_config) do
        {
          rate: {
            limit: 2,
            period: 60,
            key_suffix: ->(api_key) { api_key }
          }
        }
      end

      it 'acquires slot when under limit' do
        expect(throttler.acquire_slot(['key123'])).to be_truthy
      end

      it 'fails to acquire slot when at limit' do
        throttler.acquire_slot(['key123'])
        throttler.acquire_slot(['key123'])
        expect(throttler.acquire_slot(['key123'])).to be_falsey
      end
    end
  end

  describe '#release_slot' do
    context 'without throttle config' do
      let(:throttle_config) { nil }

      it 'returns true' do
        expect(throttler.release_slot([1, 2, 3])).to be_truthy
      end
    end

    context 'with concurrency config' do
      let(:throttle_config) do
        {
          concurrency: {
            limit: 2,
            key_suffix: ->(user_id) { user_id }
          }
        }
      end

      it 'releases slot and decrements counter' do
        throttler.acquire_slot([123])
        expect(throttler.can_process?([123])).to be_truthy

        throttler.release_slot([123])
        expect(throttler.can_process?([123])).to be_truthy
      end

      it 'handles redis errors gracefully' do
        allow(throttler.redis).to receive(:multi).and_raise(Redis::BaseError.new('Connection error'))

        expect(throttler.release_slot([123])).to be_falsey
      end
    end

    context 'with rate config' do
      let(:throttle_config) do
        {
          rate: {
            limit: 2,
            period: 60,
            key_suffix: ->(api_key) { api_key }
          }
        }
      end

      it "returns true (rate limiting doesn't need release)" do
        expect(throttler.release_slot(['key123'])).to be_truthy
      end
    end
  end

  describe 'key suffix resolution' do
    context 'with proc key_suffix' do
      let(:throttle_config) do
        {
          concurrency: {
            limit: 2,
            key_suffix: ->(user_id, org_id) { "#{user_id}:#{org_id}" }
          }
        }
      end

      it 'calls proc with arguments' do
        expect(throttler.can_process?([123, 456])).to be_truthy
        throttler.acquire_slot([123, 456])
        expect(throttler.can_process?([123, 456])).to be_truthy
        expect(throttler.can_process?([123, 789])).to be_truthy
      end
    end

    context 'with symbol key_suffix' do
      let(:throttle_config) do
        {
          concurrency: {
            limit: 2,
            key_suffix: :id
          }
        }
      end

      it 'calls method on first argument' do
        user = double('user', id: 123)
        expect(throttler.can_process?([user])).to be_truthy
        throttler.acquire_slot([user])
        expect(throttler.can_process?([user])).to be_truthy
      end

      it 'handles non-responder gracefully' do
        expect(throttler.can_process?([123])).to be_truthy
      end
    end

    context 'with string key_suffix' do
      let(:throttle_config) do
        {
          concurrency: {
            limit: 1,
            key_suffix: 'fixed_key'
          }
        }
      end

      it 'uses string as key' do
        expect(throttler.can_process?([123])).to be_truthy
        throttler.acquire_slot([123])
        expect(throttler.can_process?([456])).to be_falsey # Same key
      end
    end

    context 'with invalid key_suffix' do
      let(:throttle_config) do
        {
          concurrency: {
            limit: 1,
            key_suffix: nil
          }
        }
      end

      it 'uses default key' do
        expect(throttler.can_process?([123])).to be_truthy
        throttler.acquire_slot([123])
        expect(throttler.can_process?([456])).to be_falsey # Same default key
      end
    end
  end

  describe 'redis key management' do
    let(:throttle_config) do
      {
        concurrency: {
          limit: 2,
          key_suffix: ->(user_id) { user_id }
        }
      }
    end

    it 'uses correct redis key prefix' do
      throttler.acquire_slot([123])

      keys = throttler.redis.keys('sidekiq:queue_throttled:concurrency:*')
      expect(keys).not_to be_empty
    end

    it 'sets TTL on concurrency keys' do
      throttler.acquire_slot([123])

      key = throttler.redis.keys('sidekiq:queue_throttled:concurrency:*').first
      ttl = throttler.redis.ttl(key)
      expect(ttl).to be > 0
    end

    it 'sets TTL on rate keys' do
      rate_config = {
        rate: {
          limit: 2,
          period: 60,
          key_suffix: ->(api_key) { api_key }
        }
      }
      rate_throttler = described_class.new(job_class, rate_config)
      rate_throttler.acquire_slot(['key123'])

      key = rate_throttler.redis.keys('sidekiq:queue_throttled:rate:*').first
      ttl = rate_throttler.redis.ttl(key)
      expect(ttl).to be > 0
    end
  end

  describe 'concurrent access' do
    let(:throttle_config) do
      {
        concurrency: {
          limit: 3,
          key_suffix: ->(user_id) { user_id }
        }
      }
    end

    it 'handles concurrent slot acquisitions' do
      threads = []
      results = []

      5.times do
        threads << Thread.new do
          result = throttler.acquire_slot([123])
          results << result
        end
      end

      threads.each(&:join)

      # Should only acquire 3 slots (the limit)
      acquired_slots = results.count { |r| r }
      expect(acquired_slots).to eq(3)
    end
  end
end
