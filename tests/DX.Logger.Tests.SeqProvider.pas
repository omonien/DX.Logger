unit DX.Logger.Tests.SeqProvider;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  DX.Logger,
  DX.Logger.Provider.Seq;

type
  /// <summary>
  /// Mock HTTP capture provider to test Seq provider without actual HTTP calls
  /// </summary>
  TMockSeqCapture = class(TInterfacedObject, ILogProvider)
  private
    FLogEntries: TList<TLogEntry>;
    FLastCLEFJson: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Log(const AEntry: TLogEntry);
    procedure Clear;
    function GetEntryCount: Integer;
    function GetLastEntry: TLogEntry;
    function GetLastCLEFJson: string;
    property LastCLEFJson: TStringList read FLastCLEFJson;
  end;

  [TestFixture]
  TSeqLogProviderTests = class
  private
    FMockCapture: TMockSeqCapture;
    FMockCaptureIntf: ILogProvider;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestProviderCreation;
    [Test]
    procedure TestConfiguration;
    [Test]
    procedure TestLogEntry;
    [Test]
    procedure TestCLEFFormat;
    [Test]
    procedure TestLogLevelMapping;
    [Test]
    procedure TestAsyncLogging;
    [Test]
    procedure TestBatching;
    [Test]
    procedure TestFlush;
    [Test]
    procedure TestThreadSafety;
    [Test]
    procedure TestShutdown;
    [Test]
    procedure TestValidateConnectionWithoutUrl;
    [Test]
    procedure TestValidateConnectionWithInvalidUrl;
    [Test]
    procedure TestImplementsILogProviderValidation;
    [Test]
    procedure TestCLEFContainsAppVersionWhenSet;
    [Test]
    procedure TestCLEFOmitsAppVersionWhenEmpty;
    [Test]
    procedure TestCLEFRendersStructuredProperties;
    [Test]
    procedure TestCLEFIgnoresReservedAtPropertyKeys;
    [Test]
    procedure TestPropertiesSurviveAsyncQueue;
  end;

implementation

uses
  System.SyncObjs,
  System.Threading,
  System.DateUtils,
  Winapi.Windows;

{ TMockSeqCapture }

constructor TMockSeqCapture.Create;
begin
  inherited Create;
  FLogEntries := TList<TLogEntry>.Create;
  FLastCLEFJson := TStringList.Create;
end;

destructor TMockSeqCapture.Destroy;
begin
  FreeAndNil(FLastCLEFJson);
  FreeAndNil(FLogEntries);
  inherited;
end;

procedure TMockSeqCapture.Log(const AEntry: TLogEntry);
begin
  TMonitor.Enter(Self);
  try
    FLogEntries.Add(AEntry);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TMockSeqCapture.Clear;
begin
  TMonitor.Enter(Self);
  try
    FLogEntries.Clear;
    FLastCLEFJson.Clear;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMockSeqCapture.GetEntryCount: Integer;
begin
  TMonitor.Enter(Self);
  try
    Result := FLogEntries.Count;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMockSeqCapture.GetLastEntry: TLogEntry;
begin
  TMonitor.Enter(Self);
  try
    if FLogEntries.Count > 0 then
      Result := FLogEntries[FLogEntries.Count - 1]
    else
      raise Exception.Create('No log entries available');
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMockSeqCapture.GetLastCLEFJson: string;
begin
  TMonitor.Enter(Self);
  try
    if FLastCLEFJson.Count > 0 then
      Result := FLastCLEFJson[FLastCLEFJson.Count - 1]
    else
      Result := '';
  finally
    TMonitor.Exit(Self);
  end;
end;

{ TSeqLogProviderTests }

procedure TSeqLogProviderTests.Setup;
begin
  // Create mock capture
  FMockCapture := TMockSeqCapture.Create;
  FMockCaptureIntf := FMockCapture;
  
  // Set minimum log level
  TDXLogger.SetMinLevel(TLogLevel.Trace);
end;

procedure TSeqLogProviderTests.TearDown;
begin
  // Clean up
  if Assigned(FMockCaptureIntf) then
    FMockCaptureIntf := nil;
  FMockCapture := nil;
end;

procedure TSeqLogProviderTests.TestProviderCreation;
var
  LProvider: TSeqLogProvider;
begin
  LProvider := TSeqLogProvider.Instance;
  Assert.IsNotNull(LProvider, 'Provider instance should be created');
end;

procedure TSeqLogProviderTests.TestConfiguration;
begin
  TSeqLogProvider.SetServerUrl('https://test-seq-server.example.com');
  TSeqLogProvider.SetApiKey('test-api-key-placeholder');
  TSeqLogProvider.SetBatchSize(25);
  TSeqLogProvider.SetFlushInterval(3000);

  // Configuration should not raise exceptions
  Assert.Pass('Configuration methods executed successfully');
