unit DX.Logger.Tests.CpuInfo;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  DX.Logger.SystemInfo;

type
  [TestFixture]
  TProcessCpuMonitorTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestIsSupportedOnThisPlatform;
    [Test]
    procedure TestFirstSnapshotIsZeroByDesign;
    [Test]
    procedure TestSnapshotHasPlausibleValuesAfterWorkload;
    [Test]
    procedure TestShortStringFormat;
    [Test]
    procedure TestDisplayStringFormat;
    [Test]
    procedure TestCachingSuppressesRepeatedQueries;
    [Test]
    procedure TestFreshSnapshotBypassesCache;
    [Test]
    procedure TestPercentagesClampedToHundred;
  end;

implementation

{ TProcessCpuMonitorTests }

procedure TProcessCpuMonitorTests.Setup;
begin
  TProcessCpuMonitor.CacheIntervalMs := 500;
  TProcessCpuMonitor.ResetPriorSample;
end;

procedure TProcessCpuMonitorTests.TearDown;
begin
  TProcessCpuMonitor.CacheIntervalMs := 500;
  TProcessCpuMonitor.ResetPriorSample;
end;

procedure TProcessCpuMonitorTests.TestIsSupportedOnThisPlatform;
begin
{$IFDEF MSWINDOWS}
  Assert.IsTrue(TProcessCpuMonitor.IsSupported,
    'IsSupported must be True on Windows');
{$ELSE}
  Assert.IsFalse(TProcessCpuMonitor.IsSupported,
    'IsSupported is currently False on non-Windows platforms');
{$ENDIF}
end;

// CPU is a delta. The very first snapshot has no prior reference and must
// therefore report 0% — that's by design, not a bug. Consumers should
// expect to discard or ignore the first reading.
procedure TProcessCpuMonitorTests.TestFirstSnapshotIsZeroByDesign;
var
  LSnap: TProcessCpuSnapshot;
begin
  LSnap := TProcessCpuMonitor.GetFreshSnapshot;
  Assert.AreEqual<Double>(0, LSnap.ProcessCpuPercent,
    'First snapshot must report 0% (no prior sample yet)');
  Assert.AreEqual<Double>(0, LSnap.SystemCpuPercent,
    'First snapshot must report 0% (no prior sample yet)');
  Assert.IsTrue(LSnap.Timestamp > 0, 'Timestamp must be set');
end;

procedure TProcessCpuMonitorTests.TestSnapshotHasPlausibleValuesAfterWorkload;
var
  LSnap: TProcessCpuSnapshot;
  LX: Double;
  I: Integer;
begin
  // Seed the prior-sample reference.
  TProcessCpuMonitor.GetFreshSnapshot;

  // Do ~100 ms of CPU-bound work so the second sample sees a non-zero process delta.
  LX := 1.0;
  for I := 1 to 10000000 do
    LX := LX * 1.0000001 + 0.5;
  if LX = 0 then  // Touch LX so the compiler doesn't optimize the loop away.
    Sleep(0);

  LSnap := TProcessCpuMonitor.GetFreshSnapshot;
  if TProcessCpuMonitor.IsSupported then
  begin
    Assert.IsTrue(LSnap.ProcessCpuPercent >= 0,
      'ProcessCpuPercent must be >= 0');
    Assert.IsTrue(LSnap.ProcessCpuPercent <= 100,
      'ProcessCpuPercent must be <= 100');
    Assert.IsTrue(LSnap.SystemCpuPercent >= 0,
      'SystemCpuPercent must be >= 0');
    Assert.IsTrue(LSnap.SystemCpuPercent <= 100,
      'SystemCpuPercent must be <= 100');
  end
  else
    Assert.AreEqual<Double>(0, LSnap.ProcessCpuPercent,
      'Unsupported platforms return a zeroed snapshot');

  Assert.IsTrue(LSnap.Timestamp > 0, 'Timestamp must be set');
end;

procedure TProcessCpuMonitorTests.TestShortStringFormat;
var
  LSnap: TProcessCpuSnapshot;
begin
  LSnap := Default(TProcessCpuSnapshot);
  LSnap.ProcessCpuPercent := 78.0;
  LSnap.SystemCpuPercent := 81.0;
  Assert.AreEqual('P:78% S:81%', LSnap.ToShortString);
end;

procedure TProcessCpuMonitorTests.TestDisplayStringFormat;
var
  LSnap: TProcessCpuSnapshot;
  LResult: string;
begin
  LSnap := Default(TProcessCpuSnapshot);
  LSnap.ProcessCpuPercent := 12.5;
  LSnap.SystemCpuPercent := 34.7;
  LResult := LSnap.ToDisplayString;
  Assert.Contains(LResult, 'Process CPU');
  Assert.Contains(LResult, 'System CPU');
  Assert.Contains(LResult, '12');
  Assert.Contains(LResult, '34');
end;

procedure TProcessCpuMonitorTests.TestCachingSuppressesRepeatedQueries;
var
  LFirst, LSecond: TProcessCpuSnapshot;
begin
  TProcessCpuMonitor.CacheIntervalMs := 60 * 1000;
  LFirst := TProcessCpuMonitor.GetFreshSnapshot;
  Sleep(15);
  LSecond := TProcessCpuMonitor.GetSnapshot;
  Assert.AreEqual<TDateTime>(LFirst.Timestamp, LSecond.Timestamp,
    'Within the cache window GetSnapshot must return the cached value');
end;

procedure TProcessCpuMonitorTests.TestFreshSnapshotBypassesCache;
var
  LFirst, LSecond: TProcessCpuSnapshot;
begin
  TProcessCpuMonitor.CacheIntervalMs := 60 * 1000;
  LFirst := TProcessCpuMonitor.GetFreshSnapshot;
  Sleep(15);
  LSecond := TProcessCpuMonitor.GetFreshSnapshot;
  Assert.IsTrue(LSecond.Timestamp > LFirst.Timestamp,
    'GetFreshSnapshot must ignore the cache and re-query');
end;

procedure TProcessCpuMonitorTests.TestPercentagesClampedToHundred;
var
  LSnap: TProcessCpuSnapshot;
  I: Integer;
begin
  // Even under heavy load percentages must stay in [0,100]. We don't try
  // to provoke an overflow here — we just exercise the clamping path with
  // a normal sample and assert the invariants every consumer relies on.
  TProcessCpuMonitor.GetFreshSnapshot;
  for I := 1 to 1000000 do ;
  LSnap := TProcessCpuMonitor.GetFreshSnapshot;
  Assert.IsTrue((LSnap.ProcessCpuPercent >= 0) and (LSnap.ProcessCpuPercent <= 100));
  Assert.IsTrue((LSnap.SystemCpuPercent >= 0) and (LSnap.SystemCpuPercent <= 100));
end;

initialization
  TDUnitX.RegisterTestFixture(TProcessCpuMonitorTests);

end.
