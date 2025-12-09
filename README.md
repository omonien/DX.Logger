# DX.Logger

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Delphi Versions](https://img.shields.io/badge/Delphi-10.3%2B-blue.svg)](https://www.embarcadero.com/products/delphi)
[![Platforms](https://img.shields.io/badge/Platforms-Win%20%7C%20macOS%20%7C%20iOS%20%7C%20Android%20%7C%20Linux-lightgrey.svg)](https://github.com/omonien/DX.Logger)

A minimalistic, cross-platform logging library for Delphi with a simple API and extensible provider architecture.

## Features

- **Simple API**: Just add `DX.Logger` to your uses clause and call `DXLog()`
- **Multiple Log Levels**: Trace, Debug, Info, Warn, Error
- **Cross-Platform**: Supports Windows, macOS, iOS, Android, and Linux
- **Platform-Specific Output**:
  - Console applications: `WriteLn`
  - Windows: `OutputDebugString`
  - iOS/macOS: `NSLog`
  - Android: Android system log
  - Linux: `syslog`
- **Provider Architecture**: Easily extend with custom log targets
- **Thread-Safe**: Safe for use in multi-threaded applications
- **Single-Unit Core**: Minimal dependencies

## Installation

### Option 1: Manual Installation

1. Clone or download this repository
2. Add the `source` directory to your Delphi library path
3. Add `DX.Logger` to your uses clause

### Option 2: Git Submodule

```bash
git submodule add https://github.com/omonien/DX.Logger.git libs/DX.Logger
```

Then add `libs/DX.Logger/source` to your library path.

## Quick Start

### Basic Usage

```delphi
uses
  DX.Logger;

begin
  DXLog('Hello World');                    // Info level
  DXLog('Debug message', TLogLevel.Debug); // Debug level
  DXLogError('Something went wrong!');     // Error level
end.
```

### With File Logging

```delphi
uses
  DX.Logger,
  DX.Logger.Provider.TextFile;  // Automatically adds file logging

begin
  // Optional: Configure file provider
  TFileLogProvider.SetLogFileName('myapp.log');
  TFileLogProvider.SetMaxFileSize(10 * 1024 * 1024); // 10 MB

  DXLog('Application started');
  // ... your code
  DXLog('Application stopped');
end.
```

## API Reference

### Log Functions

```delphi
// Generic log function with optional details
procedure DXLog(const AMessage: string; ALevel: TLogLevel = TLogLevel.Info; const ADetails: string = '');

// Convenience functions for specific levels
procedure DXLogTrace(const AMessage: string);
procedure DXLogDebug(const AMessage: string);
procedure DXLogInfo(const AMessage: string);
procedure DXLogWarn(const AMessage: string);
procedure DXLogError(const AMessage: string);
```

**Details Parameter**: The optional `ADetails` parameter allows you to provide additional context or supplementary information with your log entry. Each provider handles details according to its format and requirements (see [Provider-Specific Details Handling](#provider-specific-details-handling) below).

### Log Levels

```delphi
type
  TLogLevel = (
    Trace,   // Detailed diagnostic information
    Debug,   // Debugging information
    Info,    // General informational messages
    Warn,    // Warning messages
    Error    // Error messages
  );
```

### Configuration

```delphi
// Set minimum log level (messages below this level are ignored)
TDXLogger.SetMinLevel(TLogLevel.Info);
```

### Provider-Specific Details Handling

The `Details` parameter in log functions provides additional contextual information. Each provider handles this data according to its format and purpose:

- **File Provider**: Writes details as a separate TRACE-level line immediately after the main log entry, preserving all content
- **UI Provider**: Writes details as a separate TRACE-level line, but truncates to 50 characters with a continuation message (`"... [see log file for details]"`) to prevent UI overflow
- **Seq Provider**: Includes details as a structured property in the CLEF (Compact Log Event Format) JSON payload, making it searchable and queryable in Seq

This design allows each provider to optimize details handling for its specific use case while maintaining a consistent API.

## Providers

### File Provider

The file provider supports:
- Automatic file creation
- Configurable file name
- Automatic file rotation based on size
- Thread-safe file writing
- UTF-8 encoding

**Configuration:**

```delphi
uses
  DX.Logger,
  DX.Logger.Provider.TextFile;

// Set custom log file name
TFileLogProvider.SetLogFileName('C:\Logs\myapp.log');

// Set maximum file size before rotation (default: 10 MB)
TFileLogProvider.SetMaxFileSize(5 * 1024 * 1024); // 5 MB

// Register provider
TDXLogger.Instance.RegisterProvider(TFileLogProvider.Instance);
```

When the log file reaches the maximum size, it's automatically renamed with a timestamp and a new file is created.

### Seq Provider

The Seq provider sends structured log events to a [Seq](https://datalust.co/seq) server using the CLEF (Compact Log Event Format).

Features:
- Asynchronous, non-blocking logging
- Automatic batching of events
- Configurable batch size and flush interval
- Thread-safe operation

**Configuration:**

```delphi
uses
  DX.Logger,
  DX.Logger.Provider.Seq;

// Configure Seq server
TSeqLogProvider.SetServerUrl('https://your-seq-server.example.com');
TSeqLogProvider.SetApiKey('your-api-key-here');

// Optional: Configure batching
TSeqLogProvider.SetBatchSize(20);        // Default: 10
TSeqLogProvider.SetFlushInterval(5000);  // Default: 2000 ms

// Register provider
TDXLogger.Instance.RegisterProvider(TSeqLogProvider.Instance);

// Use logging as normal
DXLog('Application started');

// Manually flush if needed
TSeqLogProvider.Instance.Flush;
```

> **Important:** Never commit real API keys! See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for secure credential management.

See [docs/SEQ_PROVIDER.md](docs/SEQ_PROVIDER.md) for detailed documentation.

### UI Provider

The UI provider enables logging to visual controls like `TMemo.Lines` or any `TStrings`-based component.

Features:
- Thread-safe UI updates via `TThread.Synchronize`
- Automatic batching for better performance
- Configurable insert position (top or bottom)
- Details truncation to prevent UI overflow

**Configuration:**

```delphi
uses
  DX.Logger,
  DX.Logger.Provider.UI;

// Register UI provider with TMemo.Lines
TUILogProvider.Instance.ExternalStrings := MemoInfo.Lines;
TUILogProvider.Instance.AppendOnTop := False;  // False = append at bottom (default)
TDXLogger.Instance.RegisterProvider(TUILogProvider.Instance);

// Use logging as normal
DXLog('Application started');
DXLog('Processing item', TLogLevel.Info, 'Large JSON payload here...');

// Unregister when form closes
TUILogProvider.Instance.ExternalStrings := nil;
```

**Details Handling**: When log entries include details, the UI provider writes them as a separate TRACE-level line. To prevent UI overflow with large details (e.g., JSON payloads, stack traces), details are truncated to 50 characters with a continuation message: `"... [see log file for details]"`. This keeps the UI readable while preserving full details in file logs.

## Creating Custom Providers

You can create custom log providers by implementing the `ILogProvider` interface:

```delphi
type
  TMyCustomProvider = class(TInterfacedObject, ILogProvider)
  public
    procedure Log(const AEntry: TLogEntry);
  end;

procedure TMyCustomProvider.Log(const AEntry: TLogEntry);
begin
  // Your custom logging logic here
  // AEntry contains: Timestamp, Level, Message, ThreadID
end;

// Register your provider
TDXLogger.Instance.RegisterProvider(TMyCustomProvider.Create);
```

## Platform-Specific Behavior

### Windows
- Console apps: Messages appear in console window
- GUI apps: Messages sent to `OutputDebugString` (visible in DebugView or IDE)
- File provider available

### macOS
- Uses `NSLog` for system logging
- Messages appear in Console.app
- File provider available

### iOS
- Uses `NSLog` for system logging
- Messages appear in Xcode console
- File provider available

### Android
- Uses Android system log (`__android_log_write`)
- Messages visible via `adb logcat`
- Tag: "DXLogger"
- File provider available

### Linux
- Uses `syslog` for system logging
- Messages appear in system logs
- File provider available

## Configuration & Security

For information on securely managing API keys and sensitive configuration:
- See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for local development setup
- See [SECURITY.md](SECURITY.md) for security best practices
- See [docs/SEQ_PROVIDER.md](docs/SEQ_PROVIDER.md) for Seq-specific configuration

## Examples

### Available Examples

- **[SimpleConsole](examples/SimpleConsole/)** - Basic console logging example
- **[SeqExample](examples/SeqExample/)** - Seq provider example with configuration management

Each example includes its own README with setup instructions.

## Testing

The project includes comprehensive unit tests using DUnitX. See `tests/README.md` for details.

To run tests:
```cmd
cd tests
dcc32 DX.Logger.Tests.dpr
DX.Logger.Tests.exe
```

## Requirements

- Delphi 10.3 or later (for inline variables)
- Supported platforms: Windows, macOS, iOS, Android, Linux

## Project Structure

```
DX.Logger/
├── source/
│   ├── DX.Logger.pas                     # Core logger unit
│   ├── DX.Logger.Provider.TextFile.pas   # File logging provider
│   ├── DX.Logger.Provider.Seq.pas        # Seq logging provider
│   └── DX.Logger.Provider.UI.pas         # UI logging provider
├── examples/
│   ├── SimpleConsole/                    # Console example application
│   └── SeqExample/                       # Seq provider example
├── tests/
│   ├── DUnitX/                           # DUnitX framework (submodule)
│   ├── DX.Logger.Tests.dpr               # Test project
│   ├── DX.Logger.Tests.Core.pas          # Core logger tests
│   ├── DX.Logger.Tests.FileProvider.pas  # File provider tests
│   ├── DX.Logger.Tests.SeqProvider.pas   # Seq provider tests
│   └── README.md                         # Test documentation
├── docs/
│   ├── Delphi Style Guide EN.md          # Coding standards
│   ├── SEQ_PROVIDER.md                   # Seq provider documentation
│   └── CONFIGURATION.md                  # Configuration guide
├── config.example.ini                    # Example configuration (safe to commit)
└── README.md
```

## Coding Standards

This project follows the Delphi Style Guide available in `docs/Delphi Style Guide EN.md`.

Key conventions:
- Local variables: `L` prefix (e.g., `LMessage`)
- Fields: `F` prefix (e.g., `FProviders`)
- Parameters: `A` prefix (e.g., `AMessage`)
- Constants: `c` prefix (e.g., `cMaxSize`)
- 2 spaces indentation
- UTF-8 with BOM encoding
- CRLF line endings

## License

MIT License

Copyright (c) 2025 Olaf Monien

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Contributing

Contributions are welcome! Please ensure:
- Code follows the [Delphi Style Guide](docs/Delphi%20Style%20Guide%20EN.md)
- All files use UTF-8 with BOM encoding
- Line endings are CRLF
- Output paths follow the `$(Platform)/$(Config)` pattern
- Add tests for new features
- Update documentation as needed

### How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Support

- **Issues**: For bugs and feature requests, please [open an issue](https://github.com/omonien/DX.Logger/issues)
- **Discussions**: For questions and general discussion, use [GitHub Discussions](https://github.com/omonien/DX.Logger/discussions)
- **Security**: For security vulnerabilities, see [SECURITY.md](SECURITY.md)

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a list of changes in each version.

## Acknowledgments

- Built with [Delphi](https://www.embarcadero.com/products/delphi)
- Testing framework: [DUnitX](https://github.com/VSoftTechnologies/DUnitX)
- Inspired by modern logging libraries across various platforms
