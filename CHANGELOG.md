# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-11-18

### Added
- Core logging functionality with multiple log levels (Trace, Debug, Info, Warn, Error)
- Cross-platform support (Windows, macOS, iOS, Android, Linux)
- Platform-specific output mechanisms (Console, OutputDebugString, NSLog, Android Log, syslog)
- File provider with automatic rotation
- Seq provider for structured logging to Seq servers
- Thread-safe logging with queue-based processing
- Extensible provider architecture (ILogProvider interface)
- Configuration management system with `config.local.ini` support
- Comprehensive unit tests using DUnitX (25 tests)
- SeqExample with automatic configuration loading
- GitHub issue and PR templates
- Comprehensive documentation (README, CONTRIBUTING, SECURITY, CHANGELOG)
- Technical documentation (CONFIGURATION.md, SEQ_PROVIDER.md)
- MIT License with SPDX headers

### Features
- Simple API with `DXLog()` function
- Convenience functions for each log level (DXLogTrace, DXLogDebug, DXLogInfo, DXLogWarn, DXLogError)
- Configurable minimum log level
- Singleton pattern for logger instance
- Provider registration/unregistration
- Automatic file rotation based on size
- Asynchronous Seq logging with batching
- CLEF (Compact Log Event Format) support for Seq

### Security
- Implemented secure credential management
- Added `.gitignore` rules for sensitive configuration files (*.local.ini)
- Removed all hardcoded API keys and URLs from codebase
- Configuration template system (config.example.ini)
- Security policy and vulnerability reporting process

[Unreleased]: https://github.com/omonien/DX.Logger/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/omonien/DX.Logger/releases/tag/v1.0.0