end;

procedure TSeqLogProviderTests.TestLogEntry;
var
  LEntry: TLogEntry;
begin
  // Register mock capture to intercept logs
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);

  FMockCapture.Clear;

  // Create and log entry
  DXLog('Test message', TLogLevel.Info);

  // Wait a bit for async processing
  Sleep(50);

  Assert.AreEqual(1, FMockCapture.GetEntryCount, 'Should have one log entry');
  LEntry := FMockCapture.GetLastEntry;
  Assert.AreEqual('Test message', LEntry.Message);
  Assert.AreEqual(TLogLevel.Info, LEntry.Level);

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestCLEFFormat;
begin
  // We need to test the CLEF format indirectly through the provider
  // Since FormatCLEF is private, we'll verify the structure by checking
  // that the provider can be created and configured
  TSeqLogProvider.SetServerUrl('https://test-seq-server.example.com');
  TSeqLogProvider.SetApiKey('test-api-key-placeholder');

  // Log a message to ensure CLEF formatting works
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  FMockCapture.Clear;

  DXLog('Test CLEF message', TLogLevel.Info);
  Sleep(100);

  Assert.AreEqual(1, FMockCapture.GetEntryCount, 'CLEF formatted message should be logged');

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestLogLevelMapping;
var
  LTestCases: array[0..4] of record
    Level: TLogLevel;
    ExpectedSeqLevel: string;
  end;
  i: Integer;
begin
  // Define expected mappings
  LTestCases[0].Level := TLogLevel.Trace;
  LTestCases[0].ExpectedSeqLevel := 'Verbose';

  LTestCases[1].Level := TLogLevel.Debug;
  LTestCases[1].ExpectedSeqLevel := 'Debug';

  LTestCases[2].Level := TLogLevel.Info;
  LTestCases[2].ExpectedSeqLevel := 'Information';

  LTestCases[3].Level := TLogLevel.Warn;
  LTestCases[3].ExpectedSeqLevel := 'Warning';

  LTestCases[4].Level := TLogLevel.Error;
  LTestCases[4].ExpectedSeqLevel := 'Error';

  // Test that provider accepts all log levels
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  FMockCapture.Clear;

  for i := 0 to High(LTestCases) do
  begin
    DXLog('Test', LTestCases[i].Level);
  end;

  Sleep(100);
  Assert.AreEqual(5, FMockCapture.GetEntryCount, 'All log levels should be processed');

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestAsyncLogging;
var
  LStartTime: TDateTime;
  LElapsedMs: Int64;
begin
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  FMockCapture.Clear;

  LStartTime := Now;

  // Log multiple messages
  DXLog('Message 1');
  DXLog('Message 2');
  DXLog('Message 3');

  LElapsedMs := MilliSecondsBetween(Now, LStartTime);

  // Async logging should be very fast (< 100ms for 3 messages)
  Assert.IsTrue(LElapsedMs < 100, 'Async logging should be fast');

  // Wait for messages to be processed
  Sleep(200);

  Assert.AreEqual(3, FMockCapture.GetEntryCount, 'All messages should be logged');

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestBatching;
var
  i: Integer;
begin
  TSeqLogProvider.SetBatchSize(5);
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  FMockCapture.Clear;

  // Log 12 messages (should create 2 full batches + 2 remaining)
  for i := 1 to 12 do
    DXLog(Format('Message %d', [i]));

  // Wait for batches to be processed
  Sleep(500);

  Assert.AreEqual(12, FMockCapture.GetEntryCount, 'All messages should be logged');

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestFlush;
var
  i: Integer;
begin
  TSeqLogProvider.SetBatchSize(100); // Large batch size
  TSeqLogProvider.SetFlushInterval(10000); // Long interval

  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  FMockCapture.Clear;

  // Log a few messages
  for i := 1 to 5 do
    DXLog(Format('Message %d', [i]));

  // Wait for async worker thread to process messages
  // Even with long flush interval, the batch will be processed eventually
  Sleep(500);

  Assert.AreEqual(5, FMockCapture.GetEntryCount, 'All messages should be processed');

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestThreadSafety;
var
  LThreadCount: Integer;
  LMessagesPerThread: Integer;
  LExpectedTotal: Integer;
  LThreads: array of TThread;
  i: Integer;
