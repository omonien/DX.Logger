unit DX.Logger.Tests.JSONLProvider;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  DX.Logger,
  DX.Logger.Provider.JSONL;

type
  [TestFixture]
  TJSONLLogProviderTests = class
  private
    FTestLogFile: string;
    FTestDir: string;

    function ReadAllLines: TArray<string>;
    function ParseLastObject: TJSONObject;
    function ParseObjectAt(AIndex: Integer): TJSONObject;
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
    procedure TestValidJSONPerLine;
    [Test]
    procedure TestJSONStructure;
    [Test]
    procedure TestCustomFileName;
    [Test]
    procedure TestDirectoryCreation;
    [Test]
    procedure TestFileRotation;
    [Test]
    procedure TestThreadSafety;
    [Test]
    procedure TestMemoryInfoField;
    [Test]
    procedure TestDetailsField;
    [Test]
    procedure TestAppVersionField;
    [Test]
    procedure TestStructuredProperties;
    [Test]
    procedure TestReservedKeysNotOverwritten;
    [Test]
    procedure TestMultipleEntriesMultipleLines;
    [Test]
    procedure TestFlush;
    [Test]
    procedure TestLogLevels;
  end;

implementation

uses
  System.Threading,
  System.DateUtils,
  Winapi.Windows;

{ TJSONLLogProviderTests }

procedure TJSONLLogProviderTests.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath, 'DXLoggerJSONLTests');
  FTestLogFile := TPath.Combine(FTestDir, 'test.jsonl');

  if TDirectory.Exists(FTestDir) then
  begin
    Sleep(200);
    try
      TDirectory.Delete(FTestDir, True);
    except
    end;
  end;

  TDirectory.CreateDirectory(FTestDir);
  TDXLogger.SetMinLevel(TLogLevel.Trace);
end;

procedure TJSONLLogProviderTests.TearDown;
begin
  // Drain any pending writes so files are closed before deletion.
  try
    TJSONLLogProvider.Instance.Flush;
  except
  end;

  Sleep(200);

  if TDirectory.Exists(FTestDir) then
  begin
    Sleep(200);
    try
      TDirectory.Delete(FTestDir, True);
    except
    end;
  end;
end;

function TJSONLLogProviderTests.ReadAllLines: TArray<string>;
var
  LContent: string;
  LRaw: TArray<string>;
  LList: TList<string>;
  LLine: string;
