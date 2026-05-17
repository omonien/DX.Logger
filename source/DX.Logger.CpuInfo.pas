unit DX.Logger.CpuInfo;

{
  DX.Logger.CpuInfo - Cross-Platform CPU-Pressure Helper for DX.Logger

  Copyright (c) 2026 Olaf Monien
  SPDX-License-Identifier: MIT

  Provides a short CPU-usage snapshot (e.g. "P:78% S:81%") that callers can
  attach to log lines or heartbeat messages alongside the existing
  MemoryInfo data. Cached (500 ms by default) so high-frequency log calls do
  not hit the OS each time.

  CPU percentages are necessarily relative to a delta between two samples.
  Callers should not expect a meaningful reading before the second
  GetSnapshot call has been served (the first sample returns 0 because no
  prior reference point exists yet).

  Platform coverage:
    Windows          — GetProcessTimes + GetSystemTimes diff
    macOS / Linux    — return zero today (no impl), callers see "P:0% S:0%"

  Non-Windows platforms still produce a benign zeroed snapshot so callers
  keep working. Use TProcessCpuMonitor.IsSupported to detect the case at
  runtime.
}

interface

uses
  System.SysUtils;

type
  /// <summary>
  /// Snapshot of current-process and system-wide CPU usage as percentages
  /// [0..100]. PercentProcess is the share of total available CPU time
  /// (across all cores) consumed by THIS process since the prior sample;
  /// PercentSystem is the busy share of all cores.
  /// </summary>
  TProcessCpuSnapshot = record
    ProcessCpuPercent: Double;
    SystemCpuPercent: Double;
    Timestamp: TDateTime;
    /// <summary>Compact form for log lines, e.g. "P:78% S:81%".</summary>
    function ToShortString: string;
    /// <summary>Readable form for UIs.</summary>
    function ToDisplayString: string;
  end;

  /// <summary>
  /// Queries process- and system-CPU usage. Two samples are needed for a
  /// meaningful percentage; the first call seeds the reference point and
  /// returns zero. Snapshots are cached (default 500 ms). Thread-safe.
  /// </summary>
  TProcessCpuMonitor = class
  private
    class var FCacheLock: TObject;
    class var FCacheIntervalMs: Integer;
    class var FCachedSnapshot: TProcessCpuSnapshot;
    class var FHasPriorSample: Boolean;
    class var FPriorProcessTicks: UInt64;
    class var FPriorSystemTotalTicks: UInt64;
    class var FPriorSystemIdleTicks: UInt64;
    class constructor Create;
    class destructor Destroy;
    class function QueryNow: TProcessCpuSnapshot; static;
  public
    /// <summary>True when the current platform has a real implementation.</summary>
    class function IsSupported: Boolean; static;
    /// <summary>Cache interval in ms (default 500).</summary>
    class property CacheIntervalMs: Integer read FCacheIntervalMs write FCacheIntervalMs;
    /// <summary>Current (possibly cached) snapshot.</summary>
    class function GetSnapshot: TProcessCpuSnapshot; static;
    /// <summary>Force a fresh OS query and refresh the cache.</summary>
    class function GetFreshSnapshot: TProcessCpuSnapshot; static;
    /// <summary>Reset the prior-sample reference. Test hook.</summary>
    class procedure ResetPriorSample; static;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  System.DateUtils;

{ TProcessCpuSnapshot }

function TProcessCpuSnapshot.ToShortString: string;
begin
  Result := Format('P:%d%% S:%d%%',
    [Round(ProcessCpuPercent), Round(SystemCpuPercent)]);
end;

function TProcessCpuSnapshot.ToDisplayString: string;
begin
  Result := Format('Process CPU: %.1f%% | System CPU: %.1f%%',
    [ProcessCpuPercent, SystemCpuPercent]);
end;

{ TProcessCpuMonitor }

class constructor TProcessCpuMonitor.Create;
begin
  FCacheLock := TObject.Create;
  FCacheIntervalMs := 500;
  FCachedSnapshot := Default(TProcessCpuSnapshot);
  FHasPriorSample := False;
end;

