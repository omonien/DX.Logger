unit DX.Logger.Tests.Core;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Logger;

type
  /// <summary>
  /// Mock provider for testing
  /// </summary>
  TMockLogProvider = class(TInterfacedObject, ILogProvider)
  private
    FLogEntries: TList<TLogEntry>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Log(const AEntry: TLogEntry);
    procedure Clear;
    function GetEntryCount: Integer;
    function GetEntry(AIndex: Integer): TLogEntry;
    function GetLastEntry: TLogEntry;
  end;

  [TestFixture]
  TDXLoggerTests = class
  private
    FMockProvider: TMockLogProvider;
    FMockProviderIntf: ILogProvider;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestSingletonInstance;
    [Test]
    procedure TestLogLevels;
    [Test]
    procedure TestMinLogLevel;
    [Test]
    procedure TestRegisterProvider;
    [Test]
    procedure TestUnregisterProvider;
    [Test]
    procedure TestLogEntry;
    [Test]
    procedure TestConvenienceFunctions;
    [Test]
    procedure TestLogLevelToString;
    [Test]
    procedure TestThreadSafety;
    [Test]
    procedure TestMemoryInfoDefaultEmpty;
    [Test]
    procedure TestMemoryInfoCallbackPopulatesEntry;
    [Test]
    procedure TestMemoryInfoCallbackClearedByNil;
    [Test]
    procedure TestMemoryInfoCallbackExceptionSwallowed;
    [Test]
    procedure TestStackInfoCallbackDefaultNil;
    [Test]
    procedure TestStackInfoCallbackPopulatesDetails;
    [Test]
    procedure TestStackInfoCallbackDoesNotOverwriteExistingDetails;
    [Test]
    procedure TestStackInfoCallbackExceptionSwallowed;
  end;

implementation

uses
  System.SyncObjs,
  System.Threading;

{ TMockLogProvider }

constructor TMockLogProvider.Create;
begin
  inherited Create;
  FLogEntries := TList<TLogEntry>.Create;
end;

destructor TMockLogProvider.Destroy;
begin
  FreeAndNil(FLogEntries);
  inherited;
end;

procedure TMockLogProvider.Log(const AEntry: TLogEntry);
begin
  TMonitor.Enter(Self);
  try
    FLogEntries.Add(AEntry);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TMockLogProvider.Clear;
begin
  TMonitor.Enter(Self);
  try
    FLogEntries.Clear;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMockLogProvider.GetEntryCount: Integer;
begin
  TMonitor.Enter(Self);
  try
    Result := FLogEntries.Count;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMockLogProvider.GetEntry(AIndex: Integer): TLogEntry;
begin
  TMonitor.Enter(Self);
  try
    Result := FLogEntries[AIndex];
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMockLogProvider.GetLastEntry: TLogEntry;
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

{ TDXLoggerTests }

procedure TDXLoggerTests.Setup;
begin
  FMockProvider := TMockLogProvider.Create;
  FMockProviderIntf := FMockProvider; // Keep interface reference
  TDXLogger.Instance.RegisterProvider(FMockProviderIntf);
  TDXLogger.SetMinLevel(TLogLevel.Trace); // Log everything for tests
end;

procedure TDXLoggerTests.TearDown;
begin
  if Assigned(FMockProviderIntf) then
  begin
    TDXLogger.Instance.UnregisterProvider(FMockProviderIntf);
    FMockProviderIntf := nil; // Release interface first
  end;
  FMockProvider := nil; // Then clear class reference
end;

procedure TDXLoggerTests.TestSingletonInstance;
var
  LInstance1, LInstance2: TDXLogger;
begin
  LInstance1 := TDXLogger.Instance;
  LInstance2 := TDXLogger.Instance;
  Assert.AreSame(LInstance1, LInstance2, 'Singleton should return same instance');
end;

