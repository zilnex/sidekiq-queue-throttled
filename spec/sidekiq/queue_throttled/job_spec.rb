# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sidekiq::QueueThrottled::Job do
  describe 'DSL' do
    let(:job_class) do
      create_test_job_class('TestJob') do
        sidekiq_throttle(
          concurrency: {
            limit: 10,
            key_suffix: ->(user_id) { user_id }
          }
        )
      end
    end

    it 'sets throttle config on class' do
      config = job_class.sidekiq_throttle_config
      expect(config[:concurrency][:limit]).to eq(10)
      expect(config[:concurrency][:key_suffix]).to be_a(Proc)
    end

    it 'allows empty throttle config' do
      job_class = create_test_job_class('EmptyJob') do
        sidekiq_throttle({})
      end
      expect(job_class.sidekiq_throttle_config).to eq({})
    end
  end

  describe 'validation' do
    it 'raises error for both concurrency and rate' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(
            concurrency: { limit: 10, key_suffix: ->(id) { id } },
            rate: { limit: 100, period: 60, key_suffix: ->(id) { id } }
          )
        end
      end.to raise_error(ArgumentError, /Cannot specify both concurrency and rate limits/)
    end

    it 'raises error for invalid concurrency config' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(concurrency: 'invalid')
        end
      end.to raise_error(ArgumentError, /Concurrency must be a hash/)
    end

    it 'raises error for missing concurrency limit' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(
            concurrency: { key_suffix: ->(id) { id } }
          )
        end
      end.to raise_error(ArgumentError, /Concurrency limit must be a positive integer/)
    end

    it 'raises error for non-positive concurrency limit' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(
            concurrency: { limit: 0, key_suffix: ->(id) { id } }
          )
        end
      end.to raise_error(ArgumentError, /Concurrency limit must be a positive integer/)
    end

    it 'raises error for missing concurrency key_suffix' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(concurrency: { limit: 10 })
        end
      end.to raise_error(ArgumentError, /Concurrency key_suffix is required/)
    end

    it 'raises error for invalid rate config' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(rate: 'invalid')
        end
      end.to raise_error(ArgumentError, /Rate must be a hash/)
    end

    it 'raises error for missing rate limit' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(
            rate: { period: 60, key_suffix: ->(id) { id } }
          )
        end
      end.to raise_error(ArgumentError, /Rate limit must be a positive integer/)
    end

    it 'raises error for non-positive rate limit' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(
            rate: { limit: 0, period: 60, key_suffix: ->(id) { id } }
          )
        end
      end.to raise_error(ArgumentError, /Rate limit must be a positive integer/)
    end

    it 'raises error for non-positive rate period' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(
            rate: { limit: 100, period: 0, key_suffix: ->(id) { id } }
          )
        end
      end.to raise_error(ArgumentError, /Rate period must be a positive integer/)
    end

    it 'raises error for missing rate key_suffix' do
      expect do
        create_test_job_class('InvalidJob') do
          sidekiq_throttle(rate: { limit: 100, period: 60 })
        end
      end.to raise_error(ArgumentError, /Rate key_suffix is required/)
    end

    it 'accepts valid concurrency config' do
      expect do
        create_test_job_class('ValidJob') do
          sidekiq_throttle(
            concurrency: {
              limit: 10,
              key_suffix: ->(user_id) { user_id }
            }
          )
        end
      end.not_to raise_error
    end

    it 'accepts valid rate config' do
      expect do
        create_test_job_class('ValidJob') do
          sidekiq_throttle(
            rate: {
              limit: 100,
              period: 60,
              key_suffix: ->(api_key) { api_key }
            }
          )
        end
      end.not_to raise_error
    end

    it 'accepts rate config without period' do
      expect do
        create_test_job_class('ValidJob') do
          sidekiq_throttle(
            rate: {
              limit: 100,
              key_suffix: ->(api_key) { api_key }
            }
          )
        end
      end.not_to raise_error
    end
  end

  describe 'integration with Sidekiq::Job' do
    it 'includes Sidekiq::Job methods' do
      job_class = create_test_job_class('IntegrationJob')
      job = job_class.new
      expect(job).to respond_to(:perform)
    end

    it 'allows sidekiq_options' do
      job_class = create_test_job_class('OptionsJob') do
        sidekiq_options queue: :test_queue, retry: 3
      end
      expect(job_class.get_sidekiq_options).to include('queue' => :test_queue, 'retry' => 3)
    end
  end
end
