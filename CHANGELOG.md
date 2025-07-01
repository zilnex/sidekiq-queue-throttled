# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
