# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidekiq::QueueThrottled::Configuration do
  let(:config) { described_class.new }

  describe '#set_queue_limit' do
    it 'sets queue limit as integer' do
      config.set_queue_limit(:test_queue, 100)
      expect(config.queue_limit(:test_queue)).to eq(100)
    end

    it 'converts string limit to integer' do
      config.set_queue_limit(:test_queue, '50')
      expect(config.queue_limit(:test_queue)).to eq(50)
    end

    it 'handles string queue names' do
      config.set_queue_limit('test_queue', 100)
      expect(config.queue_limit('test_queue')).to eq(100)
    end
  end

  describe '#queue_limit' do
    it 'returns limit for string queue name' do
      config.set_queue_limit('test_queue', 100)
      expect(config.queue_limit('test_queue')).to eq(100)
    end

    it 'returns limit for symbol queue name' do
      config.set_queue_limit(:test_queue, 100)
      expect(config.queue_limit(:test_queue)).to eq(100)
    end

    it 'returns nil for non-existent queue' do
      expect(config.queue_limit(:non_existent)).to be_nil
    end
  end

  describe '#load_from_sidekiq_config!' do
    let(:sidekiq_config) do
      {
        limits: {
          'queue1' => 100,
          'queue2' => 50
        }
      }
    end

    it 'loads limits from Sidekiq options' do
      config.load_from_sidekiq_config!(sidekiq_config)
      expect(config.queue_limit('queue1')).to eq(100)
      expect(config.queue_limit('queue2')).to eq(50)
    end

    it 'handles string keys in limits' do
      sidekiq_config_with_string_keys = {
        'limits' => {
          'queue1' => 100
        }
      }
      config.load_from_sidekiq_config!(sidekiq_config_with_string_keys)
      expect(config.queue_limit('queue1')).to eq(100)
    end

    it 'does nothing when limits are not defined' do
      empty_config = {}
      expect { config.load_from_sidekiq_config!(empty_config) }.not_to(change { config.queue_limits })
    end
  end

  describe '#load_from_yaml!' do
    let(:yaml_content) do
      <<~YAML
        limits:
          queue1: 100
          queue2: 50
      YAML
    end

    it 'loads limits from YAML content' do
      config.load_from_yaml!(yaml_content)
      expect(config.queue_limit('queue1')).to eq(100)
      expect(config.queue_limit('queue2')).to eq(50)
    end

    it 'handles string keys in YAML' do
      yaml_with_string_keys = <<~YAML
        "limits":
          "queue1": 100
      YAML
      config.load_from_yaml!(yaml_with_string_keys)
      expect(config.queue_limit('queue1')).to eq(100)
    end

    it 'does nothing when limits are not defined' do
      yaml_without_limits = <<~YAML
        other_config: value
      YAML
      expect { config.load_from_yaml!(yaml_without_limits) }.not_to(change { config.queue_limits })
    end
  end

  describe '#validate!' do
    it 'passes validation for valid limits' do
      config.set_queue_limit(:queue1, 100)
      config.set_queue_limit(:queue2, 50)
      expect { config.validate! }.not_to raise_error
    end

    it 'raises error for non-positive limits' do
      config.set_queue_limit(:queue1, 0)
      expect { config.validate! }.to raise_error(ArgumentError, /positive integer/)
    end

    it 'raises error for negative limits' do
      config.set_queue_limit(:queue1, -1)
      expect { config.validate! }.to raise_error(ArgumentError, /positive integer/)
    end

    it 'raises error for non-integer limits' do
      config.queue_limits[:queue1] = 'invalid'
      expect { config.validate! }.to raise_error(ArgumentError, /positive integer/)
    end
  end

  describe 'default values' do
    it 'has correct default redis_key_prefix' do
      expect(config.redis_key_prefix).to eq('sidekiq:queue_throttled')
    end

    it 'has correct default throttle_ttl' do
      expect(config.throttle_ttl).to eq(3600)
    end

    it 'has correct default lock_ttl' do
      expect(config.lock_ttl).to eq(300)
    end

    it 'has correct default retry_delay' do
      expect(config.retry_delay).to eq(5)
    end
  end
end