class destructor TProcessCpuMonitor.Destroy;
begin
  FCacheLock.Free;
end;

class function TProcessCpuMonitor.IsSupported: Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := True;
{$ELSE}
  Result := False;
{$ENDIF}
end;

class procedure TProcessCpuMonitor.ResetPriorSample;
begin
  TMonitor.Enter(FCacheLock);
  try
    FHasPriorSample := False;
    FCachedSnapshot := Default(TProcessCpuSnapshot);
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

{$IFDEF MSWINDOWS}
function FileTimeToUInt64(const AFileTime: TFileTime): UInt64; inline;
begin
  Result := (UInt64(AFileTime.dwHighDateTime) shl 32) or UInt64(AFileTime.dwLowDateTime);
end;
{$ENDIF}

class function TProcessCpuMonitor.QueryNow: TProcessCpuSnapshot;
{$IFDEF MSWINDOWS}
var
  LCreate, LExit, LKernelProc, LUserProc: TFileTime;
  LIdleSys, LKernelSys, LUserSys: TFileTime;
  LProcessTicks, LSystemTotal, LSystemIdle: UInt64;
  LDeltaProcess, LDeltaSystem, LDeltaIdle: Int64;
begin
  Result := Default(TProcessCpuSnapshot);
  Result.Timestamp := Now;

  if not GetProcessTimes(GetCurrentProcess, LCreate, LExit, LKernelProc, LUserProc) then
    Exit;
  if not GetSystemTimes(LIdleSys, LKernelSys, LUserSys) then
    Exit;

  // On Windows, "Kernel" time INCLUDES idle time, so total available CPU
  // ticks across all cores in the sample interval = Kernel + User.
  LProcessTicks := FileTimeToUInt64(LKernelProc) + FileTimeToUInt64(LUserProc);
  LSystemTotal  := FileTimeToUInt64(LKernelSys) + FileTimeToUInt64(LUserSys);
  LSystemIdle   := FileTimeToUInt64(LIdleSys);

  if FHasPriorSample then
  begin
    LDeltaProcess := Int64(LProcessTicks - FPriorProcessTicks);
    LDeltaSystem  := Int64(LSystemTotal  - FPriorSystemTotalTicks);
    LDeltaIdle    := Int64(LSystemIdle   - FPriorSystemIdleTicks);

    if LDeltaSystem > 0 then
    begin
      Result.ProcessCpuPercent := (LDeltaProcess * 100.0) / LDeltaSystem;
      Result.SystemCpuPercent  := ((LDeltaSystem - LDeltaIdle) * 100.0) / LDeltaSystem;
    end;

    if Result.ProcessCpuPercent < 0 then Result.ProcessCpuPercent := 0
    else if Result.ProcessCpuPercent > 100 then Result.ProcessCpuPercent := 100;
    if Result.SystemCpuPercent < 0 then Result.SystemCpuPercent := 0
    else if Result.SystemCpuPercent > 100 then Result.SystemCpuPercent := 100;
  end;

  FPriorProcessTicks      := LProcessTicks;
  FPriorSystemTotalTicks  := LSystemTotal;
  FPriorSystemIdleTicks   := LSystemIdle;
  FHasPriorSample := True;
end;
{$ELSE}
begin
  Result := Default(TProcessCpuSnapshot);
  Result.Timestamp := Now;
end;
{$ENDIF}

class function TProcessCpuMonitor.GetSnapshot: TProcessCpuSnapshot;
var
  LAgeMs: Int64;
begin
  TMonitor.Enter(FCacheLock);
  try
    if FCachedSnapshot.Timestamp = 0 then
      LAgeMs := MaxInt
    else
      LAgeMs := MilliSecondsBetween(Now, FCachedSnapshot.Timestamp);

    if LAgeMs >= FCacheIntervalMs then
      FCachedSnapshot := QueryNow;

    Result := FCachedSnapshot;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

class function TProcessCpuMonitor.GetFreshSnapshot: TProcessCpuSnapshot;
begin
  TMonitor.Enter(FCacheLock);
  try
    FCachedSnapshot := QueryNow;
    Result := FCachedSnapshot;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

end.
