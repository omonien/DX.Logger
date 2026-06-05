unit DX.Logger.ThreadCpu;

{
  DX.Logger.ThreadCpu - Per-Thread CPU Diagnostic (on-demand)

  Copyright (c) 2026 Olaf Monien
  SPDX-License-Identifier: MIT

  Liefert die Top-N Threads des eigenen Prozesses nach CPU-Verbrauch seit dem
  letzten Aufruf (Delta über GetThreadTimes). Für den heißesten Thread wird
  zusätzlich der aktuelle Instruction-Pointer via kurzem SuspendThread/
  GetThreadContext/ResumeThread erfasst. Adressen sind roh (Win32-Konvention,
  IntToHex 8) und werden offline mit Build/map-lookup.py + .map aufgelöst.

  Bewusst getrennt von DX.Logger.SystemInfo: nur Diagnose-Pfad, riskantere WinAPI.
}

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  /// <summary>Kumulative CPU-Ticks (100ns) eines Threads zum Messzeitpunkt.</summary>
  TThreadTicks = record
    ThreadId: Cardinal;
    Ticks: UInt64;
  end;

  /// <summary>Ergebnis eines Top-Threads.</summary>
  TThreadCpuSample = record
    ThreadId: Cardinal;
    CpuPercent: Double;
    Win32StartAddr: UInt64; // 0 = nicht ermittelbar
    CurrentIp: UInt64;      // nur für #1 befüllt; 0 sonst
  end;

  TThreadCpuMonitor = class
  private
    class var FPriorThreadTicks: TDictionary<Cardinal, UInt64>;
    class var FPriorSystemTotal: UInt64;
    class var FLock: TObject;
    class constructor Create;
    class destructor Destroy;
  public
    /// <summary>
    /// Pure: wählt Top-N nach (Ticks - Prior) absteigend. Neue/zurückgesetzte
    /// Threads (kein Prior oder Ticks &lt; Prior) zählen als Delta 0. CpuPercent
    /// = Delta*100 / ASystemDelta (0 wenn ASystemDelta=0). Adress-Felder bleiben 0.
    /// </summary>
    class function SelectTopByDelta(const ACurrent: TArray<TThreadTicks>;
      const APrior: TDictionary<Cardinal, UInt64>; ASystemDelta: UInt64;
      ATopN: Integer): TArray<TThreadCpuSample>; static;

    /// <summary>
    /// Erfasst alle Prozess-Threads, berechnet Deltas gegen den vorigen Aufruf,
    /// liefert Top-N inkl. Win32-Start-Adresse (alle) und Current-IP (#1).
    /// </summary>
    class function GetTopThreads(ATopN: Integer): TArray<TThreadCpuSample>; static;

    /// <summary>Setzt die Vorgänger-Referenz zurück. Test-Hook.</summary>
    class procedure ResetPriorSample; static;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows, Winapi.TlHelp32,
{$ENDIF}
  System.Generics.Defaults;

{$IFDEF MSWINDOWS}
const
  ThreadQuerySetWin32StartAddress = 9;
  // Diese Thread-Access-Rechte + OpenThread sind in Winapi.Windows (Delphi 10.3)
  // nicht deklariert — daher hier explizit.
  THREAD_QUERY_INFORMATION = $0040;
  THREAD_GET_CONTEXT = $0008;
  THREAD_SUSPEND_RESUME = $0002;

function OpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwThreadId: DWORD): THandle;
  stdcall; external kernel32 name 'OpenThread';

function NtQueryInformationThread(ThreadHandle: THandle; ThreadInformationClass: Integer;
  ThreadInformation: Pointer; ThreadInformationLength: ULONG; ReturnLength: PULONG): LongInt; stdcall;
  external 'ntdll.dll';

function FileTimeToU64(const AFt: TFileTime): UInt64; inline;
begin
  Result := (UInt64(AFt.dwHighDateTime) shl 32) or UInt64(AFt.dwLowDateTime);
end;

function QuerySystemTotalTicks: UInt64;
var
  LIdle, LKernel, LUser: TFileTime;
begin
  Result := 0;
  if GetSystemTimes(LIdle, LKernel, LUser) then
    Result := FileTimeToU64(LKernel) + FileTimeToU64(LUser);
end;

function EnumProcessThreadTicks: TArray<TThreadTicks>;
var
  LSnap: THandle;
  LEntry: TThreadEntry32;
  LPid: DWORD;
  LList: TList<TThreadTicks>;
  LH: THandle;
  LCreate, LExit, LKernel, LUser: TFileTime;
  LItem: TThreadTicks;
begin
  LList := TList<TThreadTicks>.Create;
  try
    LSnap := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if LSnap <> INVALID_HANDLE_VALUE then
    try
      LPid := GetCurrentProcessId;
      LEntry.dwSize := SizeOf(LEntry);
      if Thread32First(LSnap, LEntry) then
        repeat
          if LEntry.th32OwnerProcessID = LPid then
          begin
            LH := OpenThread(THREAD_QUERY_INFORMATION, False, LEntry.th32ThreadID);
            if LH <> 0 then
            try
              if GetThreadTimes(LH, LCreate, LExit, LKernel, LUser) then
              begin
                LItem.ThreadId := LEntry.th32ThreadID;
                LItem.Ticks := FileTimeToU64(LKernel) + FileTimeToU64(LUser);
                LList.Add(LItem);
              end;
            finally
              CloseHandle(LH);
            end;
          end;
          LEntry.dwSize := SizeOf(LEntry);
        until not Thread32Next(LSnap, LEntry);
    finally
      CloseHandle(LSnap);
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function QueryWin32StartAddr(AThreadId: Cardinal): UInt64;
var
  LH: THandle;
  LAddr: NativeUInt;
