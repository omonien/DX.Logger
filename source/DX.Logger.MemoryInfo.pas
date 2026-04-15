unit DX.Logger.MemoryInfo;

{
  DX.Logger.MemoryInfo - Cross-Platform Memory-Pressure Helper for DX.Logger

  Copyright (c) 2025 Olaf Monien
  SPDX-License-Identifier: MIT

  One-liner usage — register as MemoryInfoCallback on TDXLogger:

      uses
        DX.Logger,
        DX.Logger.MemoryInfo;

      begin
        EnableMemoryInfo;              // default 500 ms cache
        // or: EnableMemoryInfo(1000); // custom cache interval
        ...
      end.

  Provides a short memory snapshot (e.g. "WS:45MB PB:22MB") which DX.Logger's
  standard providers render between [Thread:N] and the message. The snapshot
  is cached to keep high-frequency logging cheap.

  Platform coverage:
    Windows          — GetProcessMemoryInfo (WorkingSet + PagefileUsage)
    macOS / iOS      — mach_task_basic_info (resident_size + virtual_size)
    Linux / Android  — /proc/self/status   (VmRSS + VmSize)

  Non-listed platforms fall back to a benign empty snapshot so the logger
  keeps running. See TProcessMemoryMonitor.IsSupported to detect this case
  at runtime.
}

interface

uses
  System.SysUtils;

type
  /// <summary>
  /// Snapshot of current-process memory usage. All values in bytes.
  /// PeakWorkingSet is filled on platforms where the OS tracks it
  /// (Windows only at the moment); otherwise equal to WorkingSet.
  /// </summary>
  TProcessMemorySnapshot = record
    WorkingSet: UInt64;
    PeakWorkingSet: UInt64;
    PrivateBytes: UInt64;
    Timestamp: TDateTime;
    /// <summary>Compact form for log lines, e.g. "WS:45MB PB:22MB".</summary>
    function ToShortString: string;
    /// <summary>Readable form for UIs, e.g.
    /// "Working Set: 1.2 GB (Peak 1.4 GB) | Private: 987 MB".</summary>
    function ToDisplayString: string;
  end;

  /// <summary>
  /// Queries the current process' memory footprint. The last snapshot is
  /// cached (default 500 ms) so high-frequency log calls do not hit the
  /// OS each time. Thread-safe.
  /// </summary>
  TProcessMemoryMonitor = class
  private
    class var FCachedSnapshot: TProcessMemorySnapshot;
    class var FCacheLock: TObject;
    class var FCacheIntervalMs: Integer;
    class constructor Create;
    class destructor Destroy;
    class function QueryNow: TProcessMemorySnapshot; static;
  public
    /// <summary>True when the current platform has a real implementation.
    /// On unsupported platforms GetSnapshot returns zero values.</summary>
    class function IsSupported: Boolean; static;
    /// <summary>Cache-Intervall in ms (default 500).</summary>
    class property CacheIntervalMs: Integer read FCacheIntervalMs write FCacheIntervalMs;
    /// <summary>Current (possibly cached) snapshot.</summary>
    class function GetSnapshot: TProcessMemorySnapshot; static;
    /// <summary>Force a fresh OS query and refresh the cache.</summary>
    class function GetFreshSnapshot: TProcessMemorySnapshot; static;
  end;

/// <summary>
/// Install TProcessMemoryMonitor.GetSnapshot.ToShortString as the
/// memory-info callback on TDXLogger.Instance. From now on every log entry
/// carries a short memory snippet that the providers render between
/// [Thread:N] and the message.
/// </summary>
procedure EnableMemoryInfo(ACacheIntervalMs: Integer = 500);

/// <summary>
/// Remove the memory-info callback (subsequent log entries will not carry
/// MemoryInfo). The monitor cache itself stays intact.
/// </summary>
procedure DisableMemoryInfo;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.PsAPI,
{$ENDIF}
{$IFDEF MACOS}
  Macapi.Mach,
{$ENDIF}
{$IFDEF POSIX}
  Posix.Unistd,
  System.Classes,
{$ENDIF}
  System.DateUtils,
  DX.Logger;

{ TProcessMemorySnapshot }

function FormatBytes(ABytes: UInt64): string;
const
  CKB = UInt64(1024);
  CMB = CKB * 1024;
  CGB = CMB * 1024;
begin
  if ABytes >= CGB then
    Result := Format('%.2f GB', [ABytes / CGB])
  else if ABytes >= CMB then
    Result := Format('%d MB', [ABytes div CMB])
  else if ABytes >= CKB then
    Result := Format('%d KB', [ABytes div CKB])
  else
    Result := Format('%d B', [ABytes]);
end;

function TProcessMemorySnapshot.ToShortString: string;
begin
  Result := Format('WS:%dMB PB:%dMB',
    [WorkingSet div (1024 * 1024), PrivateBytes div (1024 * 1024)]);
end;

function TProcessMemorySnapshot.ToDisplayString: string;
begin
  Result := Format('Working Set: %s (Peak %s) | Private: %s',
    [FormatBytes(WorkingSet), FormatBytes(PeakWorkingSet), FormatBytes(PrivateBytes)]);
end;

{ TProcessMemoryMonitor }