procedure TDXLoggerTests.TestLogLevels;
begin
  FMockProvider.Clear;
  
  DXLog('Test', TLogLevel.Trace);
  Assert.AreEqual(TLogLevel.Trace, FMockProvider.GetLastEntry.Level);
  
  DXLog('Test', TLogLevel.Debug);
  Assert.AreEqual(TLogLevel.Debug, FMockProvider.GetLastEntry.Level);

  DXLog('Test', TLogLevel.Info);
  Assert.AreEqual(TLogLevel.Info, FMockProvider.GetLastEntry.Level);

  DXLog('Test', TLogLevel.Warn);
  Assert.AreEqual(TLogLevel.Warn, FMockProvider.GetLastEntry.Level);

  DXLog('Test', TLogLevel.Error);
  Assert.AreEqual(TLogLevel.Error, FMockProvider.GetLastEntry.Level);
end;

procedure TDXLoggerTests.TestMinLogLevel;
begin
  FMockProvider.Clear;

  // Set minimum level to Warn
  TDXLogger.SetMinLevel(TLogLevel.Warn);

  DXLog('Trace', TLogLevel.Trace);
  DXLog('Debug', TLogLevel.Debug);
  DXLog('Info', TLogLevel.Info);
  Assert.AreEqual(0, FMockProvider.GetEntryCount, 'Should not log below minimum level');

  DXLog('Warn', TLogLevel.Warn);
  Assert.AreEqual(1, FMockProvider.GetEntryCount);

  DXLog('Error', TLogLevel.Error);
  Assert.AreEqual(2, FMockProvider.GetEntryCount);

  // Reset to Trace for other tests
  TDXLogger.SetMinLevel(TLogLevel.Trace);
end;

procedure TDXLoggerTests.TestRegisterProvider;
var
  LMockProvider2: ILogProvider;
  LMockProvider2Impl: TMockLogProvider;
begin
  FMockProvider.Clear;
  LMockProvider2Impl := TMockLogProvider.Create;
  LMockProvider2 := LMockProvider2Impl; // Interface reference

  TDXLogger.Instance.RegisterProvider(LMockProvider2);

  DXLog('Test message');

  Assert.AreEqual(1, FMockProvider.GetEntryCount, 'First provider should receive message');
  Assert.AreEqual(1, LMockProvider2Impl.GetEntryCount, 'Second provider should receive message');

  TDXLogger.Instance.UnregisterProvider(LMockProvider2);
  // No Free needed - interface handles lifetime
end;

procedure TDXLoggerTests.TestUnregisterProvider;
begin
  FMockProvider.Clear;

  DXLog('Before unregister');
  Assert.AreEqual(1, FMockProvider.GetEntryCount);

  TDXLogger.Instance.UnregisterProvider(FMockProviderIntf);

  DXLog('After unregister');
  Assert.AreEqual(1, FMockProvider.GetEntryCount, 'Should not receive messages after unregister');

  // Re-register for cleanup
  TDXLogger.Instance.RegisterProvider(FMockProviderIntf);
end;

procedure TDXLoggerTests.TestLogEntry;
var
  LEntry: TLogEntry;
begin
  FMockProvider.Clear;

  DXLog('Test message', TLogLevel.Info);

  LEntry := FMockProvider.GetLastEntry;
  Assert.AreEqual('Test message', LEntry.Message);
  Assert.AreEqual(TLogLevel.Info, LEntry.Level);
  Assert.IsTrue(LEntry.Timestamp > 0, 'Timestamp should be set');
  Assert.IsTrue(LEntry.ThreadID > 0, 'ThreadID should be set');
end;

procedure TDXLoggerTests.TestConvenienceFunctions;
begin
  FMockProvider.Clear;

  DXLogTrace('Trace');
  Assert.AreEqual(TLogLevel.Trace, FMockProvider.GetLastEntry.Level);

  DXLogDebug('Debug');
  Assert.AreEqual(TLogLevel.Debug, FMockProvider.GetLastEntry.Level);

  DXLogInfo('Info');
  Assert.AreEqual(TLogLevel.Info, FMockProvider.GetLastEntry.Level);

  DXLogWarn('Warn');
  Assert.AreEqual(TLogLevel.Warn, FMockProvider.GetLastEntry.Level);

  DXLogError('Error');
  Assert.AreEqual(TLogLevel.Error, FMockProvider.GetLastEntry.Level);