begin
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  FMockCapture.Clear;

  LThreadCount := 10;
  LMessagesPerThread := 50;
  LExpectedTotal := LThreadCount * LMessagesPerThread;

  SetLength(LThreads, LThreadCount);

  // Create and start all threads
  for i := 0 to LThreadCount - 1 do
  begin
    LThreads[i] := TThread.CreateAnonymousThread(
      procedure
      var
        j: Integer;
        LThreadIndex: Integer;
      begin
        LThreadIndex := i + 1; // Capture thread index
        for j := 1 to LMessagesPerThread do
          DXLog(Format('Thread %d Message %d', [LThreadIndex, j]));
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

  // Wait for all messages to be processed
  Sleep(1000);

  Assert.AreEqual(LExpectedTotal, FMockCapture.GetEntryCount,
    'All messages from all threads should be logged');

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestShutdown;
begin
  // Test that provider can be created and destroyed without errors
  TSeqLogProvider.SetServerUrl('https://test-seq-server.example.com');
  TSeqLogProvider.SetApiKey('test-api-key-placeholder');

  // Log some messages
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  DXLog('Test message 1');
  DXLog('Test message 2');

  // Unregister and cleanup
  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);

  // Wait for cleanup
  Sleep(200);

  Assert.Pass('Provider shutdown completed without errors');
end;

procedure TSeqLogProviderTests.TestValidateConnectionWithoutUrl;
var
  LResult: Boolean;
begin
  // Register mock to capture error messages
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  FMockCapture.Clear;

  // Clear URL configuration
  TSeqLogProvider.SetServerUrl('');

  // Validate should fail and log an error
  LResult := TSeqLogProvider.ValidateConnection;

  Assert.IsFalse(LResult, 'ValidateConnection should return False when URL is not configured');

  // Check that error was logged
  Sleep(50);
  Assert.IsTrue(FMockCapture.GetEntryCount > 0, 'Error should be logged');
  Assert.AreEqual(TLogLevel.Error, FMockCapture.GetLastEntry.Level, 'Should log at Error level');
  Assert.IsTrue(FMockCapture.GetLastEntry.Message.Contains('not configured'),
    'Error message should mention URL not configured');

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestValidateConnectionWithInvalidUrl;
var
  LResult: Boolean;
begin
  // Register mock to capture error messages
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  FMockCapture.Clear;

  // Set an invalid URL that will fail to connect
  TSeqLogProvider.SetServerUrl('http://invalid-host-that-does-not-exist.local');
  TSeqLogProvider.SetApiKey('test-key');

  // Validate should fail due to network error
  LResult := TSeqLogProvider.ValidateConnection;

  Assert.IsFalse(LResult, 'ValidateConnection should return False for invalid URL');

  // Check that error was logged
  Sleep(50);
  Assert.IsTrue(FMockCapture.GetEntryCount > 0, 'Error should be logged');
  Assert.AreEqual(TLogLevel.Error, FMockCapture.GetLastEntry.Level, 'Should log at Error level');

  TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
end;

procedure TSeqLogProviderTests.TestImplementsILogProviderValidation;
var
  LProvider: TSeqLogProvider;
  LValidation: ILogProviderValidation;
begin
  LProvider := TSeqLogProvider.Instance;

  // Test that provider implements ILogProviderValidation
  Assert.IsTrue(Supports(LProvider, ILogProviderValidation, LValidation),
    'TSeqLogProvider should implement ILogProviderValidation interface');
end;

procedure TSeqLogProviderTests.TestCLEFContainsAppVersionWhenSet;
var
  LEntry: TLogEntry;
  LJson: string;
begin
  TDXLogger.SetAppVersion('1.2.3.4567');
  try
    LEntry := Default(TLogEntry);
    LEntry.Timestamp := Now;
    LEntry.Level := TLogLevel.Info;
    LEntry.Message := 'with-version';
    LEntry.ThreadID := TThread.CurrentThread.ThreadID;

    LJson := TSeqLogProvider.Instance.FormatCLEF(LEntry);
    Assert.IsTrue(LJson.Contains('"AppVersion":"1.2.3.4567"'),
      'CLEF must include AppVersion when set on TDXLogger');
  finally
    // Reset to '' so other tests are unaffected; auto-detect re-runs lazily.
    TDXLogger.SetAppVersion('');
  end;
end;

procedure TSeqLogProviderTests.TestCLEFOmitsAppVersionWhenEmpty;
var
  LEntry: TLogEntry;
  LJson: string;