class constructor TProcessMemoryMonitor.Create;
begin
  FCacheLock := TObject.Create;
  FCacheIntervalMs := 500;
  FCachedSnapshot := Default(TProcessMemorySnapshot);
end;

class destructor TProcessMemoryMonitor.Destroy;
begin
  FCacheLock.Free;
end;

class function TProcessMemoryMonitor.IsSupported: Boolean;
begin
{$IF defined(MSWINDOWS) or defined(MACOS) or defined(LINUX) or defined(ANDROID)}
  Result := True;
{$ELSE}
  Result := False;
{$ENDIF}
end;

{$IFDEF POSIX}
// Read /proc/self/status — used on Linux and Android.
// Extracts VmRSS (resident / working set) and VmSize (virtual / private).
function ReadProcSelfStatus(out AWorkingSet, APrivateBytes: UInt64): Boolean;
var
  LLines: TStringList;
  LLine, LKey: string;
  LColon: Integer;
  LKB: Int64;
begin
  Result := False;
  AWorkingSet := 0;
  APrivateBytes := 0;
  LLines := TStringList.Create;
  try
    try
      LLines.LoadFromFile('/proc/self/status');
    except
      Exit;
    end;
    for LLine in LLines do
    begin
      LColon := Pos(':', LLine);
      if LColon <= 0 then
        Continue;
      LKey := Copy(LLine, 1, LColon - 1);
      // Values look like "VmRSS:\t   12345 kB"
      if (LKey = 'VmRSS') or (LKey = 'VmSize') then
      begin
        var LRest: string := Trim(Copy(LLine, LColon + 1, MaxInt));
        // Strip trailing " kB"
        var LSpace: Integer := Pos(' ', LRest);
        if LSpace > 0 then
          LRest := Copy(LRest, 1, LSpace - 1);
        if TryStrToInt64(LRest, LKB) then
        begin
          if LKey = 'VmRSS' then
            AWorkingSet := UInt64(LKB) * 1024
          else
            APrivateBytes := UInt64(LKB) * 1024;
        end;
      end;
    end;
    Result := AWorkingSet > 0;
  finally
    LLines.Free;
  end;
end;
{$ENDIF}

class function TProcessMemoryMonitor.QueryNow: TProcessMemorySnapshot;
{$IFDEF MSWINDOWS}
var
  LCounters: PROCESS_MEMORY_COUNTERS;
begin
  Result := Default(TProcessMemorySnapshot);
  Result.Timestamp := Now;
  FillChar(LCounters, SizeOf(LCounters), 0);
  LCounters.cb := SizeOf(LCounters);
  if GetProcessMemoryInfo(GetCurrentProcess, @LCounters, SizeOf(LCounters)) then
  begin
    Result.WorkingSet := LCounters.WorkingSetSize;
    Result.PeakWorkingSet := LCounters.PeakWorkingSetSize;
    Result.PrivateBytes := LCounters.PagefileUsage;
  end;
end;
{$ELSE}
{$IFDEF MACOS}
var
  LInfo: mach_task_basic_info;
  LCount: mach_msg_type_number_t;
  LKR: kern_return_t;
begin
  Result := Default(TProcessMemorySnapshot);
  Result.Timestamp := Now;
  LCount := MACH_TASK_BASIC_INFO_COUNT;
  LKR := task_info(mach_task_self_, MACH_TASK_BASIC_INFO, @LInfo, LCount);
  if LKR = KERN_SUCCESS then
  begin
    Result.WorkingSet := LInfo.resident_size;
    Result.PeakWorkingSet := LInfo.resident_size_max;
    Result.PrivateBytes := LInfo.virtual_size;
  end;
end;
{$ELSE}
{$IF defined(LINUX) or defined(ANDROID)}
var
  LWS, LPB: UInt64;
begin
  Result := Default(TProcessMemorySnapshot);
  Result.Timestamp := Now;
  if ReadProcSelfStatus(LWS, LPB) then
  begin
    Result.WorkingSet := LWS;
    Result.PeakWorkingSet := LWS; // no separate peak on /proc/self/status without VmHWM
    Result.PrivateBytes := LPB;
  end;
end;
{$ELSE}
begin
  // Unsupported platform — return an empty snapshot so logging stays safe.
  Result := Default(TProcessMemorySnapshot);
  Result.Timestamp := Now;
end;
{$ENDIF}
{$ENDIF}
{$ENDIF}

class function TProcessMemoryMonitor.GetSnapshot: TProcessMemorySnapshot;
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

class function TProcessMemoryMonitor.GetFreshSnapshot: TProcessMemorySnapshot;
begin
  TMonitor.Enter(FCacheLock);
  try
    FCachedSnapshot := QueryNow;
    Result := FCachedSnapshot;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

{ Public API }

procedure EnableMemoryInfo(ACacheIntervalMs: Integer);
begin
  TProcessMemoryMonitor.CacheIntervalMs := ACacheIntervalMs;
  TDXLogger.Instance.MemoryInfoCallback :=
    function: string
    begin
      Result := TProcessMemoryMonitor.GetSnapshot.ToShortString;
    end;
end;

procedure DisableMemoryInfo;
begin
  TDXLogger.Instance.MemoryInfoCallback := nil;
end;

end.
