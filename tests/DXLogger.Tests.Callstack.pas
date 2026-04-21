unit DXLogger.Tests.Callstack;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DX.Logger,
  DX.Logger.Tests.Core,
  DXLogger.Callstack;

type
  [TestFixture]
  TCallstackTests = class
  private
    FMock:     TMockLogProvider;
    FMockIntf: ILogProvider;
    FSavedStackCallback: TStackInfoCallback;
    FSavedMinLogLevel:   TLogLevel;
    FSavedMapFilePath:   string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestInstallSetsRTLHooks;
    [Test]
    procedure TestUninstallClearsRTLHooks;
    [Test]
    procedure TestExceptionHasNonEmptyStackTrace;
    [Test]
    procedure TestFallbackWhenNoMapFile;
    [Test]
    procedure TestReraisePrevervesOriginalStack;
    [Test]
    procedure TestDXLogErrorPopulatesDetails;
    [Test]
    procedure TestDXLogWarnDoesNotPopulateDetailsBelowMinLevel;
    [Test]
    procedure TestExplicitDetailsNotOverwritten;
    [Test]
    procedure TestDXCaptureStackReturnsNonEmpty;
    [Test]
    procedure TestThreadSafety;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Threading,
  System.SyncObjs;

procedure TCallstackTests.Setup;
begin
  FMock     := TMockLogProvider.Create;
  FMockIntf := FMock;
  TDXLogger.Instance.RegisterProvider(FMockIntf);
  TDXLogger.SetMinLevel(TLogLevel.Trace);
  FSavedMinLogLevel   := DXCallstackOptions.MinLogLevel;
  FSavedMapFilePath   := DXCallstackOptions.MapFilePath;
  // Ensure RTL hooks and StackInfoCallback are installed before saving state.
  // A previous test fixture may have cleared the callback via StackInfoCallback := nil.
  DXCallstackInstall;
  FSavedStackCallback := TDXLogger.Instance.StackInfoCallback;
end;

procedure TCallstackTests.TearDown;
begin
  TDXLogger.Instance.StackInfoCallback := FSavedStackCallback;
  DXCallstackOptions.MinLogLevel       := FSavedMinLogLevel;
  DXCallstackOptions.MapFilePath       := FSavedMapFilePath;
  DXCallstackResetMapCache;
  if Assigned(FMockIntf) then
  begin
    TDXLogger.Instance.UnregisterProvider(FMockIntf);
    FMockIntf := nil;
  end;
  FMock := nil;
end;

procedure TCallstackTests.TestInstallSetsRTLHooks;
begin
  Assert.IsTrue(Assigned(Exception.GetExceptionStackInfoProc),
    'GetExceptionStackInfoProc must be set after DXCallstackInstall');
  Assert.IsTrue(Assigned(Exception.CleanUpStackInfoProc),
    'CleanUpStackInfoProc must be set after DXCallstackInstall');
  Assert.IsTrue(Assigned(Exception.GetStackInfoStringProc),
    'GetStackInfoStringProc must be set after DXCallstackInstall');
end;

procedure TCallstackTests.TestUninstallClearsRTLHooks;
begin
  DXCallstackUninstall;
  try
    Assert.IsFalse(Assigned(Exception.GetExceptionStackInfoProc),
      'GetExceptionStackInfoProc must be nil after DXCallstackUninstall');
  finally
    DXCallstackInstall; // Restore for other tests
  end;
end;

procedure TCallstackTests.TestExceptionHasNonEmptyStackTrace;
var
  LTrace: string;
begin
  LTrace := '';
  try
    raise Exception.Create('test');
  except
    on E: Exception do
      LTrace := E.StackTrace;
  end;
  Assert.IsFalse(LTrace.IsEmpty, 'StackTrace must not be empty after exception');
end;

procedure TCallstackTests.TestFallbackWhenNoMapFile;
var
  LTrace: string;
