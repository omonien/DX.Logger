# DX.Logger Configuration Guide

## Overview

This document describes how to securely manage sensitive configuration data (API keys, server URLs) without committing them to the public repository.

## Quick Start

### 1. Create Local Configuration File

```bash
# Copy the example configuration
copy config.example.ini config.local.ini
```

### 2. Enter Your Credentials

Open `config.local.ini` and enter your actual values:

```ini
[Seq]
ServerUrl=https://your-seq-server.example.com
ApiKey=your-api-key-here
BatchSize=10
FlushInterval=2000
```

### 3. Use in Code

**Option A: Set Manually in Code**

```delphi
uses
  DX.Logger,
  DX.Logger.Provider.Seq;

begin
  // Enter your actual values here
  TSeqLogProvider.SetServerUrl('https://your-seq-server.example.com');
  TSeqLogProvider.SetApiKey('your-api-key-here');

  TDXLogger.Instance.RegisterProvider(TSeqLogProvider.Instance);
end;
```

**Option B: Load from INI File (Recommended)**

```delphi
uses
  System.IniFiles,
  DX.Logger,
  DX.Logger.Provider.Seq;

procedure LoadSeqConfig;
var
  LIni: TIniFile;
  LConfigFile: string;
begin
  LConfigFile := ExtractFilePath(ParamStr(0)) + 'config.local.ini';
  
  if not FileExists(LConfigFile) then
  begin
    WriteLn('WARNING: config.local.ini not found!');
    WriteLn('Please copy config.example.ini to config.local.ini and configure it.');
    Exit;
  end;
  
  LIni := TIniFile.Create(LConfigFile);
  try
    TSeqLogProvider.SetServerUrl(LIni.ReadString('Seq', 'ServerUrl', ''));
    TSeqLogProvider.SetApiKey(LIni.ReadString('Seq', 'ApiKey', ''));
    TSeqLogProvider.SetBatchSize(LIni.ReadInteger('Seq', 'BatchSize', 10));
    TSeqLogProvider.SetFlushInterval(LIni.ReadInteger('Seq', 'FlushInterval', 2000));
  finally
    LIni.Free;
  end;
end;

begin
  LoadSeqConfig;
  TDXLogger.Instance.RegisterProvider(TSeqLogProvider.Instance);
end;
```

## Startup & Configuration Window

### Why it exists

Providers such as `TFileLogProvider` and `TSeqLogProvider` register themselves in their unit's `initialization` section and become active immediately — with *default* configuration (e.g. log file `<AppName>.log` next to the executable, 10 MB rotation). Application-specific configuration (`SetLogFileName`, `SetMaxFileSize`, `SetMinLevel`, Seq server URL, …) can run at the earliest in the DPR body, i.e. *after* the first log calls are already possible. Without a mechanism to bridge that gap, early entries can be written to the wrong file, or race a provider that is still being configured.

To close that gap, `TDXLogger` owns a **configuration window** that is open from process start.

### Behavior

| Situation | Default provider | All other registered providers |
|---|---|---|
| Window **open** | writes immediately (current `MinLevel` applies, as today) | receive **nothing**; every entry is appended to the **startup buffer** (unfiltered, all levels) |
| Window **closes** | unchanged | buffered entries are replayed **in original order**, filtered with the `MinLevel` valid *at close time*; buffer is discarded afterwards |
| Window **closed** | unchanged | live dispatch, as today |

The buffer stores entries **unfiltered** (ignoring the `MinLevel` in effect at the time each entry was logged), so a later `SetMinLevel(Trace)` still recovers early trace lines at replay time. The default provider's immediate output keeps honoring the current `MinLevel` throughout, exactly as before.

The buffer has a fixed cap of **10 000 entries**. On overflow the **newest** entries are dropped (the oldest boot lines carry the highest diagnostic value); if any entries were dropped, the replay emits one final `Warn` entry stating how many.

### Closing the window: `TDXLogger.CompleteConfiguration`

```pascal
class procedure TDXLogger.CompleteConfiguration;
```

- Thread-safe and **idempotent** — safe to call from any thread; second and later calls are no-ops.
- Closes the window: replays the buffer (order preserved, filtered with the `MinLevel` valid now) to every registered provider except the platform default one, then discards the buffer.
- Providers registered while the window was open take part in the replay. Providers registered after the close start empty and receive live entries only.

### Recommended DPR layout

Put `DX.Logger` and **all** provider units in the `uses` clause before anything else that might log (only memory managers such as FastMM, which must not depend on DX.Logger, go first) — this makes sure their `initialization` sections (and therefore provider registration) run as early as possible. Configure providers as the first statement(s) after `begin`, then close the window explicitly:

```pascal
program MyApp;

uses
  // Memory managers (FastMM etc.) first — they must not depend on DX.Logger.
  // Then the logger and ALL provider units, before anything else, so their
  // initialization runs as early as possible:
  DX.Logger,
  DX.Logger.Provider.TextFile,
  Vcl.Forms,
  { ... },
  Main.Form in 'Main.Form.pas';

begin
  // Configure providers first, then close the configuration window.
  // Without CompleteConfiguration the window auto-closes after
  // TDXLogger.StartupTimeoutMs (default: 10 s) or at process shutdown —
  // early entries are never lost either way.
  TFileLogProvider.SetLogFileName('LOG\MyApp.log');
  TDXLogger.SetMinLevel(TLogLevel.Trace);
  TDXLogger.CompleteConfiguration;
  Application.Initialize;
  { ... }
end.
```

