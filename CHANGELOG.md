# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Seq provider for structured logging to Seq servers
- Configuration management system with `config.local.ini` support
- Comprehensive security documentation
- SeqExample with automatic configuration loading
- Unit tests for Seq provider
- Security best practices documentation

### Changed
- Improved documentation structure (moved to `docs/` directory)
- Enhanced README with badges and installation instructions

### Security
- Implemented secure credential management
- Added `.gitignore` rules for sensitive configuration files
- Removed all hardcoded API keys and URLs from codebase

## [1.0.0] - 2025-01-XX

### Added
- Core logging functionality with multiple log levels (Trace, Debug, Info, Warn, Error)
- Cross-platform support (Windows, macOS, iOS, Android, Linux)
- Platform-specific output mechanisms
- File provider with automatic rotation
- Thread-safe logging
- Extensible provider architecture
- Comprehensive unit tests using DUnitX
- Delphi Style Guide
- MIT License

### Features
- Simple API with `DXLog()` function
- Convenience functions for each log level
- Configurable minimum log level
- Singleton pattern for logger instance
- Provider registration/unregistration
- Automatic file rotation based on size

[Unreleased]: https://github.com/omonien/DX.Logger/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/omonien/DX.Logger/releases/tag/v1.0.0