end;

procedure TDXLoggerTests.TestLogLevelToString;
begin
  Assert.AreEqual('TRACE', LogLevelToString(TLogLevel.Trace));
  Assert.AreEqual('DEBUG', LogLevelToString(TLogLevel.Debug));
  Assert.AreEqual('INFO', LogLevelToString(TLogLevel.Info));
  Assert.AreEqual('WARN', LogLevelToString(TLogLevel.Warn));
  Assert.AreEqual('ERROR', LogLevelToString(TLogLevel.Error));
end;

procedure TDXLoggerTests.TestThreadSafety;
var
  LThreadCount: Integer;
  LMessagesPerThread: Integer;
  LExpectedTotal: Integer;
begin
  FMockProvider.Clear;
  LThreadCount := 10;
  LMessagesPerThread := 100;
  LExpectedTotal := LThreadCount * LMessagesPerThread;

  TParallel.For(1, LThreadCount, procedure(AIndex: Integer)
  var
    i: Integer;
  begin
    for i := 1 to LMessagesPerThread do
      DXLog(Format('Thread %d Message %d', [AIndex, i]));
  end);

  Assert.AreEqual(LExpectedTotal, FMockProvider.GetEntryCount,
    'All messages from all threads should be logged');
end;

{ Memory-Info callback tests }

// Baseline: without a callback set, MemoryInfo on new entries is empty.
procedure TDXLoggerTests.TestMemoryInfoDefaultEmpty;
var
  LEntry: TLogEntry;
begin
  TDXLogger.Instance.MemoryInfoCallback := nil;
  FMockProvider.Clear;
  DXLog('no-memory-info');
  Assert.AreEqual(1, FMockProvider.GetEntryCount);
  LEntry := FMockProvider.GetLastEntry;
  Assert.AreEqual('', LEntry.MemoryInfo,
    'MemoryInfo should be empty when no callback is installed');
end;

// A registered callback's result is attached to every subsequent entry.
procedure TDXLoggerTests.TestMemoryInfoCallbackPopulatesEntry;
var
  LEntry: TLogEntry;
begin
  TDXLogger.Instance.MemoryInfoCallback :=
    function: string
    begin
      Result := 'WS:42MB PB:17MB';
    end;
  try
    FMockProvider.Clear;
    DXLog('with-memory-info');
    Assert.AreEqual(1, FMockProvider.GetEntryCount);
    LEntry := FMockProvider.GetLastEntry;
    Assert.AreEqual('WS:42MB PB:17MB', LEntry.MemoryInfo,
      'MemoryInfo should carry the callback result');
  finally
    TDXLogger.Instance.MemoryInfoCallback := nil;
  end;
end;

// Assigning nil removes the callback; later entries carry no memory info.
procedure TDXLoggerTests.TestMemoryInfoCallbackClearedByNil;
var
  LCount: Integer;
  LEntry: TLogEntry;
begin
  LCount := 0;
  TDXLogger.Instance.MemoryInfoCallback :=
    function: string
    begin
      Inc(LCount);
      Result := 'CALL-' + LCount.ToString;
    end;
  try
    FMockProvider.Clear;
    DXLog('first');
    DXLog('second');
    Assert.AreEqual(2, LCount, 'Callback should be invoked per log entry');
    Assert.AreEqual('CALL-1', FMockProvider.GetEntry(0).MemoryInfo);
    Assert.AreEqual('CALL-2', FMockProvider.GetEntry(1).MemoryInfo);

    TDXLogger.Instance.MemoryInfoCallback := nil;
    FMockProvider.Clear;
    DXLog('third');
    Assert.AreEqual(2, LCount, 'Callback must not be called after nil-assignment');
    LEntry := FMockProvider.GetLastEntry;
    Assert.AreEqual('', LEntry.MemoryInfo,
      'After nil-assignment entries must not carry MemoryInfo');
  finally
    TDXLogger.Instance.MemoryInfoCallback := nil;
  end;