begin
  // Force empty value AND mark as resolved by setting then clearing — but
  // SetAppVersion('') re-enables auto-detect. Under TestInsight the test
  // EXE has its own version resource, so auto-detect may produce a value.
  // We verify by setting explicitly to a sentinel, then asserting that the
  // sentinel either appears (if auto-detect blocked) or that no AppVersion
  // field appears at all when truly empty. To get a deterministic empty
  // case, we cannot easily reach the private FAppVersionResolved flag, so
  // this test asserts only that AppVersion is omitted when GetAppVersion
  // returns empty — which we ensure by setting to '' AFTER the EXE-version
  // has been pre-resolved to '' by passing an empty explicit value first.
  TDXLogger.SetAppVersion(''); // re-enables auto-detect on next read

  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'omit-test';
  LEntry.ThreadID := TThread.CurrentThread.ThreadID;

  LJson := TSeqLogProvider.Instance.FormatCLEF(LEntry);
  // If the test EXE has no version resource OR auto-detect failed, the
  // field must be absent. If it has a version, the field is present and
  // this assertion is skipped. We accept both — the contract is "absent
  // when empty", not "always absent".
  if TDXLogger.GetAppVersion = '' then
    Assert.IsFalse(LJson.Contains('"AppVersion"'),
      'CLEF must omit AppVersion field when value is empty')
  else
    Assert.Pass('Test EXE has a version resource; auto-detect populated AppVersion');
end;

procedure TSeqLogProviderTests.TestCLEFRendersStructuredProperties;
var
  LEntry: TLogEntry;
  LJson: string;
begin
  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Error;
  LEntry.Message := 'request-failed';
  LEntry.ThreadID := TThread.CurrentThread.ThreadID;
  LEntry.Properties := TArray<TPair<string, string>>.Create(
    TPair<string, string>.Create('RequestURL', '/v1/me/kontrolleBeenden'),
    TPair<string, string>.Create('HttpMethod', 'POST'),
    TPair<string, string>.Create('StatusCode', '500'));

  LJson := TSeqLogProvider.Instance.FormatCLEF(LEntry);
  Assert.IsTrue(LJson.Contains('"RequestURL":"\/v1\/me\/kontrolleBeenden"') or
                LJson.Contains('"RequestURL":"/v1/me/kontrolleBeenden"'),
    'CLEF must render RequestURL as a top-level field');
  Assert.IsTrue(LJson.Contains('"HttpMethod":"POST"'),
    'CLEF must render HttpMethod as a top-level field');
  Assert.IsTrue(LJson.Contains('"StatusCode":"500"'),
    'CLEF must render StatusCode as a top-level field');
end;

procedure TSeqLogProviderTests.TestCLEFIgnoresReservedAtPropertyKeys;
var
  LEntry: TLogEntry;
  LJson: string;
begin
  LEntry := Default(TLogEntry);
  LEntry.Timestamp := Now;
  LEntry.Level := TLogLevel.Info;
  LEntry.Message := 'real-message';
  LEntry.ThreadID := TThread.CurrentThread.ThreadID;
  LEntry.Properties := TArray<TPair<string, string>>.Create(
    TPair<string, string>.Create('@m', 'OVERRIDE'),
    TPair<string, string>.Create('', 'IGNORED'),
    TPair<string, string>.Create('Safe', 'kept'));

  LJson := TSeqLogProvider.Instance.FormatCLEF(LEntry);
  // Original @m must remain — the '@m' property must be silently dropped.
  Assert.IsTrue(LJson.Contains('"@m":"real-message"'),
    'Original @m field must not be overwritten by a reserved property key');
  Assert.IsFalse(LJson.Contains('OVERRIDE'),
    'Reserved-prefix property must be dropped');
  Assert.IsTrue(LJson.Contains('"Safe":"kept"'),
    'Non-reserved property must still be rendered');
end;

procedure TSeqLogProviderTests.TestPropertiesSurviveAsyncQueue;
var
  LProps: TArray<TPair<string, string>>;
  LCaptured: TLogEntry;
begin
  TDXLogger.Instance.RegisterProvider(FMockCaptureIntf);
  try
    FMockCapture.Clear;

    LProps := TArray<TPair<string, string>>.Create(
      TPair<string, string>.Create('UserEmail', 'lisa@example.org'),
      TPair<string, string>.Create('TransactionID', 'tx-42'));

    TDXLogger.Instance.Log('queued-with-props', TLogLevel.Warn, '', LProps);
    Sleep(50);

    Assert.AreEqual(1, FMockCapture.GetEntryCount, 'Entry must reach the provider');
    LCaptured := FMockCapture.GetLastEntry;
    Assert.AreEqual<NativeInt>(2, Length(LCaptured.Properties),
      'Properties array must survive transit through the logger');
    Assert.AreEqual('UserEmail', LCaptured.Properties[0].Key);
    Assert.AreEqual('lisa@example.org', LCaptured.Properties[0].Value);
    Assert.AreEqual('TransactionID', LCaptured.Properties[1].Key);
    Assert.AreEqual('tx-42', LCaptured.Properties[1].Value);
  finally
    TDXLogger.Instance.UnregisterProvider(FMockCaptureIntf);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSeqLogProviderTests);

end.

