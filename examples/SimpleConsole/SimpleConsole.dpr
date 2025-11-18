program SimpleConsole;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  DX.Logger in '..\..\source\DX.Logger.pas',
  DX.Logger.Provider.TextFile in '..\..\source\DX.Logger.Provider.TextFile.pas';

begin
  try
    WriteLn('DX.Logger Simple Console Example');
    WriteLn('==================================');
    WriteLn;

    // Configure file provider
    TFileLogProvider.SetLogFileName('SimpleConsole.log');

    // Simple logging examples
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
    WriteLn('3. File: SimpleConsole.log');
    WriteLn;

    // Example with different log levels
    DXLog('Processing started...', TLogLevel.Info);
    DXLog('Step 1 completed', TLogLevel.Debug);
    DXLog('Step 2 completed', TLogLevel.Debug);
    DXLog('Warning: Low memory', TLogLevel.Warn);
    DXLog('Processing completed', TLogLevel.Info);

    WriteLn;
    WriteLn('Press ENTER to exit...');
    ReadLn;

    DXLog('Application stopped');
  except
    on E: Exception do begin
      DXLogError('Exception: ' + E.ClassName + ': ' + E.Message);
      Writeln(E.ClassName, ': ', E.Message);
    end;
  end;
end.