If a call to `CompleteConfiguration` is omitted entirely, nothing breaks — the window simply closes on its own via the fallback timer described below, or at the latest during process shutdown.

### UI providers

`TUILogProvider` is typically bound to a control (e.g. `TMemo.Lines`) inside a form's `FormCreate`, which usually runs later than the DPR body — well within the default 10-second window. Two supported patterns:

- **Bind and close explicitly**: assign `ExternalStrings` and call `TDXLogger.CompleteConfiguration` in `FormCreate` (or wherever the UI becomes ready), once every other provider is also configured. The memo then shows the buffered boot lines immediately.
- **Rely on the fallback window**: bind `ExternalStrings` without calling `CompleteConfiguration` yourself. As long as `FormCreate` runs before `StartupTimeoutMs` elapses, the memo still receives the full replay when the window auto-closes.

Applications that call `CompleteConfiguration` earlier (e.g. right after `begin`, before any form is created) deliberately opt out of this — a UI provider bound after the window has already closed only ever sees entries logged from that point on.

### `StartupTimeoutMs`

```pascal
class property TDXLogger.StartupTimeoutMs: Cardinal; // default 10000; 0 = no auto-close
```

- Default **10 000 ms**. A single short-lived watchdog thread is armed on the first access to `TDXLogger.Instance` (in practice: the first provider registration in a unit `initialization` section, or the first log call) and waits on an event for this timeout. `CompleteConfiguration` signals the event, so the watchdog exits without action if the window was already closed explicitly. On timeout, the watchdog calls `CompleteConfiguration` itself.
- `StartupTimeoutMs = 0` **disables** the auto-close — the window then stays open until an explicit `CompleteConfiguration` call or the process shutdown flush. Changing the value is only effective while the window is still open.
- Set it as one of the first lines in the DPR, before or instead of an explicit `CompleteConfiguration` call, e.g. `TDXLogger.StartupTimeoutMs := 3000;` for a tighter window, or `:= 0` to require an explicit close.

### Shutdown flush

If the process exits (or the DX.Logger unit finalizes) while the window is still open — a short-lived CLI tool that never calls `CompleteConfiguration` and exits before the timeout, for example — the class destructor closes it as part of teardown: buffered entries are replayed to all registered providers before the providers themselves are freed. Early entries are therefore **never lost**, regardless of how the process ends.

### Notes for custom-provider authors

The mechanism lives entirely in the core — the `ILogProvider` interface and `TAsyncLogProvider` base class are unchanged. A provider you write behaves exactly like the shipped ones: it receives nothing while the window is open, then gets the full replay once `CompleteConfiguration` runs.

One thing to get right, though, because the shutdown flush above depends on it: `TDXLogger` keeps every registered provider alive purely through its `ILogProvider` interface reference (in `FProviders`). If your provider also exposes a class-var singleton (the pattern all shipped providers use — `TFileLogProvider.Instance`, `TSeqLogProvider.Instance`, `TUILogProvider.Instance`), its **class destructor must only `nil` that singleton pointer, never `Free` the object itself**:

```pascal
class destructor TMyProvider.Destroy;
begin
  // During shutdown, just set to nil without freeing.
  // The instance stays alive via the interface reference held by
  // TDXLogger.Instance.FProviders until that reference is released.
  FInstance := nil;
end;
```

Unit finalization order is not guaranteed relative to `DX.Logger`'s own class destructor, so a provider's class destructor may run before or after the core's shutdown flush. Freeing the object directly here would risk a dangling interface reference inside `TDXLogger` at exactly the moment the shutdown flush tries to replay into it. All three shipped providers already follow this pattern.

## Security

### What is NOT Committed to the Repository?

The following files are in `.gitignore` and are **never** committed:

- `config.local.ini` - Your personal configuration
- `*.local.ini` - All local INI files
- `.env.local` - Local environment variables

### What is in the Repository?

- `config.example.ini` - Example configuration with placeholders
- All code examples use generic placeholders

## GitHub Secrets (for CI/CD)

If you want to run automated tests with real credentials:

### 1. Set Secrets in GitHub

1. Go to: **Repository → Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Add:
   - Name: `SEQ_SERVER_URL`, Value: `https://your-seq-server.example.com`
   - Name: `SEQ_API_KEY`, Value: `your-api-key-here`

### 2. Use in GitHub Actions

```yaml
# .github/workflows/test.yml
name: Tests
on: [push]
jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Create config file
        run: |
          echo "[Seq]" > config.local.ini
          echo "ServerUrl=${{ secrets.SEQ_SERVER_URL }}" >> config.local.ini
          echo "ApiKey=${{ secrets.SEQ_API_KEY }}" >> config.local.ini

      - name: Run Tests
        run: |
          # Your tests here
```

## Best Practices

### ✅ DO

- Use `config.local.ini` for local development
- Only commit `config.example.ini` with placeholders
- Document all required configuration parameters
- Use GitHub Secrets for CI/CD

### ❌ DON'T

- Never hardcode real API keys in code
- Never commit `config.local.ini`
- Never put secrets in comments or documentation
- Never put secrets in commit messages

## Troubleshooting

### "config.local.ini not found"

**Problem:** The configuration file does not exist.

**Solution:**
```bash
copy config.example.ini config.local.ini
# Then edit config.local.ini
```

### "Invalid API Key"

**Problem:** The API key is incorrect or expired.

**Solution:** Check your Seq server and generate a new API key if necessary.

## Additional Information

- [Seq Provider Documentation](SEQ_PROVIDER.md)
- [Security Best Practices](../SECURITY.md)
- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

