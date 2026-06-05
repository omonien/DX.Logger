unit DX.Logger.Tests.SystemInfo;

interface

uses
  DUnitX.TestFramework, DX.Logger.SystemInfo;

type
  [TestFixture]
  TSystemInfoTests = class
  public
    [Test] procedure Snapshot_HasPlausibleValues;
    [Test] procedure ToLogLine_NotEmpty;
  end;

implementation

procedure TSystemInfoTests.Snapshot_HasPlausibleValues;
var
  LSnap: TSystemInfoSnapshot;
begin
  LSnap := TSystemInfo.GetSnapshot;
{$IFDEF MSWINDOWS}
  Assert.IsTrue(LSnap.LogicalProcessors > 0, 'logical cores > 0');
  Assert.IsTrue(LSnap.TotalPhysMB > 0, 'RAM > 0');
  Assert.IsTrue((LSnap.ProcessBitness = 'Win32') or (LSnap.ProcessBitness = 'Win64'));
{$ENDIF}
end;

procedure TSystemInfoTests.ToLogLine_NotEmpty;
var
  LSnap: TSystemInfoSnapshot;
begin
  LSnap := TSystemInfo.GetSnapshot;
  Assert.IsTrue(LSnap.ToLogLine <> '');
  Assert.IsTrue(Length(LSnap.ToProperties) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TSystemInfoTests);

end.
