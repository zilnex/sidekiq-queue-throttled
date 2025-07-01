# frozen_string_literal: true

require 'rails'

module Sidekiq
  module QueueThrottled
    class Railtie < ::Rails::Railtie
      initializer 'sidekiq.queue_throttled' do
        require 'sidekiq/queue_throttled'
      end
    end
  end
end
