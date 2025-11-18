# DX.Logger

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
// Generic log function
procedure DXLog(const AMessage: string; ALevel: TLogLevel = TLogLevel.Info);

// Convenience functions for specific levels
procedure DXLogTrace(const AMessage: string);
procedure DXLogDebug(const AMessage: string);
procedure DXLogInfo(const AMessage: string);
procedure DXLogWarn(const AMessage: string);
procedure DXLogError(const AMessage: string);
```

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

## File Provider

The file provider supports:
- Automatic file creation
- Configurable file name
- Automatic file rotation based on size
- Thread-safe file writing
- UTF-8 encoding

### File Provider Configuration

```delphi
// Set custom log file name
TFileLogProvider.SetLogFileName('C:\Logs\myapp.log');

// Set maximum file size before rotation (default: 10 MB)
TFileLogProvider.SetMaxFileSize(5 * 1024 * 1024); // 5 MB
```

When the log file reaches the maximum size, it's automatically renamed with a timestamp and a new file is created.

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

## Examples

See the `examples/SimpleConsole` directory for a complete working example.

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
│   └── DX.Logger.Provider.TextFile.pas   # File logging provider
├── examples/
│   └── SimpleConsole/                    # Console example application
├── tests/
│   ├── DUnitX/                           # DUnitX framework (submodule)
│   ├── DX.Logger.Tests.dpr               # Test project
│   ├── DX.Logger.Tests.Core.pas          # Core logger tests
│   ├── DX.Logger.Tests.FileProvider.pas  # File provider tests
│   └── README.md                         # Test documentation
├── docs/
│   └── Delphi Style Guide EN.md          # Coding standards
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
- Code follows the Delphi Style Guide
- All files use UTF-8 with BOM encoding
- Line endings are CRLF
- Output paths follow the `$(Platform)/$(Config)` pattern

## Support

For issues, questions, or suggestions, please open an issue on GitHub.
