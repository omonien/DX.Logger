# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`TLogEntry.MemoryInfo`**: new optional free-form string field. When a host registers `TDXLogger.Instance.MemoryInfoCallback`, every log entry carries a short memory snapshot (e.g. `"WS:45MB PB:22MB"`). Standard providers render it between `[Thread:N]` and the message; the Seq provider exposes it as a structured `MemoryInfo` field so it can be filtered and charted.
- **`DX.Logger.MemoryInfo`**: new ready-to-use cross-platform unit. `EnableMemoryInfo` installs the callback with a cached `TProcessMemoryMonitor` (default 500 ms). Implementations: Windows (`GetProcessMemoryInfo`), macOS/iOS (`task_info`), Linux/Android (`/proc/self/status`). Unsupported platforms fall back to an empty snapshot so logging keeps running.
- **Thread-ID in UI provider**: `TUILogProvider` now renders `[Thread:N]` just like the File and Seq providers. Previously the UI line omitted the thread-id, which made parallel work hard to follow in live log views.
- **Thread-ID in default provider**: `TDefaultLogProvider` (`OutputDebugString` / `WriteLn` / `NSLog` / `syslog` / Android log) now also renders `[Thread:N]` for consistency across all outputs.

### Changed
- Log line format across all standard providers is now consistent:
  `[timestamp] [LEVEL] [Thread:N]` optionally followed by `[MemoryInfo]`, then the message. Any custom provider that formatted entries itself (via `AEntry.Message`) keeps working unchanged.

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

