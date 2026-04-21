/// <summary>
/// DXLogger.Callstack
/// Automatic exception callstack capture for DX.Logger.
/// </summary>
///
/// <remarks>
/// Add this unit to your uses clause to activate. No further code required.
/// On Windows: installs RTL exception hooks and registers a StackInfoCallback
/// on TDXLogger so that E.StackTrace is available and DXLogError automatically
/// populates the Details field.
/// On non-Windows platforms: compiles to a no-op.
/// </remarks>
///
/// <copyright>
/// Copyright © 2026 Olaf Monien
/// Licensed under MIT
/// </copyright>

unit DXLogger.Callstack;

interface

uses
  System.SysUtils,
  DX.Logger;

type
  /// <summary>
  /// Configuration for callstack capture and DX.Logger integration.
  /// Set fields before any threads start for thread-safe use.
  /// </summary>
  TDXCallstackOptions = record
    MaxFrames:        Integer;    // Default 32 — max frames shown in StackTrace string
    SkipFrames:       Integer;    // Default 1 — skip internal Callstack frames before raise
    IncludeAddresses: Boolean;    // Default True — show hex address per frame
    IncludeLineInfo:  Boolean;    // Default True — show file + line number per frame
    MapFilePath:      string;     // Default '' — empty = auto-detect next to EXE
    MinLogLevel:      TLogLevel;  // Default Error — min level to add stack to Details
  end;

var
  DXCallstackOptions: TDXCallstackOptions;

/// <summary>Capture the current call stack as a string, outside an exception context.</summary>
function DXCaptureStack: string;

/// <summary>
/// Install RTL exception hooks and DX.Logger StackInfoCallback.
/// Called automatically in initialization — only call manually in tests.
/// </summary>
procedure DXCallstackInstall;

/// <summary>
/// Uninstall RTL hooks and StackInfoCallback.
/// Called automatically in finalization.
/// </summary>
procedure DXCallstackUninstall;

/// <summary>
/// Reset the internal map cache so the next Resolve() re-reads the map file.
/// For testing only — use DXCallstackOptions.MapFilePath to point to a
/// non-existent file, call this, then restore the path after the test.
/// </summary>
procedure DXCallstackResetMapCache;

implementation

{$IFDEF MSWINDOWS}
uses
  Winapi.Windows,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Math;

const
  cMaxCaptureFrames = 64;
  cNoMapFallback    = '-- no call stack - map file not found --';

// ---------------------------------------------------------------------------
// Raw stack record — one instance per Exception, lives on the heap
// ---------------------------------------------------------------------------

type
  PStackInfoRecord = ^TStackInfoRecord;
  TStackInfoRecord = record
    Frames:     array[0..cMaxCaptureFrames - 1] of Pointer;
    FrameCount: Integer;
  end;

// ---------------------------------------------------------------------------
// Win32 API
// ---------------------------------------------------------------------------

function RtlCaptureStackBackTrace(FramesToSkip: ULONG; FramesToCapture: ULONG;
  BackTrace: Pointer; BackTraceHash: PULONG): USHORT; stdcall;
  external 'kernel32.dll' name 'RtlCaptureStackBackTrace';

// ---------------------------------------------------------------------------
// Map file parser — forward declarations
// ---------------------------------------------------------------------------

type
  TMapSymbol = record
    RVA:  UInt32;
    Name: string;
  end;

  TMapLine = record
    RVA:      UInt32;
    FileName: string;
    Line:     Integer;
  end;

  TModuleMap = class
  private
    FLoaded:        Boolean;
    FHasMapFile:    Boolean;
    FCodeSectionVA: UInt32;
    FSymbols:       array of TMapSymbol;
    FLines:         array of TMapLine;
    function  GetCodeSectionVA: UInt32;
    procedure ParseMapFile;
    procedure EnsureLoaded;
    function  FindNearestSymbol(ARVA: UInt32): Integer;
    function  FindNearestLine(ARVA: UInt32): Integer;
  public
    procedure ResetForTest;
    function  Resolve(AAddr: Pointer): string;
  end;

var
  GModuleMap: TModuleMap;

// ---------------------------------------------------------------------------
// Forward declarations for RTL hooks
// ---------------------------------------------------------------------------

function  DXCallstack_GetInfo(P: System.PExceptionRecord): Pointer; forward;
procedure DXCallstack_CleanUp(Info: Pointer); forward;
function  DXCallstack_InfoToString(Info: Pointer): string; forward;
function  DXCaptureStackImpl: string; forward;

{$ENDIF MSWINDOWS}

