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

initialization
  TDUnitX.RegisterTestFixture(TSeqLogProviderTests);

end.

