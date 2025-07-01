# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2024-12-19

### Fixed
- **Critical**: Fixed jobs staying in "running" state when rescheduled due to throttling limits
- **Critical**: Fixed YAML configuration file not being loaded properly from sidekiq.yml
- **Critical**: Fixed configuration not being loaded from Sidekiq's configuration options

### Added
- Automatic configuration loading from multiple sources:
  - Configuration passed as arguments to `configure` method
  - Sidekiq's configuration options (if available)
  - sidekiq.yml file in common locations (config/sidekiq.yml, sidekiq.yml, etc.)
- Enhanced configuration loading with `load_configuration!` method
- Support for Rails-specific sidekiq.yml location detection
- Improved job rescheduling using Sidekiq's proper client mechanism
- Better error handling for job rescheduling to prevent stuck jobs

### Changed
- Updated `Sidekiq::QueueThrottled.configure` to accept configuration arguments
- Improved middleware to properly handle job lifecycle and prevent stuck jobs
- Enhanced configuration loading to prioritize user-provided configuration over defaults
- Updated examples to show the new configuration loading capabilities

### Technical Details
- Jobs are now properly rescheduled using `Sidekiq::Client.new.push` for newer Sidekiq versions
- Configuration loading follows a clear precedence order: arguments > Sidekiq config > YAML file
- Middleware now raises `Sidekiq::Shutdown` exception to properly stop job processing when rescheduling
- Added comprehensive file path detection for sidekiq.yml in Rails and non-Rails environments

## [1.1.3] - 2024-12-19

### Changed
- Re-enabled MFA requirement for RubyGems deployment for enhanced security

## [1.1.2] - 2024-12-19

### Changed
- Disabled MFA requirement for RubyGems deployment to simplify release process

## [Unreleased]

### Added
- Initial release
- Queue-level concurrency limits
- Job-level throttling with concurrency and rate limits
- Redis-based coordination
- Thread-safe implementation
- Comprehensive configuration options
- Middleware integration with Sidekiq
- DSL for job throttling configuration
- Error handling and logging
- Production-ready features

### Features
- Support for queue limits in sidekiq.yml configuration
- Programmatic queue limit configuration
- Concurrency-based job throttling with custom key suffixes
- Rate-based job throttling with time windows
- Automatic job rescheduling when limits are reached
- Redis key management with TTL
- Concurrent access safety with read-write locks
- Comprehensive validation of configuration options

## [1.0.0] - 2024-01-01

### Added
- Initial release of sidekiq-queue-throttled gem
- Queue-level concurrency limiting
- Job-level throttling capabilities
- Redis-based coordination system
- Thread-safe implementation
- Comprehensive configuration system
- Middleware integration
- DSL for job configuration
- Error handling and logging
- Production-ready features

### Technical Details
- Uses Concurrent::ReentrantReadWriteLock for thread safety
- Redis-based counters with TTL for memory management
- Automatic job rescheduling with configurable delays
- Support for both concurrency and rate limiting
- Flexible key suffix resolution (Proc, Symbol, String)
- Comprehensive validation of configuration options
- Integration with Sidekiq's middleware chain 
