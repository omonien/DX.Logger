# DX.Logger.Provider.Seq

Seq provider for DX.Logger - sends structured log events to a Seq server.

## Overview

The Seq provider enables sending log entries from DX.Logger to a [Seq](https://datalust.co/seq) server. Seq is a modern logging platform for structured log events with powerful search and analysis capabilities.

## Features

- **Asynchronous Logging**: Non-blocking through queue-based processing
- **Automatic Batching**: Collects multiple events and sends them bundled
- **CLEF Format**: Uses Compact Log Event Format (CLEF)
- **Configurable**: Batch size and flush interval adjustable
- **Thread-safe**: Can be used from multiple threads simultaneously
- **Fault Tolerant**: HTTP errors do not block the application

## Installation

1. Add `DX.Logger.Provider.Seq.pas` to your project
2. Add the unit to your `uses` clause:

```delphi
uses
  DX.Logger,
  DX.Logger.Provider.Seq;
```

## Usage

### Basic Configuration

```delphi
// Configure Seq server
TSeqLogProvider.SetServerUrl('https://your-seq-server.example.com');
TSeqLogProvider.SetApiKey('your-api-key-here');

// Register provider
TDXLogger.Instance.RegisterProvider(TSeqLogProvider.Instance);

// Log as usual
DXLog('Application started');
DXLogError('Something went wrong!');
```

> **Note:** See [CONFIGURATION.md](CONFIGURATION.md) for details on configuration with `config.local.ini`.

### Advanced Configuration

```delphi
// Set batch size (default: 10)
TSeqLogProvider.SetBatchSize(20);

// Set flush interval in milliseconds (default: 2000)
TSeqLogProvider.SetFlushInterval(5000);

// Register provider
TDXLogger.Instance.RegisterProvider(TSeqLogProvider.Instance);
```

### Manual Flushing

```delphi
// Send all pending events immediately
TSeqLogProvider.Instance.Flush;
```

## CLEF Format

The provider sends events in CLEF (Compact Log Event Format):

```json
{"@t":"2025-11-18T13:45:30.123Z","@l":"Information","@m":"Application started","ThreadId":1234}
{"@t":"2025-11-18T13:45:31.456Z","@l":"Error","@m":"Something went wrong!","ThreadId":1234}
```

### Field Mapping

| DX.Logger | Seq/CLEF | Description |
|-----------|----------|-------------|
| `TLogLevel.Trace` | `Verbose` | Detailed trace information |
| `TLogLevel.Debug` | `Debug` | Debug information |
| `TLogLevel.Info` | `Information` | Informational messages |
| `TLogLevel.Warn` | `Warning` | Warnings |
| `TLogLevel.Error` | `Error` | Errors |

## Configuration Parameters

### SetServerUrl

Sets the URL of the Seq server (without `/api/events/raw`).

```delphi
TSeqLogProvider.SetServerUrl('https://seq.example.com');
```

### SetApiKey

Sets the API key for authentication with the Seq server.

```delphi
TSeqLogProvider.SetApiKey('your-api-key-here');
```

### SetBatchSize

Specifies after how many events a batch is sent (default: 10).

```delphi
TSeqLogProvider.SetBatchSize(50);  // Sends after 50 events
```

### SetFlushInterval

Sets the maximum interval in milliseconds after which a batch is sent (default: 2000).

```delphi
TSeqLogProvider.SetFlushInterval(1000);  // Sends at most after 1 second
```

## Example

A complete example can be found at `examples/SeqExample/SeqExample.dpr`.

## Technical Details

### Asynchronous Processing

The provider uses a worker thread that:
1. Reads log entries from a thread-safe queue
2. Collects events until `BatchSize` is reached or `FlushInterval` has elapsed
3. Sends bundled events via HTTP POST to Seq

### HTTP Communication

- **Endpoint**: `{ServerUrl}/api/events/raw`
- **Method**: POST
- **Content-Type**: `application/vnd.serilog.clef`
- **Authentication**: `X-Seq-ApiKey` Header
- **Format**: Newline-delimited JSON (CLEF)

### Error Handling

HTTP errors are silently ignored to prevent logging issues from affecting the application. If needed, error handling can be customized in `SendBatch`.

## Performance Tips

1. **Batch Size**: Larger batches reduce HTTP overhead but increase latency
2. **Flush Interval**: Shorter intervals increase timeliness but generate more HTTP requests
3. **Queue Depth**: Default is 1000 events - adjust if needed for very high throughput

## License

MIT License - see main README of the DX.Logger project.

