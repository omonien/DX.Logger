program DX.Logger.Tests;

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF }
  DUnitX.TestFramework,
  DX.Logger in '..\source\DX.Logger.pas',
  DX.Logger.Provider.TextFile in '..\source\DX.Logger.Provider.TextFile.pas',
  DX.Logger.Tests.Core in 'DX.Logger.Tests.Core.pas',
  DX.Logger.Tests.FileProvider in 'DX.Logger.Tests.FileProvider.pas';

{$IFNDEF TESTINSIGHT}
var
  LRunner: ITestRunner;
  LResults: IRunResults;
  LLogger: ITestLogger;
  LNUnitLogger: ITestLogger;
{$ENDIF}

begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    // Check command line options, will take precedence over environment variables
    TDUnitX.CheckCommandLine;
    
    // Create the test runner
    LRunner := TDUnitX.CreateRunner;
    
    // Tell the runner to use RTTI to find Fixtures
    LRunner.UseRTTI := True;
    
    // When true, Assertions must be made during tests
    LRunner.FailsOnNoAsserts := False;

    // Tell the runner how we will log things
    // Log to the console window if desired
    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      LLogger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      LRunner.AddLogger(LLogger);
    end;
    
    // Generate an NUnit compatible XML File
    LNUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    LRunner.AddLogger(LNUnitLogger);

    // Run tests
    LResults := LRunner.Execute;
    
    if not LResults.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    // We don't want this happening when running under CI.
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ENDIF}
end.

