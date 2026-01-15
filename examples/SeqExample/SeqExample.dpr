program SeqExample;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IniFiles,
  DX.Logger in '..\..\source\DX.Logger.pas',
  DX.Logger.Provider.Async in '..\..\source\DX.Logger.Provider.Async.pas',
  DX.Logger.Provider.Seq in '..\..\source\DX.Logger.Provider.Seq.pas',
  DX.Logger.Provider.TextFile in '..\..\source\DX.Logger.Provider.TextFile.pas';

procedure LoadConfigFromIni;
var
  LIni: TIniFile;
  LConfigFile: string;
  LServerUrl: string;
  LApiKey: string;
begin
  // Try to load config.local.ini from the same directory as the executable
  LConfigFile := ExtractFilePath(ParamStr(0)) + 'config.local.ini';

  if FileExists(LConfigFile) then
  begin
    WriteLn('Loading configuration from: ', LConfigFile);
    LIni := TIniFile.Create(LConfigFile);
    try
      LServerUrl := LIni.ReadString('Seq', 'ServerUrl', '');
      LApiKey := LIni.ReadString('Seq', 'ApiKey', '');

      if (LServerUrl <> '') and (LApiKey <> '') then
      begin
        TSeqLogProvider.SetServerUrl(LServerUrl);
        TSeqLogProvider.SetApiKey(LApiKey);
        TSeqLogProvider.SetBatchSize(LIni.ReadInteger('Seq', 'BatchSize', 5));
        TSeqLogProvider.SetFlushInterval(LIni.ReadInteger('Seq', 'FlushInterval', 1000));
        WriteLn('Configuration loaded successfully.');
      end
      else
      begin
        WriteLn('WARNING: ServerUrl or ApiKey missing in config.local.ini');
        WriteLn('Using placeholder values (logging will not work).');
      end;
    finally
      LIni.Free;
    end;
  end
  else
  begin
    WriteLn('WARNING: config.local.ini not found at: ', LConfigFile);
    WriteLn('Using placeholder values (logging will not work).');
    WriteLn;
    WriteLn('Please create config.local.ini with the following structure:');
    WriteLn;
    WriteLn('  [Seq]');
    WriteLn('  ServerUrl=https://your-seq-server.example.com');
    WriteLn('  ApiKey=your-api-key-here');
    WriteLn('  BatchSize=5');
    WriteLn('  FlushInterval=1000');
    WriteLn;
    // Use placeholder values
    TSeqLogProvider.SetServerUrl('https://your-seq-server.example.com');
    TSeqLogProvider.SetApiKey('your-api-key-here');
    TSeqLogProvider.SetBatchSize(5);
    TSeqLogProvider.SetFlushInterval(1000);
  end;
end;

begin
  try
    WriteLn('DX.Logger Seq Provider Example');
    WriteLn('================================');
    WriteLn;

    // Configure Seq provider from config.local.ini
    WriteLn('Configuring Seq provider...');
    LoadConfigFromIni;

    // Register Seq provider - this automatically calls ValidateConnection
    // because TSeqLogProvider implements ILogProviderValidation
    WriteLn('Registering Seq provider (connection will be validated automatically)...');
    TDXLogger.Instance.RegisterProvider(TSeqLogProvider.Instance);
    WriteLn('Seq provider registered.');
    WriteLn;

    // Optional: You can also call ValidateConnection manually if needed,
    // e.g., to re-validate after configuration changes or for testing:
    //
    // if not TSeqLogProvider.ValidateConnection then
    //   WriteLn('WARNING: Seq connection validation failed!');

    // Simple logging examples
    WriteLn('Sending log messages to Seq...');
    DXLog('Application started');

    DXLogTrace('This is a trace message');
    DXLogDebug('This is a debug message');
    DXLogInfo('This is an info message');
    DXLogWarn('This is a warning message');
    DXLogError('This is an error message');

    WriteLn;
    WriteLn('All messages have been logged to:');
    WriteLn('1. Console (WriteLn)');
    WriteLn('2. Windows: OutputDebugString');
    WriteLn('3. Seq: (your configured server)');
    WriteLn;

    // Example with different log levels
    DXLog('Processing started...', TLogLevel.Info);
    DXLog('Step 1 completed', TLogLevel.Debug);
    DXLog('Step 2 completed', TLogLevel.Debug);
    DXLog('Warning: Low memory', TLogLevel.Warn);
    DXLog('Processing completed', TLogLevel.Info);

    WriteLn;
    WriteLn('Flushing remaining messages...');
    TSeqLogProvider.Instance.Flush;

    WriteLn('Done! Check your Seq server for the logged messages.');
    WriteLn;
    WriteLn('Press ENTER to exit...');
    ReadLn;

    DXLog('Application stopped');

    // Give worker thread time to send final messages
    Sleep(500);
  except
    on E: Exception do begin
      DXLogError('Exception: ' + E.ClassName + ': ' + E.Message);
      Writeln(E.ClassName, ': ', E.Message);
    end;
  end;
end.