begin
  Result := 0;
  LH := OpenThread(THREAD_QUERY_INFORMATION, False, AThreadId);
  if LH = 0 then
    Exit;
  try
    LAddr := 0;
    if NtQueryInformationThread(LH, ThreadQuerySetWin32StartAddress, @LAddr,
      SizeOf(LAddr), nil) = 0 then
      Result := LAddr;
  finally
    CloseHandle(LH);
  end;
end;

function QueryCurrentIp(AThreadId: Cardinal): UInt64;
var
  LH: THandle;
  LCtx: TContext;
begin
  Result := 0;
  // Niemals den aufrufenden (Heartbeat-)Thread suspenden.
  if AThreadId = GetCurrentThreadId then
    Exit;
  LH := OpenThread(THREAD_GET_CONTEXT or THREAD_SUSPEND_RESUME, False, AThreadId);
  if LH = 0 then
    Exit;
  try
    if SuspendThread(LH) = DWORD(-1) then
      Exit;
    try
      FillChar(LCtx, SizeOf(LCtx), 0);
      LCtx.ContextFlags := CONTEXT_CONTROL;
      if GetThreadContext(LH, LCtx) then
      {$IFDEF WIN64}
        Result := LCtx.Rip;
      {$ELSE}
        Result := LCtx.Eip;
      {$ENDIF}
    finally
      ResumeThread(LH);
    end;
  finally
    CloseHandle(LH);
  end;
end;
{$ENDIF}

{ TThreadCpuMonitor }

class constructor TThreadCpuMonitor.Create;
begin
  FLock := TObject.Create;
  FPriorThreadTicks := TDictionary<Cardinal, UInt64>.Create;
  FPriorSystemTotal := 0;
end;

class destructor TThreadCpuMonitor.Destroy;
begin
  FPriorThreadTicks.Free;
  FLock.Free;
end;

class procedure TThreadCpuMonitor.ResetPriorSample;
begin
  TMonitor.Enter(FLock);
  try
    FPriorThreadTicks.Clear;
    FPriorSystemTotal := 0;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TThreadCpuMonitor.SelectTopByDelta(const ACurrent: TArray<TThreadTicks>;
  const APrior: TDictionary<Cardinal, UInt64>; ASystemDelta: UInt64;
  ATopN: Integer): TArray<TThreadCpuSample>;
var
  LSamples: TList<TThreadCpuSample>;
  LCur: TThreadTicks;
  LPrior, LDelta: UInt64;
  LSample: TThreadCpuSample;
  I: Integer;
begin
  LSamples := TList<TThreadCpuSample>.Create;
  try
    for LCur in ACurrent do
    begin
      if APrior.TryGetValue(LCur.ThreadId, LPrior) and (LCur.Ticks >= LPrior) then
        LDelta := LCur.Ticks - LPrior
      else
        LDelta := 0;
      LSample := Default(TThreadCpuSample);
      LSample.ThreadId := LCur.ThreadId;
      if ASystemDelta > 0 then
        LSample.CpuPercent := (LDelta * 100.0) / ASystemDelta
      else
        LSample.CpuPercent := 0;
      LSamples.Add(LSample);
    end;
    LSamples.Sort(TComparer<TThreadCpuSample>.Construct(
      function(const L, R: TThreadCpuSample): Integer
      begin
        if R.CpuPercent > L.CpuPercent then Result := 1
        else if R.CpuPercent < L.CpuPercent then Result := -1
        else Result := 0;
      end));
    if ATopN > LSamples.Count then
      ATopN := LSamples.Count;
    SetLength(Result, ATopN);
    for I := 0 to ATopN - 1 do
      Result[I] := LSamples[I];
  finally
    LSamples.Free;
  end;
end;

class function TThreadCpuMonitor.GetTopThreads(ATopN: Integer): TArray<TThreadCpuSample>;
{$IFDEF MSWINDOWS}
var
  LCurrent: TArray<TThreadTicks>;
  LSysTotal, LSysDelta: UInt64;
  I: Integer;
  LTick: TThreadTicks;
begin
  TMonitor.Enter(FLock);
  try
    LCurrent := EnumProcessThreadTicks;
    LSysTotal := QuerySystemTotalTicks;
    if (FPriorSystemTotal > 0) and (LSysTotal >= FPriorSystemTotal) then
      LSysDelta := LSysTotal - FPriorSystemTotal
    else
      LSysDelta := 0;

    Result := SelectTopByDelta(LCurrent, FPriorThreadTicks, LSysDelta, ATopN);

    // Adressen anreichern (Start-Adresse für alle Top, IP nur für #1).
    for I := 0 to High(Result) do
    begin
      Result[I].Win32StartAddr := QueryWin32StartAddr(Result[I].ThreadId);
      if I = 0 then
        Result[I].CurrentIp := QueryCurrentIp(Result[I].ThreadId);
    end;

    // Vorgänger-Referenz aktualisieren.
    FPriorThreadTicks.Clear;
    for LTick in LCurrent do
      FPriorThreadTicks.AddOrSetValue(LTick.ThreadId, LTick.Ticks);
    FPriorSystemTotal := LSysTotal;
  finally
    TMonitor.Exit(FLock);
  end;
end;
{$ELSE}
begin
  SetLength(Result, 0);
end;
{$ENDIF}

end.
