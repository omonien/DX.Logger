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