begin
  DXCallstackOptions.MapFilePath := 'C:\does\not\exist.map';
  DXCallstackResetMapCache;
  try
    try
      raise Exception.Create('no-map-test');
    except
      on E: Exception do
        LTrace := E.StackTrace;
    end;
    Assert.IsTrue(LTrace.StartsWith('-- no call stack - map file not found --'),
      'Fallback string must appear when map file is missing');
  finally
    DXCallstackOptions.MapFilePath := '';
    DXCallstackResetMapCache;
  end;
end;

procedure TCallstackTests.TestReraisePrevervesOriginalStack;
var
  LFirstTrace, LSecondTrace: string;
begin
  LFirstTrace  := '';
  LSecondTrace := '';
  try
    try
      try
        raise Exception.Create('original');
      except
        on E: Exception do
        begin
          LFirstTrace := E.StackTrace;
          raise;
        end;
      end;
    except
      on E: Exception do
        LSecondTrace := E.StackTrace;
    end;
  except
  end;
  Assert.AreEqual(LFirstTrace, LSecondTrace,
    'Reraise must preserve the original stack trace');
end;

procedure TCallstackTests.TestDXLogErrorPopulatesDetails;
var
  LEntry: TLogEntry;
begin
  FMock.Clear;
  DXCallstackOptions.MinLogLevel := TLogLevel.Error;
  try
    raise Exception.Create('test-details');
  except
    on E: Exception do
      DXLogError(E.Message);
  end;
  Assert.AreEqual(1, FMock.GetEntryCount);
  LEntry := FMock.GetLastEntry;
  Assert.IsFalse(LEntry.Details.IsEmpty,
    'DXLogError in except block must auto-populate Details with StackTrace');
end;

procedure TCallstackTests.TestDXLogWarnDoesNotPopulateDetailsBelowMinLevel;
var
  LEntry: TLogEntry;
begin
  FMock.Clear;
  DXCallstackOptions.MinLogLevel := TLogLevel.Error;
  try
    raise Exception.Create('test-warn');
  except
    on E: Exception do
      DXLogWarn(E.Message);
  end;
  Assert.AreEqual(1, FMock.GetEntryCount);
  LEntry := FMock.GetLastEntry;
  Assert.IsTrue(LEntry.Details.IsEmpty,
    'Details must be empty for levels below MinLogLevel');
end;

procedure TCallstackTests.TestExplicitDetailsNotOverwritten;
var
  LEntry: TLogEntry;
begin
  FMock.Clear;
  DXCallstackOptions.MinLogLevel := TLogLevel.Error;
  try
    raise Exception.Create('test-explicit');
  except
    on E: Exception do
      TDXLogger.Instance.Log(E.Message, TLogLevel.Error, 'my-detail');
  end;
  LEntry := FMock.GetLastEntry;
  Assert.AreEqual('my-detail', LEntry.Details,
    'Explicitly passed Details must not be overwritten by StackInfoCallback');
end;

procedure TCallstackTests.TestDXCaptureStackReturnsNonEmpty;
var
  LStack: string;
begin
  LStack := DXCaptureStack;
  Assert.IsFalse(LStack.IsEmpty, 'DXCaptureStack must return a non-empty string');
end;

procedure TCallstackTests.TestThreadSafety;
const
  CThreads    = 20;
  CExceptions = 50;
var
  LErrors:  TList<string>;
  LLock:    TObject;
begin
  LErrors := TList<string>.Create;
  LLock   := TObject.Create;
  try
    TParallel.For(1, CThreads, procedure(AIdx: Integer)
    var
      i:      Integer;
      LTrace: string;
    begin
      for i := 1 to CExceptions do
      begin
        try
          raise Exception.CreateFmt('T%d-E%d', [AIdx, i]);
        except
          on E: Exception do
          begin
            LTrace := E.StackTrace;
            if LTrace.IsEmpty then
            begin
              TMonitor.Enter(LLock);
              try
                LErrors.Add(Format('Thread %d exception %d: empty trace', [AIdx, i]));
              finally
                TMonitor.Exit(LLock);
              end;
            end;
          end;
        end;
      end;
    end);
    Assert.AreEqual(0, LErrors.Count,
      'No thread must produce an empty or corrupt stack trace: ' +
      string.Join(', ', LErrors.ToArray));
  finally
    LErrors.Free;
    LLock.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCallstackTests);

end.
