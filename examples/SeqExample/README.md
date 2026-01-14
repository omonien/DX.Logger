# Seq Provider Example

This example demonstrates how to use the DX.Logger Seq provider to send log messages to a [Seq](https://datalust.co/seq) server.

## Prerequisites

- A running Seq server
- A valid Seq API key

## Setup

### 1. Configure Your Credentials

Copy the example configuration file and add your credentials:

```bash
copy config.example.ini config.local.ini
```

Then edit `config.local.ini` and replace the placeholder values with your actual Seq server URL and API key:

```ini
[Seq]
ServerUrl=https://your-seq-server.example.com
ApiKey=your-api-key-here
BatchSize=5
FlushInterval=1000
```

> **Important:** The `config.local.ini` file is ignored by Git and will never be committed to the repository.

### 2. Build and Run

```bash
dcc32 SeqExample.dpr
SeqExample.exe
```

Or open `SeqExample.dproj` in Delphi IDE and run it.

## What It Does

The example demonstrates:

1. **Loading configuration** from `config.local.ini`
2. **Configuring the Seq provider** with server URL, API key, batch size, and flush interval
3. **Registering the provider** with DX.Logger (automatically validates the connection)
4. **Logging messages** at different log levels (Trace, Debug, Info, Warn, Error)
5. **Manual flushing** to ensure all messages are sent

## Expected Output

```
DX.Logger Seq Provider Example
================================

Configuring Seq provider...
Loading configuration from: Y:\DX.Logger\examples\SeqExample\Win32\Debug\config.local.ini
Configuration loaded successfully.
Registering Seq provider (connection will be validated automatically)...
Seq provider registered.

Sending log messages to Seq...

All messages have been logged to:
1. Console (WriteLn)
2. Windows: OutputDebugString
3. Seq: (your configured server)

Flushing remaining messages...
Done! Check your Seq server for the logged messages.

Press ENTER to exit...
```

## Troubleshooting

### "config.local.ini not found"

**Solution:** Copy `config.example.ini` to `config.local.ini` and configure it with your credentials.

### "WARNING: ServerUrl or ApiKey missing"

**Solution:** Make sure both `ServerUrl` and `ApiKey` are set in your `config.local.ini` file.

### Messages not appearing in Seq

**Possible causes:**
- Invalid API key
- Incorrect server URL
- Network connectivity issues
- Firewall blocking the connection

Check the Seq server logs for more information.

### Connection Validation Errors

The `ValidateConnection` method provides detailed error messages:

| Error Message | Cause | Solution |
|--------------|-------|----------|
| "Server URL is not configured" | URL is empty | Set the ServerUrl in config.local.ini |
| "authentication failed (401/403)" | Invalid or missing API key | Check your API key in Seq and config.local.ini |
| "API endpoint not found (404)" | Wrong URL or Seq not installed | Verify the server URL is correct |
| "Network error: ..." | Server unreachable | Check network, firewall, and that Seq is running |
| "Connection timeout" | Server too slow or unreachable | Check network connectivity and server load |

## See Also

- [Seq Provider Documentation](../../docs/SEQ_PROVIDER.md)
- [Configuration Guide](../../docs/CONFIGURATION.md)
- [Security Best Practices](../../docs/SECURITY.md)