// ---------------------------------------------------------------------------
// Public API — non-Windows stubs compile to no-ops
// ---------------------------------------------------------------------------

function DXCaptureStack: string;
begin
{$IFDEF MSWINDOWS}
  Result := DXCaptureStackImpl;
{$ELSE}
  Result := '';
{$ENDIF}
end;

procedure DXCallstackInstall;
begin
  {$IFDEF MSWINDOWS}
  if not Assigned(Exception.GetExceptionStackInfoProc) then
    Exception.GetExceptionStackInfoProc := DXCallstack_GetInfo
  else
    DXLog('DXLogger.Callstack: GetExceptionStackInfoProc already set by another library',
          TLogLevel.Warn);

  if not Assigned(Exception.CleanUpStackInfoProc) then
    Exception.CleanUpStackInfoProc := DXCallstack_CleanUp;

  if not Assigned(Exception.GetStackInfoStringProc) then
    Exception.GetStackInfoStringProc := DXCallstack_InfoToString;
  {$ENDIF}
end;

procedure DXCallstackUninstall;
begin
  {$IFDEF MSWINDOWS}
  if PPointer(@Exception.GetExceptionStackInfoProc)^ = @DXCallstack_GetInfo then
    Exception.GetExceptionStackInfoProc := nil;
  if PPointer(@Exception.CleanUpStackInfoProc)^ = @DXCallstack_CleanUp then
    Exception.CleanUpStackInfoProc := nil;
  if PPointer(@Exception.GetStackInfoStringProc)^ = @DXCallstack_InfoToString then
    Exception.GetStackInfoStringProc := nil;
  TDXLogger.Instance.StackInfoCallback := nil;
  {$ENDIF}
end;

procedure DXCallstackResetMapCache;
begin
  {$IFDEF MSWINDOWS}
  if Assigned(GModuleMap) then
    GModuleMap.ResetForTest;
  {$ENDIF}
end;

{$IFDEF MSWINDOWS}

// ---------------------------------------------------------------------------
// Stub implementations — replaced in Tasks 3–6
// ---------------------------------------------------------------------------

function DXCallstack_GetInfo(P: System.PExceptionRecord): Pointer;
var
  LRec: PStackInfoRecord;
begin
  New(LRec);
  FillChar(LRec^, SizeOf(TStackInfoRecord), 0);
  LRec^.FrameCount := RtlCaptureStackBackTrace(
    DXCallstackOptions.SkipFrames,
    cMaxCaptureFrames,
    @LRec^.Frames[0],
    nil);
  Result := LRec;
end;

procedure DXCallstack_CleanUp(Info: Pointer);
begin
  if Info <> nil then
    Dispose(PStackInfoRecord(Info));
end;

function DXCallstack_InfoToString(Info: Pointer): string;
begin
  // Task 5
  Result := '';
end;

function TModuleMap.GetCodeSectionVA: UInt32;
begin
  // Task 4
  Result := $1000;
end;

procedure TModuleMap.ParseMapFile;
begin
  // Task 4
end;

procedure TModuleMap.EnsureLoaded;
begin
  // Task 4
end;

function TModuleMap.FindNearestSymbol(ARVA: UInt32): Integer;
begin
  // Task 4
  Result := -1;
end;

function TModuleMap.FindNearestLine(ARVA: UInt32): Integer;
begin
  // Task 4
  Result := -1;
end;

procedure TModuleMap.ResetForTest;
begin
  TMonitor.Enter(Self);
  try
    FLoaded     := False;
    FHasMapFile := False;
    SetLength(FSymbols, 0);
    SetLength(FLines, 0);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TModuleMap.Resolve(AAddr: Pointer): string;
begin
  // Task 5
  Result := cNoMapFallback;
end;

function DXCaptureStackImpl: string;
begin
  // Task 5
  Result := '';
end;

{$ENDIF MSWINDOWS}

initialization
  DXCallstackOptions.MaxFrames        := 32;
  DXCallstackOptions.SkipFrames       := 1;
  DXCallstackOptions.IncludeAddresses := True;
  DXCallstackOptions.IncludeLineInfo  := True;
  DXCallstackOptions.MapFilePath      := '';
  DXCallstackOptions.MinLogLevel      := TLogLevel.Error;
  {$IFDEF MSWINDOWS}
  GModuleMap := TModuleMap.Create;
  DXCallstackInstall;
  {$ENDIF}

finalization
  {$IFDEF MSWINDOWS}
  DXCallstackUninstall;
  FreeAndNil(GModuleMap);
  {$ENDIF}

end.