begin
  Result := nil;
  if not TFile.Exists(FTestLogFile) then
    Exit;

  LContent := TFile.ReadAllText(FTestLogFile, TEncoding.UTF8);
  LRaw := LContent.Split([#13#10, #10]);

  LList := TList<string>.Create;
  try
    for LLine in LRaw do
      if not LLine.Trim.IsEmpty then
        LList.Add(LLine.Trim);
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TJSONLLogProviderTests.ParseLastObject: TJSONObject;
var
  LLines: TArray<string>;
begin
  LLines := ReadAllLines;
  Assert.IsTrue(Length(LLines) > 0, 'Expected at least one JSONL line');
  Result := TJSONObject.ParseJSONValue(LLines[High(LLines)]) as TJSONObject;
  Assert.IsNotNull(Result, 'Last line must be valid JSON');
end;

function TJSONLLogProviderTests.ParseObjectAt(AIndex: Integer): TJSONObject;
var
  LLines: TArray<string>;
begin
  LLines := ReadAllLines;
  Assert.IsTrue((AIndex >= 0) and (AIndex < Length(LLines)),
    Format('Line index %d out of range (count=%d)', [AIndex, Length(LLines)]));
  Result := TJSONObject.ParseJSONValue(LLines[AIndex]) as TJSONObject;
  Assert.IsNotNull(Result, Format('Line %d must be valid JSON', [AIndex]));
end;

procedure TJSONLLogProviderTests.TestFileCreation;
var
  LEntry: TLogEntry;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'Test';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  Assert.IsTrue(TFile.Exists(FTestLogFile), 'JSONL log file should be created');
end;

procedure TJSONLLogProviderTests.TestLogToFile;
var
  LEntry: TLogEntry;
  LContent: string;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'Test message from JSONL';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  Assert.IsTrue(TFile.Exists(FTestLogFile), 'Log file should exist');
  LContent := TFile.ReadAllText(FTestLogFile, TEncoding.UTF8);
  Assert.Contains(LContent, 'Test message from JSONL', 'File should contain the message');
  Assert.Contains(LContent, '"level":"INFO"', 'File should contain the level');
end;

procedure TJSONLLogProviderTests.TestValidJSONPerLine;
var
  LEntry: TLogEntry;
  LLines: TArray<string>;
  LLine: string;
  LJson: TJSONValue;
  i: Integer;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  for i := 1 to 5 do
  begin
    LEntry := Default(TLogEntry);
    LEntry.Timestamp := Now;
    LEntry.Level := TLogLevel.Info;
    LEntry.Message := Format('Message %d', [i]);
    LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
    TJSONLLogProvider.Instance.Log(LEntry);
  end;

  TJSONLLogProvider.Instance.Flush;

  LLines := ReadAllLines;
  Assert.AreEqual(5, Length(LLines), 'Should have exactly 5 non-empty lines');

  for LLine in LLines do
  begin
    LJson := TJSONObject.ParseJSONValue(LLine);
    try
      Assert.IsNotNull(LJson, 'Each line must be valid JSON: ' + LLine);
      Assert.IsTrue(LJson is TJSONObject, 'Each line must be a JSON object');
    finally
      LJson.Free;
    end;
  end;
end;

procedure TJSONLLogProviderTests.TestJSONStructure;
var
  LEntry: TLogEntry;
  LJson: TJSONObject;
  LTimestamp: string;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := EncodeDateTime(2026, 8, 8, 12, 34, 56, 789);
  LEntry.Level := TLogLevel.Warn;
  LEntry.Message := 'structure-check';
  LEntry.ThreadID := 4242;

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  LJson := ParseLastObject;
  try
    Assert.IsNotNull(LJson.GetValue('timestamp'), 'Must have timestamp');
    Assert.IsNotNull(LJson.GetValue('level'), 'Must have level');
    Assert.IsNotNull(LJson.GetValue('message'), 'Must have message');
    Assert.IsNotNull(LJson.GetValue('threadId'), 'Must have threadId');

    Assert.AreEqual('WARN', LJson.GetValue<string>('level'));
    Assert.AreEqual('structure-check', LJson.GetValue<string>('message'));
    Assert.AreEqual(4242, LJson.GetValue<Integer>('threadId'));

    LTimestamp := LJson.GetValue<string>('timestamp');
    // ISO 8601 UTC shape: yyyy-mm-ddThh:nn:ss.zzzZ
    Assert.IsTrue(LTimestamp.Contains('T'), 'Timestamp must be ISO 8601');
    Assert.IsTrue(LTimestamp.EndsWith('Z'), 'Timestamp must end with Z (UTC)');
  finally
    LJson.Free;
  end;
end;

procedure TJSONLLogProviderTests.TestCustomFileName;
var
  LCustomFile: string;
  LEntry: TLogEntry;
begin
  LCustomFile := TPath.Combine(FTestDir, 'custom.jsonl');
  TJSONLLogProvider.SetLogFileName(LCustomFile);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'custom-name';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  Assert.IsTrue(TFile.Exists(LCustomFile), 'Custom JSONL file should be created');
end;

procedure TJSONLLogProviderTests.TestDirectoryCreation;
var
  LSubDir: string;
  LFileInSubDir: string;
  LEntry: TLogEntry;
begin
  LSubDir := TPath.Combine(FTestDir, 'subdir');
  LFileInSubDir := TPath.Combine(LSubDir, 'nested.jsonl');

  TJSONLLogProvider.SetLogFileName(LFileInSubDir);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'nested';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  Assert.IsTrue(TDirectory.Exists(LSubDir), 'Subdirectory should be created');
  Assert.IsTrue(TFile.Exists(LFileInSubDir), 'Log file in subdirectory should exist');
end;

procedure TJSONLLogProviderTests.TestFileRotation;
var
  LEntry: TLogEntry;
  i: Integer;
  LFiles: TArray<string>;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);
  TJSONLLogProvider.SetMaxFileSize(1024); // 1 KB

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

  for i := 1 to 80 do
  begin
    LEntry.Message := StringOfChar('X', 40);
    TJSONLLogProvider.Instance.Log(LEntry);
  end;

  TJSONLLogProvider.Instance.Flush;
  Sleep(100);

  LFiles := TDirectory.GetFiles(FTestDir, '*.jsonl');
  Assert.IsTrue(Length(LFiles) > 1, 'File rotation should create backup files');
end;

type
  TJSONLLoggingWorker = class(TThread)
  public
    WorkerIndex: Integer;
    WorkerMessagesPerThread: Integer;
  protected
    procedure Execute; override;
  end;

procedure TJSONLLoggingWorker.Execute;
var
  j: Integer;
  LEntry: TLogEntry;
begin
  for j := 1 to WorkerMessagesPerThread do
  begin
    LEntry := Default(TLogEntry);
    LEntry.Timestamp := Now;
    LEntry.Level := TLogLevel.Info;
    LEntry.Message := Format('Thread %d Message %d', [WorkerIndex + 1, j]);
    LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
    TJSONLLogProvider.Instance.Log(LEntry);
  end;
end;

procedure TJSONLLogProviderTests.TestThreadSafety;
var
  LThreadCount: Integer;
  LMessagesPerThread: Integer;
  LExpectedCount: Integer;
  LThreads: array of TThread;
  LWorker: TJSONLLoggingWorker;
  LLines: TArray<string>;
  i: Integer;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);
  TJSONLLogProvider.SetMaxFileSize(100 * 1024 * 1024); // avoid rotation

  TJSONLLogProvider.Instance.Flush;
  if TFile.Exists(FTestLogFile) then
    TFile.Delete(FTestLogFile);

  LThreadCount := 10;
  LMessagesPerThread := 50;
  LExpectedCount := LThreadCount * LMessagesPerThread;

  SetLength(LThreads, LThreadCount);

  for i := 0 to LThreadCount - 1 do
  begin
    LWorker := TJSONLLoggingWorker.Create(True);
    LWorker.WorkerIndex := i;
    LWorker.WorkerMessagesPerThread := LMessagesPerThread;
    LWorker.FreeOnTerminate := False;
    LThreads[i] := LWorker;
    LWorker.Start;
  end;

  for i := 0 to LThreadCount - 1 do
  begin
    LThreads[i].WaitFor;
    LThreads[i].Free;
  end;

  TJSONLLogProvider.Instance.Flush;

  Assert.IsTrue(TFile.Exists(FTestLogFile), 'Log file should exist');
  LLines := ReadAllLines;
  Assert.AreEqual(LExpectedCount, Length(LLines),
    'All messages from all threads should be written as separate lines');
