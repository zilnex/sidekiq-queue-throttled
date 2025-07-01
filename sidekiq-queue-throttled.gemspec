# frozen_string_literal: true

require_relative 'lib/sidekiq/queue_throttled/version'

Gem::Specification.new do |spec|
  spec.name = 'sidekiq-queue-throttled'
  spec.version = Sidekiq::QueueThrottled::VERSION
  spec.authors = ['Farid Mohammadi']
  spec.email = ['farid.workspace@gmail.com']

  spec.summary = 'Sidekiq gem that combines queue-level limits with job-level throttling'
  spec.description = 'A production-ready Sidekiq gem that provides both queue-level concurrency limits ' \
                     'and job-level throttling capabilities, combining the best of sidekiq-limit_fetch ' \
                     'and sidekiq-throttled.'
  spec.homepage = 'https://github.com/zilnex/sidekiq-queue-throttled'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('{lib,spec}/**/*') + %w[README.md LICENSE.txt CHANGELOG.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'concurrent-ruby', '~> 1.1'
  spec.add_dependency 'redis', '~> 4.0'
  spec.add_dependency 'sidekiq', '~> 6.0'
end
