unit DX.Logger.SystemInfo;

{
  DX.Logger.SystemInfo - Consolidated Process/System Introspection for DX.Logger

  Copyright (c) 2026 Olaf Monien
  SPDX-License-Identifier: MIT

  Bündelt die frühere DX.Logger.CpuInfo und DX.Logger.MemoryInfo (BREAKING:
  beide Units entfallen) und ergänzt statische System-Konfiguration (CPU-Cores,
  RAM, OS, Bitness, VM-Hinweis) für ein einmaliges Startup-Log.

  Die per-Thread-CPU-Diagnose (SuspendThread/GetThreadContext) liegt bewusst in
  der separaten Unit DX.Logger.ThreadCpu (nur Diagnose-Pfad, riskantere WinAPI).
}

interface

uses
  System.SysUtils, System.Generics.Collections;

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

  /// <summary>Statische System-/Host-Konfiguration (einmal beim Start geloggt).</summary>
  TSystemInfoSnapshot = record
    LogicalProcessors: Integer;
    PhysicalCores: Integer;       // 0 = nicht ermittelbar
    ProcessorGroups: Integer;
    CpuBrand: string;
    TotalPhysMB: UInt64;
    AvailPhysMB: UInt64;
    MemoryLoadPercent: Integer;
    TotalPageFileMB: UInt64;
    AvailPageFileMB: UInt64;
    OsVersion: string;
    Is64BitOS: Boolean;
    ProcessBitness: string;       // 'Win32' | 'Win64'
    SystemManufacturer: string;   // VM-Hinweis (BIOS), z.B. 'VMware, Inc.'
    SystemProductName: string;
    MachineName: string;
    ProcessId: Cardinal;
    function ToLogLine: string;
    function ToProperties: TArray<TPair<string, string>>;
  end;

  TSystemInfo = class
  public
    class function GetSnapshot: TSystemInfoSnapshot; static;
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
  System.Win.Registry,
{$ENDIF}
{$IFDEF MACOS}
  Macapi.Mach,
{$ENDIF}
{$IFDEF POSIX}
  Posix.Unistd,
{$ENDIF}
  System.Classes,
  System.Math,
  System.StrUtils,
  System.DateUtils,
  DX.Logger;

// ===========================================================================
//  CPU — verbatim aus DX.Logger.CpuInfo.pas
// ===========================================================================

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

// ===========================================================================
//  Memory — verbatim aus DX.Logger.MemoryInfo.pas
// ===========================================================================

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

{ Public API — MemoryInfo-Callback }

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

// ===========================================================================
//  System — neue statische System-Info
// ===========================================================================

{$IFDEF MSWINDOWS}
function GetActiveProcessorGroupCount: WORD; stdcall;
  external kernel32 name 'GetActiveProcessorGroupCount';
function GetLogicalProcessorInformationEx(RelationshipType: DWORD; Buffer: Pointer;
  var ReturnedLength: DWORD): BOOL; stdcall;
  external kernel32 name 'GetLogicalProcessorInformationEx';

function CountPhysicalCores: Integer;
const
  RelationProcessorCore = 0;
var
  LLen: DWORD;
  LBuffer, LPtr: PByte;
  LRel, LSize: DWORD;
begin
  Result := 0;
  LLen := 0;
  GetLogicalProcessorInformationEx(RelationProcessorCore, nil, LLen);
  if (GetLastError <> ERROR_INSUFFICIENT_BUFFER) or (LLen = 0) then
    Exit;
  GetMem(LBuffer, LLen);
  try
    if not GetLogicalProcessorInformationEx(RelationProcessorCore, LBuffer, LLen) then
      Exit;
    LPtr := LBuffer;
    while (NativeUInt(LPtr) - NativeUInt(LBuffer)) < LLen do
    begin
      LRel := PDWORD(LPtr)^;            // SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX.Relationship
      LSize := PDWORD(LPtr + 4)^;       // .Size
      if LSize = 0 then
        Break;
      if LRel = RelationProcessorCore then
        Inc(Result);
      Inc(LPtr, LSize);
    end;
  finally
    FreeMem(LBuffer);
  end;
end;

function IsOS64Bit: Boolean;
{$IFDEF WIN64}
begin
  Result := True;
end;
{$ELSE}
var
  LWow64: BOOL;
begin
  LWow64 := False;
  if IsWow64Process(GetCurrentProcess, LWow64) then
    Result := LWow64
  else
    Result := False;
end;
{$ENDIF}

function ReadRegStr(const AKey, AName: string): string;
var
  LReg: TRegistry;
begin
  Result := '';
  LReg := TRegistry.Create(KEY_READ);
  try
    LReg.RootKey := HKEY_LOCAL_MACHINE;
    if LReg.OpenKeyReadOnly(AKey) then
      try
        if LReg.ValueExists(AName) then
          Result := LReg.ReadString(AName);
      except
        // Registry-Diagnose darf nie den Start gefährden
      end;
  finally
    LReg.Free;
  end;