end;

procedure TJSONLLogProviderTests.TestMemoryInfoField;
var
  LEntry: TLogEntry;
  LJson: TJSONObject;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'with-memory';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
  LEntry.MemoryInfo := 'WS:45MB PB:22MB';

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  LJson := ParseLastObject;
  try
    Assert.AreEqual('WS:45MB PB:22MB', LJson.GetValue<string>('memoryInfo'),
      'memoryInfo field must be present and correct');
  finally
    LJson.Free;
  end;
end;

procedure TJSONLLogProviderTests.TestDetailsField;
var
  LEntry: TLogEntry;
  LJson: TJSONObject;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Error;
  LEntry.Message := 'with-details';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
  LEntry.Details := 'stack trace / large payload here';

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  LJson := ParseLastObject;
  try
    Assert.AreEqual('stack trace / large payload here',
      LJson.GetValue<string>('details'),
      'details field must be present and correct');
  finally
    LJson.Free;
  end;
end;

procedure TJSONLLogProviderTests.TestAppVersionField;
var
  LEntry: TLogEntry;
  LJson: TJSONObject;
begin
  TDXLogger.SetAppVersion('9.8.7.6543');
  try
    TJSONLLogProvider.SetLogFileName(FTestLogFile);

    LEntry := Default(TLogEntry);
    LEntry.Timestamp := Now;
    LEntry.Level := TLogLevel.Info;
    LEntry.Message := 'with-version';
    LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;

    TJSONLLogProvider.Instance.Log(LEntry);
    TJSONLLogProvider.Instance.Flush;

    LJson := ParseLastObject;
    try
      Assert.AreEqual('9.8.7.6543', LJson.GetValue<string>('appVersion'),
        'appVersion field must be present when set on TDXLogger');
    finally
      LJson.Free;
    end;
  finally
    TDXLogger.SetAppVersion('');
  end;
end;

procedure TJSONLLogProviderTests.TestStructuredProperties;
var
  LEntry: TLogEntry;
  LJson: TJSONObject;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Error;
  LEntry.Message := 'request-failed';
  LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
  LEntry.Properties := TArray<TPair<string, string>>.Create(
    TPair<string, string>.Create('RequestURL', '/v1/orders'),
    TPair<string, string>.Create('HttpMethod', 'POST'),
    TPair<string, string>.Create('StatusCode', '500'));

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  LJson := ParseLastObject;
  try
    Assert.AreEqual('/v1/orders', LJson.GetValue<string>('RequestURL'));
    Assert.AreEqual('POST', LJson.GetValue<string>('HttpMethod'));
    Assert.AreEqual('500', LJson.GetValue<string>('StatusCode'));
  finally
    LJson.Free;
  end;
