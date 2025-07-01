# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rails Integration' do
  describe 'when Rails is available' do
    before do
      # Mock Rails to simulate Rails environment
      stub_const('Rails', double('Rails'))
      stub_const('Rails::Railtie', Class.new)

      # Reload the main file to trigger Rails detection
      load File.expand_path('../../lib/sidekiq/queue_throttled.rb', __dir__)
    end

    it 'defines the Sidekiq::QueueThrottled module' do
      expect(defined?(Sidekiq::QueueThrottled)).to be_truthy
    end

    it 'defines the Sidekiq::QueueThrottled::Job module' do
      expect(defined?(Sidekiq::QueueThrottled::Job)).to be_truthy
    end

    it 'defines the Railtie class' do
      expect(defined?(Sidekiq::QueueThrottled::Railtie)).to be_truthy
    end
  end

  describe 'when Rails is not available' do
    before do
      # Remove Rails constants to simulate non-Rails environment
      Object.send(:remove_const, 'Rails') if defined?(Rails)

      # Reload the main file to trigger Rails detection
      load File.expand_path('../../lib/sidekiq/queue_throttled.rb', __dir__)
    end

    it 'still defines the Sidekiq::QueueThrottled module' do
      expect(defined?(Sidekiq::QueueThrottled)).to be_truthy
    end

    it 'still defines the Sidekiq::QueueThrottled::Job module' do
      expect(defined?(Sidekiq::QueueThrottled::Job)).to be_truthy
    end
  end
end
