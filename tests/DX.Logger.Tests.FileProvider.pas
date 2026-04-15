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
  FTestDir := TPath.Combine(TPath.GetTempPath, 'DXLoggerTests');
  FTestLogFile := TPath.Combine(FTestDir, 'test.log');

  // Clean up any existing test files
  if TDirectory.Exists(FTestDir) then
  begin
    Sleep(200); // Give async worker thread time to finish
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
  // Give async worker thread time to finish writing
  Sleep(200);

  // Clean up test files
  if TDirectory.Exists(FTestDir) then
  begin
    Sleep(200); // Give file handles time to close
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
  Sleep(200); // Give async worker thread time to write
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

  // Give async worker thread time to write
  Sleep(200);

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
  Sleep(200); // Give async worker thread time to write
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
  Sleep(200); // Give async worker thread time to write

  Assert.IsTrue(TDirectory.Exists(LSubDir), 'Subdirectory should be created');
  Assert.IsTrue(TFile.Exists(LFileInSubDir), 'Log file in subdirectory should be created');
end;

type
  TLoggingWorker = class(TThread)
  public
    WorkerIndex: Integer;            // public fields, set after construction
    WorkerMessagesPerThread: Integer; // before Start — race-free.
  protected
    procedure Execute; override;
  end;

procedure TLoggingWorker.Execute;
var
  j: Integer;
  LEntry: TLogEntry;
begin
  for j := 1 to WorkerMessagesPerThread do
  begin
    LEntry.Timestamp := Now;
    LEntry.Level := TLogLevel.Info;
    LEntry.Message := Format('Thread %d Message %d', [WorkerIndex + 1, j]);
    LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
    TFileLogProvider.Instance.Log(LEntry);
  end;
end;

procedure TFileLogProviderTests.TestThreadSafety;
var
  LThreadCount: Integer;
  LMessagesPerThread: Integer;
  LContent: string;
  LLineCount: Integer;
  LExpectedCount: Integer;
  LThreads: array of TThread;
  LWorker: TLoggingWorker;
  i: Integer;
begin
  TFileLogProvider.SetLogFileName(FTestLogFile);
  // Set a very large max file size to prevent rotation during this test
  TFileLogProvider.SetMaxFileSize(100 * 1024 * 1024); // 100 MB

  // Drain the async worker so leftovers from a previous test cannot leak
  // into our line count, and start with a fresh empty file.
  TFileLogProvider.Instance.Flush;
  if TFile.Exists(FTestLogFile) then
    TFile.Delete(FTestLogFile);

  LThreadCount := 10;
  LMessagesPerThread := 50;
  LExpectedCount := LThreadCount * LMessagesPerThread;

  SetLength(LThreads, LThreadCount);

  // Use a dedicated TThread subclass to carry the per-worker index as a
  // proper field. Closures over the for-loop variable capture by reference
  // in Delphi and would cause every worker to read the same (post-loop)
  // index — which masked as a "logger loses entries" bug before.
  for i := 0 to LThreadCount - 1 do
  begin
    LWorker := TLoggingWorker.Create(True); // suspended, default ctor
    LWorker.WorkerIndex := i;
    LWorker.WorkerMessagesPerThread := LMessagesPerThread;
    LWorker.FreeOnTerminate := False;
    LThreads[i] := LWorker;
    LWorker.Start;
  end;

  // Wait for all threads to complete
  for i := 0 to LThreadCount - 1 do
  begin
    LThreads[i].WaitFor;
    LThreads[i].Free;
  end;

  // Block until the async worker has drained the queue. The async provider
  // batches writes every 100ms; at 500 entries this can easily exceed the
  // old 500ms Sleep, causing the last batch to still be pending when the
  // assertion runs. Flush waits up to 5 seconds for QueueSize to reach 0.
  TFileLogProvider.Instance.Flush;

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