end;

procedure TJSONLLogProviderTests.TestReservedKeysNotOverwritten;
var
  LEntry: TLogEntry;
  LJson: TJSONObject;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'real-message';
  LEntry.ThreadID := 999;
  LEntry.Properties := TArray<TPair<string, string>>.Create(
    TPair<string, string>.Create('message', 'OVERRIDE'),
    TPair<string, string>.Create('level', 'OVERRIDE'),
    TPair<string, string>.Create('@m', 'CLEF-RESERVED'),
    TPair<string, string>.Create('', 'EMPTY-KEY'),
    TPair<string, string>.Create('Safe', 'kept'));

  TJSONLLogProvider.Instance.Log(LEntry);
  TJSONLLogProvider.Instance.Flush;

  LJson := ParseLastObject;
  try
    Assert.AreEqual('real-message', LJson.GetValue<string>('message'),
      'Canonical message must not be overwritten by a property');
    Assert.AreEqual('INFO', LJson.GetValue<string>('level'),
      'Canonical level must not be overwritten by a property');
    Assert.IsFalse(LJson.ToJSON.Contains('OVERRIDE'),
      'Conflicting property values must be dropped');
    Assert.IsFalse(LJson.ToJSON.Contains('CLEF-RESERVED'),
      '@-prefixed keys must be ignored');
    Assert.AreEqual('kept', LJson.GetValue<string>('Safe'),
      'Non-conflicting property must still be rendered');
  finally
    LJson.Free;
  end;
end;

procedure TJSONLLogProviderTests.TestMultipleEntriesMultipleLines;
var
  LEntry: TLogEntry;
  LLines: TArray<string>;
  LJson: TJSONObject;
  i: Integer;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  for i := 1 to 3 do
  begin
    LEntry := Default(TLogEntry);
    LEntry.Timestamp := Now;
    LEntry.Level := TLogLevel.Info;
    LEntry.Message := Format('entry-%d', [i]);
    LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
    TJSONLLogProvider.Instance.Log(LEntry);
  end;

  TJSONLLogProvider.Instance.Flush;

  LLines := ReadAllLines;
  Assert.AreEqual(3, Length(LLines));

  for i := 0 to 2 do
  begin
    LJson := ParseObjectAt(i);
    try
      Assert.AreEqual(Format('entry-%d', [i + 1]), LJson.GetValue<string>('message'));
    finally
      LJson.Free;
    end;
  end;
end;

procedure TJSONLLogProviderTests.TestFlush;
var
  LEntry: TLogEntry;
  i: Integer;
  LLines: TArray<string>;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  for i := 1 to 7 do
  begin
    LEntry := Default(TLogEntry);
    LEntry.Timestamp := Now;
    LEntry.Level := TLogLevel.Debug;
    LEntry.Message := Format('flush-%d', [i]);
    LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
    TJSONLLogProvider.Instance.Log(LEntry);
  end;

  // Explicit flush must make everything durable before we read.
  TJSONLLogProvider.Instance.Flush;

  LLines := ReadAllLines;
  Assert.AreEqual(7, Length(LLines), 'Flush must drain all pending entries');
end;

procedure TJSONLLogProviderTests.TestLogLevels;
var
  LLevels: TArray<TLogLevel>;
  LExpected: TArray<string>;
  LEntry: TLogEntry;
  LJson: TJSONObject;
  i: Integer;
begin
  TJSONLLogProvider.SetLogFileName(FTestLogFile);

  LLevels := [TLogLevel.Trace, TLogLevel.Debug, TLogLevel.Info, TLogLevel.Warn, TLogLevel.Error];
  LExpected := ['TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR'];

  for i := 0 to High(LLevels) do
  begin
    LEntry := Default(TLogEntry);
    LEntry.Timestamp := Now;
    LEntry.Level := LLevels[i];
    LEntry.Message := 'level-test';
    LEntry.ThreadID := Winapi.Windows.GetCurrentThreadId;
    TJSONLLogProvider.Instance.Log(LEntry);
  end;

  TJSONLLogProvider.Instance.Flush;

  for i := 0 to High(LLevels) do
  begin
    LJson := ParseObjectAt(i);
    try
      Assert.AreEqual(LExpected[i], LJson.GetValue<string>('level'),
        Format('Level mapping failed for index %d', [i]));
    finally
      LJson.Free;
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJSONLLogProviderTests);

end.
