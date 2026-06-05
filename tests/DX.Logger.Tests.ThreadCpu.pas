unit DX.Logger.Tests.ThreadCpu;

interface

uses
  DUnitX.TestFramework, System.Generics.Collections, DX.Logger.ThreadCpu;

type
  [TestFixture]
  TThreadCpuMonitorTests = class
  public
    [Test] procedure TopByDelta_OrdersDescendingByDelta;
    [Test] procedure TopByDelta_NewThreadWithoutPriorCountsZero;
    [Test] procedure TopByDelta_PercentRelativeToSystemDelta;
    [Test] procedure GetTopThreads_ReturnsAtMostN;
  end;

implementation

function Ticks(AId: Cardinal; AT: UInt64): TThreadTicks;
begin
  Result.ThreadId := AId;
  Result.Ticks := AT;
end;

procedure TThreadCpuMonitorTests.TopByDelta_OrdersDescendingByDelta;
var
  LPrior: TDictionary<Cardinal, UInt64>;
  LCur: TArray<TThreadTicks>;
  LTop: TArray<TThreadCpuSample>;
begin
  LPrior := TDictionary<Cardinal, UInt64>.Create;
  try
    LPrior.Add(1, 100); LPrior.Add(2, 100); LPrior.Add(3, 100);
    LCur := [Ticks(1, 110), Ticks(2, 200), Ticks(3, 150)]; // Deltas: 10, 100, 50
    LTop := TThreadCpuMonitor.SelectTopByDelta(LCur, LPrior, 1000, 3);
    Assert.AreEqual<Cardinal>(2, LTop[0].ThreadId, 'hottest first');
    Assert.AreEqual<Cardinal>(3, LTop[1].ThreadId);
    Assert.AreEqual<Cardinal>(1, LTop[2].ThreadId);
  finally
    LPrior.Free;
  end;
end;

procedure TThreadCpuMonitorTests.TopByDelta_NewThreadWithoutPriorCountsZero;
var
  LPrior: TDictionary<Cardinal, UInt64>;
  LTop: TArray<TThreadCpuSample>;
begin
  // Thread 1 hat ein echtes Delta (60), Thread 9 ist neu (kein Prior -> Delta 0).
  // Damit ist die Reihenfolge deterministisch (1 vor 9) und 9 muss 0% zeigen.
  LPrior := TDictionary<Cardinal, UInt64>.Create;
  try
    LPrior.Add(1, 100);
    LTop := TThreadCpuMonitor.SelectTopByDelta([Ticks(1, 160), Ticks(9, 9999)], LPrior, 1000, 2);
    Assert.AreEqual<Cardinal>(1, LTop[0].ThreadId, 'thread with real delta first');
    Assert.AreEqual<Cardinal>(9, LTop[1].ThreadId, 'new thread (no prior) last');
    Assert.AreEqual<Double>(0, LTop[1].CpuPercent, 'new thread without prior counts as 0%');
  finally
    LPrior.Free;
  end;
end;

procedure TThreadCpuMonitorTests.TopByDelta_PercentRelativeToSystemDelta;
var
  LPrior: TDictionary<Cardinal, UInt64>;
  LTop: TArray<TThreadCpuSample>;
begin
  LPrior := TDictionary<Cardinal, UInt64>.Create;
  try
    LPrior.Add(1, 0);
    LTop := TThreadCpuMonitor.SelectTopByDelta([Ticks(1, 50)], LPrior, 100, 1);
    Assert.AreEqual<Double>(50, LTop[0].CpuPercent, 'delta 50 of system 100 = 50%');
  finally
    LPrior.Free;
  end;
end;

procedure TThreadCpuMonitorTests.GetTopThreads_ReturnsAtMostN;
var
  LTop: TArray<TThreadCpuSample>;
begin
  TThreadCpuMonitor.ResetPriorSample;
  TThreadCpuMonitor.GetTopThreads(3);   // seed
  LTop := TThreadCpuMonitor.GetTopThreads(3);
  Assert.IsTrue(Length(LTop) <= 3, 'never more than N');
end;

initialization
  TDUnitX.RegisterTestFixture(TThreadCpuMonitorTests);

end.