end;

// A misbehaving callback must never break logging — MemoryInfo falls back
// to empty, the entry itself still reaches all providers.
procedure TDXLoggerTests.TestMemoryInfoCallbackExceptionSwallowed;
var
  LEntry: TLogEntry;
begin
  TDXLogger.Instance.MemoryInfoCallback :=
    function: string
    begin
      raise Exception.Create('boom');
    end;
  try
    FMockProvider.Clear;
    DXLog('callback-raises');
    Assert.AreEqual(1, FMockProvider.GetEntryCount,
      'Entry must still be logged even if the memory callback raises');
    LEntry := FMockProvider.GetLastEntry;
    Assert.AreEqual('', LEntry.MemoryInfo,
      'On callback failure MemoryInfo must fall back to empty');
  finally
    TDXLogger.Instance.MemoryInfoCallback := nil;
  end;
end;

{ StackInfoCallback tests }

procedure TDXLoggerTests.TestStackInfoCallbackDefaultNil;
begin
  // DXLogger.Callstack is included in this test project, so DXCallstackInstall
  // has registered the callback in initialization. Verify it is assigned.
  Assert.IsTrue(Assigned(TDXLogger.Instance.StackInfoCallback),
    'StackInfoCallback must be assigned when DXLogger.Callstack is included');
end;

procedure TDXLoggerTests.TestStackInfoCallbackPopulatesDetails;
var
  LEntry: TLogEntry;
begin
  TDXLogger.Instance.StackInfoCallback :=
    function(ALevel: TLogLevel): string
    begin
      Result := 'fake-stack';
    end;
  try
    FMockProvider.Clear;
    TDXLogger.Instance.Log('msg', TLogLevel.Error, '');
    LEntry := FMockProvider.GetLastEntry;
    Assert.AreEqual('fake-stack', LEntry.Details,
      'StackInfoCallback result must appear in Details when Details is empty');
  finally
    TDXLogger.Instance.StackInfoCallback := nil;
  end;
end;

procedure TDXLoggerTests.TestStackInfoCallbackDoesNotOverwriteExistingDetails;
var
  LEntry: TLogEntry;
begin
  TDXLogger.Instance.StackInfoCallback :=
    function(ALevel: TLogLevel): string
    begin
      Result := 'should-not-appear';
    end;
  try
    FMockProvider.Clear;
    TDXLogger.Instance.Log('msg', TLogLevel.Error, 'explicit-detail');
    LEntry := FMockProvider.GetLastEntry;
    Assert.AreEqual('explicit-detail', LEntry.Details,
      'Explicitly passed Details must never be overwritten by StackInfoCallback');
  finally
    TDXLogger.Instance.StackInfoCallback := nil;
  end;
end;

procedure TDXLoggerTests.TestStackInfoCallbackExceptionSwallowed;
var
  LEntry: TLogEntry;
begin
  TDXLogger.Instance.StackInfoCallback :=
    function(ALevel: TLogLevel): string
    begin
      raise Exception.Create('boom in callback');
    end;
  try
    FMockProvider.Clear;
    TDXLogger.Instance.Log('msg', TLogLevel.Error, '');
    Assert.AreEqual(1, FMockProvider.GetEntryCount,
      'Entry must still be logged even if StackInfoCallback raises');
    LEntry := FMockProvider.GetLastEntry;
    Assert.AreEqual('', LEntry.Details,
      'Details must be empty when StackInfoCallback raises');
  finally
    TDXLogger.Instance.StackInfoCallback := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDXLoggerTests);

end.

