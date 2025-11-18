unit DX.Logger.Tests.FileProvider;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  DX.Logger,
  DX.Logger.Provider.TextFile;

type
  [TestFixture]
  TFileLogProviderTests = class
  private
    FTestLogFile: string;
    FTestDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestFileCreation;
    [Test]
    procedure TestLogToFile;
    [Test]
    procedure TestFileRotation;
    [Test]
    procedure TestCustomFileName;
    [Test]
    procedure TestDirectoryCreation;
    [Test]
    procedure TestThreadSafety;
  end;

implementation

uses
  System.Threading,
  Winapi.Windows;

{ TFileLogProviderTests }

procedure TFileLogProviderTests.Setup;
begin
  // Close any open log file from previous tests
  TFileLogProvider.Instance.Close;

  FTestDir := TPath.Combine(TPath.GetTempPath, 'DXLoggerTests');
  FTestLogFile := TPath.Combine(FTestDir, 'test.log');

  // Clean up any existing test files
  if TDirectory.Exists(FTestDir) then
  begin
    Sleep(100); // Give file handles time to close
    try
      TDirectory.Delete(FTestDir, True);
    except
      // Ignore cleanup errors
    end;
  end;

  TDirectory.CreateDirectory(FTestDir);

  // Set minimum log level
  TDXLogger.SetMinLevel(TLogLevel.Trace);
end;

procedure TFileLogProviderTests.TearDown;
begin
  // Close the log file to release file handles
  TFileLogProvider.Instance.Close;

  // Clean up test files
  if TDirectory.Exists(FTestDir) then
  begin
    Sleep(100); // Give file handles time to close
    try
      TDirectory.Delete(FTestDir, True);
    except
      // Ignore cleanup errors
    end;
  end;
end;

procedure TFileLogProviderTests.TestFileCreation;
var
  LEntry: TLogEntry;
begin
  TFileLogProvider.SetLogFileName(FTestLogFile);

  // Create a valid log entry
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'Test';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  TFileLogProvider.Instance.Log(LEntry);
  Sleep(50); // Give it time to write
  Assert.IsTrue(TFile.Exists(FTestLogFile), 'Log file should be created');
end;

procedure TFileLogProviderTests.TestLogToFile;
var
  LEntry: TLogEntry;
  LContent: string;
begin
  TFileLogProvider.SetLogFileName(FTestLogFile);

  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'Test message';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  TFileLogProvider.Instance.Log(LEntry);

  // Close the file before reading it
  TFileLogProvider.Instance.Close;

  Assert.IsTrue(TFile.Exists(FTestLogFile), 'Log file should exist');
  LContent := TFile.ReadAllText(FTestLogFile);
  Assert.Contains(LContent, 'Test message', 'Log file should contain the message');
  Assert.Contains(LContent, 'INFO', 'Log file should contain log level');
end;

procedure TFileLogProviderTests.TestFileRotation;
var
  LEntry: TLogEntry;
  i: Integer;
  LFiles: TArray<string>;
begin
  TFileLogProvider.SetLogFileName(FTestLogFile);
  TFileLogProvider.SetMaxFileSize(1024); // 1 KB for testing

  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  // Write enough messages to trigger rotation
  for i := 1 to 100 do
  begin
    LEntry.Message := StringOfChar('X', 50); // 50 chars per message
    TFileLogProvider.Instance.Log(LEntry);
  end;

  // Wait for file operations
  Sleep(200);

  // Check if rotation occurred
  LFiles := TDirectory.GetFiles(FTestDir, '*.log');
  Assert.IsTrue(Length(LFiles) > 1, 'File rotation should create backup files');
end;

procedure TFileLogProviderTests.TestCustomFileName;
var
  LCustomFile: string;
  LEntry: TLogEntry;
begin
  LCustomFile := TPath.Combine(FTestDir, 'custom.log');
  TFileLogProvider.SetLogFileName(LCustomFile);

  // Create a valid log entry
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'Test';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  TFileLogProvider.Instance.Log(LEntry);
  Sleep(50); // Give it time to write
  Assert.IsTrue(TFile.Exists(LCustomFile), 'Custom log file should be created');
end;

procedure TFileLogProviderTests.TestDirectoryCreation;
var
  LSubDir: string;
  LFileInSubDir: string;
  LEntry: TLogEntry;
begin
  LSubDir := TPath.Combine(FTestDir, 'subdir');
  LFileInSubDir := TPath.Combine(LSubDir, 'test.log');

  TFileLogProvider.SetLogFileName(LFileInSubDir);

  // Create a valid log entry
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'Test';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  TFileLogProvider.Instance.Log(LEntry);
  Sleep(50); // Give it time to write

  Assert.IsTrue(TDirectory.Exists(LSubDir), 'Subdirectory should be created');
  Assert.IsTrue(TFile.Exists(LFileInSubDir), 'Log file in subdirectory should be created');
end;

procedure TFileLogProviderTests.TestThreadSafety;
var
  LThreadCount: Integer;
  LMessagesPerThread: Integer;
  LContent: string;
  LLineCount: Integer;
  LExpectedCount: Integer;
  LThreads: array of TThread;
  i: Integer;
begin
  TFileLogProvider.SetLogFileName(FTestLogFile);
  // Set a very large max file size to prevent rotation during this test
  TFileLogProvider.SetMaxFileSize(100 * 1024 * 1024); // 100 MB

  LThreadCount := 10;
  LMessagesPerThread := 50;
  LExpectedCount := LThreadCount * LMessagesPerThread;

  SetLength(LThreads, LThreadCount);

  // Create and start all threads
  for i := 0 to LThreadCount - 1 do
  begin
    LThreads[i] := TThread.CreateAnonymousThread(
      procedure
      var
        j: Integer;
        LEntry: TLogEntry;
        LThreadIndex: Integer;
      begin
        LThreadIndex := i + 1; // Capture thread index
        for j := 1 to LMessagesPerThread do
        begin
          LEntry.Timestamp := Now;
          LEntry.Level := TLogLevel.Info;
          LEntry.Message := Format('Thread %d Message %d', [LThreadIndex, j]);
          LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
          TFileLogProvider.Instance.Log(LEntry);
        end;
      end);
    LThreads[i].FreeOnTerminate := False;
    LThreads[i].Start;
  end;

  // Wait for all threads to complete
  for i := 0 to LThreadCount - 1 do
  begin
    LThreads[i].WaitFor;
    LThreads[i].Free;
  end;

  // Close the file before reading it
  TFileLogProvider.Instance.Close;

  Assert.IsTrue(TFile.Exists(FTestLogFile), 'Log file should exist');

  LContent := TFile.ReadAllText(FTestLogFile);

  // Count lines (each log entry is one line)
  LLineCount := 0;
  var LLines := LContent.Split([#13#10, #10]);

  for var LLine in LLines do
  begin
    if not LLine.Trim.IsEmpty then
      Inc(LLineCount);
  end;

  Assert.AreEqual(LExpectedCount, LLineCount,
    'All messages from all threads should be written');
end;

initialization
  TDUnitX.RegisterTestFixture(TFileLogProviderTests);

end.