end;
{$ENDIF}

function TSystemInfoSnapshot.ToLogLine: string;
begin
  Result := Format(
    'System | cores=%dP/%dL grp=%d | mem=%dMB total/%dMB avail (%d%%) | os=%s %s | proc=%s | host=%s | mfg=%s/%s',
    [PhysicalCores, LogicalProcessors, ProcessorGroups,
     TotalPhysMB, AvailPhysMB, MemoryLoadPercent,
     OsVersion, IfThen(Is64BitOS, 'x64', 'x86'),
     ProcessBitness, MachineName, SystemManufacturer, SystemProductName]);
end;

function TSystemInfoSnapshot.ToProperties: TArray<TPair<string, string>>;
begin
  SetLength(Result, 14);
  Result[0]  := TPair<string, string>.Create('SourceContext', 'SystemInfo');
  Result[1]  := TPair<string, string>.Create('LogicalProcessors', IntToStr(LogicalProcessors));
  Result[2]  := TPair<string, string>.Create('PhysicalCores', IntToStr(PhysicalCores));
  Result[3]  := TPair<string, string>.Create('ProcessorGroups', IntToStr(ProcessorGroups));
  Result[4]  := TPair<string, string>.Create('CpuBrand', CpuBrand);
  Result[5]  := TPair<string, string>.Create('TotalPhysMB', IntToStr(TotalPhysMB));
  Result[6]  := TPair<string, string>.Create('AvailPhysMB', IntToStr(AvailPhysMB));
  Result[7]  := TPair<string, string>.Create('MemoryLoadPercent', IntToStr(MemoryLoadPercent));
  Result[8]  := TPair<string, string>.Create('OsVersion', OsVersion);
  Result[9]  := TPair<string, string>.Create('Is64BitOS', BoolToStr(Is64BitOS, True));
  Result[10] := TPair<string, string>.Create('ProcessBitness', ProcessBitness);
  Result[11] := TPair<string, string>.Create('SystemManufacturer', SystemManufacturer);
  Result[12] := TPair<string, string>.Create('SystemProductName', SystemProductName);
  Result[13] := TPair<string, string>.Create('MachineName', MachineName);
end;

class function TSystemInfo.GetSnapshot: TSystemInfoSnapshot;
{$IFDEF MSWINDOWS}
const
  CKeyCpu = 'HARDWARE\DESCRIPTION\System\CentralProcessor\0';
  CKeyBios = 'HARDWARE\DESCRIPTION\System\BIOS';
var
  LMem: TMemoryStatusEx;
  LName: array[0..MAX_COMPUTERNAME_LENGTH] of Char;
  LSize: DWORD;
begin
  Result := Default(TSystemInfoSnapshot);
  Result.LogicalProcessors := TThread.ProcessorCount;
  Result.PhysicalCores := CountPhysicalCores;
  Result.ProcessorGroups := GetActiveProcessorGroupCount;
  Result.CpuBrand := Trim(ReadRegStr(CKeyCpu, 'ProcessorNameString'));

  FillChar(LMem, SizeOf(LMem), 0);
  LMem.dwLength := SizeOf(LMem);
  if GlobalMemoryStatusEx(LMem) then
  begin
    Result.TotalPhysMB := LMem.ullTotalPhys div (1024 * 1024);
    Result.AvailPhysMB := LMem.ullAvailPhys div (1024 * 1024);
    Result.MemoryLoadPercent := LMem.dwMemoryLoad;
    Result.TotalPageFileMB := LMem.ullTotalPageFile div (1024 * 1024);
    Result.AvailPageFileMB := LMem.ullAvailPageFile div (1024 * 1024);
  end;

  Result.OsVersion := Format('%d.%d.%d',
    [TOSVersion.Major, TOSVersion.Minor, TOSVersion.Build]);
  Result.Is64BitOS := IsOS64Bit;
  {$IFDEF WIN64} Result.ProcessBitness := 'Win64'; {$ELSE} Result.ProcessBitness := 'Win32'; {$ENDIF}
  Result.SystemManufacturer := Trim(ReadRegStr(CKeyBios, 'SystemManufacturer'));
  Result.SystemProductName := Trim(ReadRegStr(CKeyBios, 'SystemProductName'));

  LSize := Length(LName);
  if GetComputerName(LName, LSize) then
    Result.MachineName := LName
  else
    Result.MachineName := '';
  Result.ProcessId := GetCurrentProcessId;
end;
{$ELSE}
begin
  Result := Default(TSystemInfoSnapshot);
  {$IFDEF WIN64} Result.ProcessBitness := 'Win64'; {$ELSE} Result.ProcessBitness := 'Win32'; {$ENDIF}
end;
{$ENDIF}

end.
