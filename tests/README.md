# DX.Logger Tests

Unit tests for the DX.Logger library using DUnitX.

## Running Tests

### From Delphi IDE

1. Open `DX.Logger.Tests.dproj` in Delphi
2. Build and run the project (F9)
3. Test results will be displayed in the console

### From Command Line

```cmd
cd tests
dcc32 DX.Logger.Tests.dpr
DX.Logger.Tests.exe
```

## Test Coverage

### Core Logger Tests (`DX.Logger.Tests.Core.pas`)

- **TestSingletonInstance**: Verifies singleton pattern implementation
- **TestLogLevels**: Tests all log levels (Trace, Debug, Info, Warn, Error)
- **TestMinLogLevel**: Validates minimum log level filtering
- **TestRegisterProvider**: Tests provider registration
- **TestUnregisterProvider**: Tests provider unregistration
- **TestLogEntry**: Validates log entry structure
- **TestConvenienceFunctions**: Tests DXLogTrace, DXLogDebug, etc.
- **TestLogLevelToString**: Tests log level string conversion
- **TestThreadSafety**: Validates thread-safe logging with multiple threads

### File Provider Tests (`DX.Logger.Tests.FileProvider.pas`)

- **TestFileCreation**: Verifies log file is created
- **TestLogToFile**: Tests writing log entries to file
- **TestFileRotation**: Validates automatic file rotation
- **TestCustomFileName**: Tests custom log file names
- **TestDirectoryCreation**: Tests automatic directory creation
- **TestThreadSafety**: Validates thread-safe file writing

## Test Framework

This project uses [DUnitX](https://github.com/VSoftTechnologies/DUnitX), which is included as a Git submodule.

### Initializing DUnitX Submodule

If you cloned the repository without submodules:

```cmd
git submodule update --init --recursive
```

## CI/CD Integration

The tests can be integrated into CI/CD pipelines:

```cmd
DX.Logger.Tests.exe --console=quiet --xml=test-results.xml
```

This will:
- Run all tests in quiet mode
- Generate NUnit-compatible XML output
- Exit with error code if tests fail

## Adding New Tests

1. Create a new test fixture class with `[TestFixture]` attribute
2. Add test methods with `[Test]` attribute
3. Use `[Setup]` and `[TearDown]` for initialization/cleanup
4. Register the fixture in the initialization section:

```delphi
initialization
  TDUnitX.RegisterTestFixture(TYourTestClass);
```

## Mock Provider

The `TMockLogProvider` class in `DX.Logger.Tests.Core.pas` provides a simple in-memory log provider for testing purposes. It captures all log entries and allows inspection of:

- Entry count
- Individual entries
- Last entry

This is useful for verifying that the logger behaves correctly without writing to actual outputs.

