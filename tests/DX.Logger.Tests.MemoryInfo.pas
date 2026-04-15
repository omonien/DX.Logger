unit DX.Logger.Tests.MemoryInfo;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  DX.Logger,
  DX.Logger.MemoryInfo;

type
  [TestFixture]
  TProcessMemoryMonitorTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestIsSupportedOnThisPlatform;
    [Test]
    procedure TestSnapshotHasPlausibleValues;
    [Test]
    procedure TestShortStringFormat;
    [Test]
    procedure TestDisplayStringFormat;
    [Test]
    procedure TestCachingSuppressesRepeatedQueries;
    [Test]
    procedure TestFreshSnapshotBypassesCache;

    [Test]
    procedure TestEnableMemoryInfoInstallsCallback;
    [Test]
    procedure TestDisableMemoryInfoRemovesCallback;
    [Test]
    procedure TestEnabledCallbackProducesPattern;
  end;

implementation

{ TProcessMemoryMonitorTests }

procedure TProcessMemoryMonitorTests.Setup;
begin
  // Ensure no callback from previous tests leaks into this fixture.
  TDXLogger.Instance.MemoryInfoCallback := nil;
end;

procedure TProcessMemoryMonitorTests.TearDown;
begin
  TDXLogger.Instance.MemoryInfoCallback := nil;
  TProcessMemoryMonitor.CacheIntervalMs := 500;
end;

// Anchor: on the platforms DX.Logger ships implementations for we expect
// IsSupported = True. On unsupported platforms the call must still be safe
// and return False.
procedure TProcessMemoryMonitorTests.TestIsSupportedOnThisPlatform;
begin
{$IF defined(MSWINDOWS) or defined(MACOS) or defined(LINUX) or defined(ANDROID)}
  Assert.IsTrue(TProcessMemoryMonitor.IsSupported,
    'IsSupported must be True on Windows/macOS/Linux/Android');
{$ELSE}
  Assert.IsFalse(TProcessMemoryMonitor.IsSupported,
    'IsSupported must be False on unhandled platforms');
{$ENDIF}
end;

procedure TProcessMemoryMonitorTests.TestSnapshotHasPlausibleValues;
var
  LSnap: TProcessMemorySnapshot;
begin
  LSnap := TProcessMemoryMonitor.GetFreshSnapshot;

  if TProcessMemoryMonitor.IsSupported then
  begin
    Assert.IsTrue(LSnap.WorkingSet > 0,
      'WorkingSet must be > 0 on supported platforms');
    Assert.IsTrue(LSnap.PrivateBytes > 0,
      'PrivateBytes must be > 0 on supported platforms');
    Assert.IsTrue(LSnap.PeakWorkingSet >= LSnap.WorkingSet,
      'PeakWorkingSet must be >= WorkingSet');
  end
  else
    Assert.AreEqual<UInt64>(0, LSnap.WorkingSet,
      'Unsupported platforms return a zeroed snapshot');

  Assert.IsTrue(LSnap.Timestamp > 0, 'Timestamp must be set');
end;

procedure TProcessMemoryMonitorTests.TestShortStringFormat;
var
  LSnap: TProcessMemorySnapshot;
begin
  LSnap := Default(TProcessMemorySnapshot);
  LSnap.WorkingSet := UInt64(45) * 1024 * 1024;
  LSnap.PrivateBytes := UInt64(22) * 1024 * 1024;
  Assert.AreEqual('WS:45MB PB:22MB', LSnap.ToShortString);
end;

procedure TProcessMemoryMonitorTests.TestDisplayStringFormat;
var
  LSnap: TProcessMemorySnapshot;
  LResult: string;
begin
  LSnap := Default(TProcessMemorySnapshot);
  LSnap.WorkingSet := UInt64(1500) * 1024 * 1024;       // 1500 MB -> 1.46 GB
  LSnap.PeakWorkingSet := UInt64(1700) * 1024 * 1024;   // 1700 MB -> 1.66 GB
  LSnap.PrivateBytes := UInt64(800) * 1024 * 1024;      // 800 MB
  LResult := LSnap.ToDisplayString;
  // Format: "Working Set: 1.46 GB (Peak 1.66 GB) | Private: 800 MB"
  Assert.Contains(LResult, 'Working Set');
  Assert.Contains(LResult, 'GB');
  Assert.Contains(LResult, '800 MB');
  Assert.Contains(LResult, 'Peak');
end;

// GetSnapshot should reuse the cached value for repeated calls within the
// cache window. We prove that by observing a stable timestamp across calls
// with a long cache interval.
procedure TProcessMemoryMonitorTests.TestCachingSuppressesRepeatedQueries;
var
  LFirst, LSecond: TProcessMemorySnapshot;
begin
  TProcessMemoryMonitor.CacheIntervalMs := 60 * 1000; // 60s — effectively disables refresh during the test
  LFirst := TProcessMemoryMonitor.GetFreshSnapshot;   // seed cache
  Sleep(15);
  LSecond := TProcessMemoryMonitor.GetSnapshot;
  Assert.AreEqual<TDateTime>(LFirst.Timestamp, LSecond.Timestamp,
    'Within the cache window GetSnapshot must return the cached value');
end;

procedure TProcessMemoryMonitorTests.TestFreshSnapshotBypassesCache;
var
  LCached, LFresh: TProcessMemorySnapshot;
begin
  TProcessMemoryMonitor.CacheIntervalMs := 60 * 1000;
  LCached := TProcessMemoryMonitor.GetFreshSnapshot;
  Sleep(15);
  LFresh := TProcessMemoryMonitor.GetFreshSnapshot;
  Assert.IsTrue(LFresh.Timestamp > LCached.Timestamp,
    'GetFreshSnapshot must ignore the cache and re-query');
end;

procedure TProcessMemoryMonitorTests.TestEnableMemoryInfoInstallsCallback;
begin
  EnableMemoryInfo(500);
  Assert.IsTrue(Assigned(TDXLogger.Instance.MemoryInfoCallback),
    'EnableMemoryInfo must install a callback on TDXLogger');
end;

procedure TProcessMemoryMonitorTests.TestDisableMemoryInfoRemovesCallback;
begin
  EnableMemoryInfo;
  Assert.IsTrue(Assigned(TDXLogger.Instance.MemoryInfoCallback));
  DisableMemoryInfo;
  Assert.IsFalse(Assigned(TDXLogger.Instance.MemoryInfoCallback),
    'DisableMemoryInfo must remove the callback');
end;

// End-to-end sanity: after EnableMemoryInfo the callback returns a string
// shaped like "WS:<n>MB PB:<n>MB" on supported platforms, or an empty
// string on unsupported ones.
procedure TProcessMemoryMonitorTests.TestEnabledCallbackProducesPattern;
var
  LCb: TMemoryInfoCallback;
  LValue: string;
begin
  EnableMemoryInfo;
  LCb := TDXLogger.Instance.MemoryInfoCallback;
  Assert.IsTrue(Assigned(LCb));
  LValue := LCb();
  if TProcessMemoryMonitor.IsSupported then
  begin
    Assert.StartsWith('WS:', LValue);
    Assert.Contains(LValue, 'MB PB:');
    Assert.EndsWith('MB', LValue);
  end
  else
  begin
    Assert.AreEqual('WS:0MB PB:0MB', LValue,
      'On unsupported platforms the short string still renders with zero values');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TProcessMemoryMonitorTests);

end.
