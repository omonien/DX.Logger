unit DX.Logger;

{
  DX.Logger - Minimalistic Cross-Platform Logger for Delphi

  Copyright (c) 2025 Olaf Monien
  SPDX-License-Identifier: MIT

  Simple usage:
    uses DX.Logger;

    DXLog('Hello World');                    // Info level
    DXLog('Debug message', TLogLevel.Debug); // Debug level
    DXLog('Error!', TLogLevel.Error);        // Error level

  Platform-specific output:
    - Console apps: WriteLn
    - Windows: OutputDebugString
    - iOS/macOS: NSLog
    - Android: Android system log
    - Linux: syslog

  Provider architecture:
    Additional log targets can be added by using provider units:
    uses DX.Logger.Provider.TextFile;  // Adds file logging

  Startup behavior:
    From process start, TDXLogger holds a configuration window: the platform
    default provider above writes immediately, but every other registered
    provider (File, Seq, UI, custom) receives nothing until
    TDXLogger.CompleteConfiguration is called, StartupTimeoutMs (default
    10 s) elapses, or the process shuts down. Early entries are buffered
    (never lost) and replayed once the window closes. See
    docs/CONFIGURATION.md ("Startup & Configuration Window") for the
    recommended DPR layout.
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs;

type
  /// <summary>
  /// Log level enumeration
  /// </summary>
  TLogLevel = (
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    None
  );

  /// <summary>
  /// Log entry record containing all information about a log message
  /// </summary>
  TLogEntry = record
    Timestamp: TDateTime;
    Level: TLogLevel;
    Message: string;
    Details: string;    // Optional: Additional detail information (e.g., large JSON payloads)
    ThreadID: TThreadID;
    /// <summary>
    /// Optional: Short memory-pressure snapshot (e.g. "WS:45MB PB:22MB").
    /// Filled by TDXLogger if a memory-info callback is registered via
    /// TDXLogger.Instance.MemoryInfoCallback. Providers display the value
    /// between ThreadID and message when non-empty. Kept free-form to
    /// avoid binding DX.Logger to a specific memory library.
    /// </summary>
    MemoryInfo: string;
    /// <summary>
    /// Optional: Structured key/value properties attached to this log entry.
    /// Providers that support structured logging (e.g. Seq) render these
    /// as top-level fields. Plain providers may ignore them. Dynamic-array
    /// element type means the record copies safely through async queues.
    /// Keys must not start with '@' (reserved by CLEF).
    /// </summary>
    Properties: TArray<TPair<string, string>>;
  end;

  /// <summary>
  /// Callback type used by TDXLogger to query a short memory-pressure
  /// snapshot from the host application each time a log entry is produced.
  /// Kept deliberately minimal so DX.Logger does not depend on any specific
  /// process-memory library.
  /// </summary>
  TMemoryInfoCallback = reference to function: string;

  /// <summary>
  /// Optionaler Callback, der bei jedem Log()-Aufruf gefeuert wird und
  /// strukturierte Kontext-Properties zurueckliefert (z. B. ContextID,
  /// RequestID, TenantID). Result wird in TLogEntry.Properties gemerged.
  /// Caller-Properties haben Vorrang bei Key-Kollision.
  /// Exceptions im Callback werden geschluckt — Logging darf niemals
  /// durch broken Callbacks crashen.
  /// </summary>
  TLogPropertiesCallback = reference to function: TArray<TPair<string, string>>;

  /// <summary>
  /// Interface for log providers
  /// </summary>
  ILogProvider = interface
    ['{8F3D2A1B-4C5E-4F6D-8A9B-1C2D3E4F5A6B}']
    procedure Log(const AEntry: TLogEntry);
  end;

  /// <summary>
  /// Optional interface for providers that support connection validation.
  /// If a provider implements this interface, ValidateConnection will be called
  /// automatically when the provider is registered with TDXLogger.
  /// Providers should log success/failure information to help diagnose issues.
  /// </summary>
  ILogProviderValidation = interface
    ['{A1B2C3D4-E5F6-4A5B-9C8D-7E6F5A4B3C2D}']
    /// <summary>
    /// Validates the provider's configuration and connection.
    /// Called automatically after registration.
    /// Should log success or detailed error information.
    /// </summary>
    procedure ValidateConnection;
  end;

  /// <summary>
  /// Core logger class (singleton)
  /// </summary>
  TDXLogger = class sealed
  private
    class var FInstance: TDXLogger;
    class var FMinLevel: TLogLevel;
    class var FLock: TObject;
    class var FAppVersion: string;
    class var FAppVersionResolved: Boolean;
    // Startup configuration window (see docs/superpowers/specs/2026-08-14-
    // startup-configuration-window-design.md). Class-level so the window can
    // be reasoned about (and reset for tests) independently of any single
    // TDXLogger instance.
    class var FWindowOpen: Boolean;
    class var FStartupBuffer: TList<TLogEntry>;
    class var FStartupDropCount: Cardinal;
    class var FStartupTimeoutMs: Cardinal;
    // Fallback watchdog (see design doc "Fallback timer"): a single
    // short-lived thread, armed on the first Instance access (and re-armed
    // by ResetStartupStateForTesting), that closes the window on its own
    // if nobody calls CompleteConfiguration in time. FWatchdogEvent is the
    // thread's wait handle; CompleteConfiguration always signals it
    // (idempotently) so an explicit/early close lets the thread exit
    // immediately instead of sleeping out the rest of the timeout.
    class var FWatchdogThread: TThread;
    class var FWatchdogEvent: TEvent;
  private
    FProviders: TList<ILogProvider>;
    // The platform default provider, kept apart from FProviders so it can be
    // dispatched to directly while the window is open and excluded from the
    // startup replay in CompleteConfiguration.
    FDefaultProvider: ILogProvider;
    FMemoryInfoCallback: TMemoryInfoCallback;
    FLogPropertiesCallback: TLogPropertiesCallback;

    /// <summary>
    /// Arms the fallback watchdog thread: creates a fresh FWatchdogEvent and
    /// starts a thread that waits on it for FStartupTimeoutMs and calls
    /// CompleteConfiguration on timeout. No-op when StartupTimeoutMs = 0 or
    /// the window is already closed. Must only be called when no watchdog is
    /// currently armed (callers first go through StopWatchdog).
    /// </summary>
    class procedure ArmWatchdog;

    /// <summary>
    /// Signals and joins any currently armed watchdog thread and frees both
    /// the thread and its event. Safe to call when no watchdog is armed.
    /// </summary>
    class procedure StopWatchdog;

    constructor Create;
    class constructor Create;
    class destructor Destroy;
  public
    destructor Destroy; override;

    /// <summary>
    /// Register a custom log provider
    /// </summary>
    procedure RegisterProvider(const AProvider: ILogProvider);

    /// <summary>
    /// Unregister a custom log provider
    /// </summary>
    procedure UnregisterProvider(const AProvider: ILogProvider);

    /// <summary>
    /// Log a message with optional level and details
    /// </summary>
    procedure Log(const AMessage: string; ALevel: TLogLevel = TLogLevel.Info; const ADetails: string = ''); overload;

    /// <summary>
    /// Log a message with structured key/value properties (rendered as
    /// top-level fields by structured providers like Seq).
    /// </summary>
    procedure Log(const AMessage: string; ALevel: TLogLevel; const ADetails: string;
      const AProperties: TArray<TPair<string, string>>); overload;

    /// <summary>
    /// Get singleton instance
    /// </summary>
    class function Instance: TDXLogger;

    /// <summary>
    /// Set minimum log level (messages below this level are ignored)
    /// </summary>
    class procedure SetMinLevel(ALevel: TLogLevel);

    /// <summary>
    /// Returns True when a message at ALevel would be emitted (i.e. the
    /// current MinLevel allows it). Callers can use this to skip expensive
    /// message/parameter construction when the log would otherwise be dropped.
    /// </summary>
    class function IsLevelEnabled(ALevel: TLogLevel): Boolean;

    /// <summary>
    /// Ends the configuration phase: replays all buffered startup entries (in
    /// original order, filtered with the MinLevel valid now) to every registered
    /// provider except the platform default provider, then discards the buffer.
    /// Thread-safe and idempotent; may be called from any thread. Providers
    /// registered after this call start empty and receive live entries only.
    /// </summary>
    class procedure CompleteConfiguration;

    /// <summary>
    /// Fallback timeout for the configuration window in milliseconds.
    /// Default 10000. 0 disables auto-close (explicit CompleteConfiguration or
    /// process shutdown only). Effective while the window is open.
    /// </summary>
    class property StartupTimeoutMs: Cardinal read FStartupTimeoutMs write FStartupTimeoutMs;

    /// <summary>
    /// TEST SUPPORT ONLY: reopens the configuration window, clears the startup
    /// buffer and drop counter, and re-arms the fallback watchdog with the
    /// current StartupTimeoutMs. Not intended for production code.
    /// </summary>
    class procedure ResetStartupStateForTesting;

    /// <summary>
    /// Application version string (e.g. "1.0.3.1172"). Centralized here so
    /// every provider sees the same value. Currently consumed by the Seq
    /// provider, which adds it as `AppVersion` to every CLEF event. Other
    /// providers may opt-in.
    /// On Windows, an unset value is auto-detected from the executable's
    /// version resource the first time it is read. On other platforms,
    /// callers must set it explicitly via SetAppVersion.
    /// </summary>
    class function GetAppVersion: string;

    /// <summary>
    /// Explicitly set the application version. Overrides any auto-detected
    /// value. Pass an empty string to re-enable auto-detection on next read.
    /// </summary>
    class procedure SetAppVersion(const AVersion: string);

    /// <summary>
    /// Optional callback that returns a short memory-pressure snapshot.
    /// When set, the result is attached to every TLogEntry as MemoryInfo
    /// and rendered by the standard providers between thread-id and message.
    /// Assign nil to disable. Host applications are responsible for keeping
    /// the callback cheap (caching recommended) since it runs per log entry.
    /// </summary>
    property MemoryInfoCallback: TMemoryInfoCallback read FMemoryInfoCallback write FMemoryInfoCallback;

    /// <summary>
    /// Optionaler Callback, der pro Log-Eintrag strukturierte Properties
    /// liefert. Result wird zu TLogEntry.Properties gemerged. Caller-
    /// Properties haben Vorrang. Exceptions werden geschluckt.
    /// Beispiel: pro Request eine ContextID aus dem Session-Kontext mitgeben.
    /// </summary>
    property LogPropertiesCallback: TLogPropertiesCallback
      read FLogPropertiesCallback write FLogPropertiesCallback;
  end;

/// <summary>
/// Convenience function for logging with optional level and details
/// </summary>
procedure DXLog(const AMessage: string; ALevel: TLogLevel = TLogLevel.Info; const ADetails: string = ''); overload; inline;

/// <summary>
/// Convenience functions for specific log levels
/// </summary>
procedure DXLogTrace(const AMessage: string); inline;
procedure DXLogDebug(const AMessage: string); inline;
procedure DXLogInfo(const AMessage: string); inline;
procedure DXLogWarn(const AMessage: string); inline;
procedure DXLogError(const AMessage: string); inline;

/// <summary>
/// Convert log level to string
/// </summary>
function LogLevelToString(ALevel: TLogLevel): string;

implementation

// System.SyncObjs (needed here for TEvent, the watchdog's wait handle) now
// lives in the INTERFACE uses clause instead — the private class var
// FWatchdogEvent: TEvent is declared in the interface-section class body,
// so the type must already be visible there, and Delphi treats the same
// unit appearing in both an interface and implementation uses clause of
// the same file as a redeclaration error (E2004). The platform units below
// are mutually exclusive per target (exactly one of MSWINDOWS / ANDROID /
// MACOS / LINUX is ever defined for a given build), so this remains a
// syntactically valid single-entry (or two-entry, for MACOS) uses clause
// on every supported platform without a dedicated anchor unit.
uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows
  {$ENDIF}
  {$IFDEF ANDROID}
  Androidapi.Log
  {$ENDIF}
  {$IFDEF MACOS}
	Macapi.Helpers,
	Macapi.Foundation
  {$ENDIF}
  {$IFDEF LINUX}
  Posix.Syslog
  {$ENDIF}
  ;

const
  // Startup configuration window (see docs/superpowers/specs/2026-08-14-
  // startup-configuration-window-design.md). Fixed cap on the startup
  // buffer; on overflow the newest entries are dropped (oldest boot lines
  // carry the highest diagnostic value).
  C_STARTUP_BUFFER_MAX = 10000;
  // Default fallback watchdog timeout in milliseconds.
  C_DEFAULT_STARTUP_TIMEOUT_MS = 10000;

type
  /// <summary>
  /// Default platform-specific log provider
  /// </summary>
  TDefaultLogProvider = class(TInterfacedObject, ILogProvider)
  public
    procedure Log(const AEntry: TLogEntry);
  end;

{ TDefaultLogProvider }

procedure TDefaultLogProvider.Log(const AEntry: TLogEntry);
var
  LFormattedMessage: string;
  LMemSegment: string;
  {$IFDEF ANDROID}
  LMarshaller: TMarshaller;
  {$ENDIF}
begin
  // Optional memory snippet right after [Thread:N] (empty when no callback).
  LMemSegment := '';
  if AEntry.MemoryInfo <> '' then
    LMemSegment := '[' + AEntry.MemoryInfo + '] ';

  LFormattedMessage := Format('[%s] [%s] [Thread:%d] %s%s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', AEntry.Timestamp),
     LogLevelToString(AEntry.Level),
     AEntry.ThreadID,
     LMemSegment,
     AEntry.Message]);

  {$IFDEF CONSOLE}
  WriteLn(LFormattedMessage);
  if AEntry.Details <> '' then
    WriteLn('Details: ' + AEntry.Details);
  {$ENDIF}

  {$IFDEF MSWINDOWS}
  OutputDebugString(PChar(LFormattedMessage));
  if AEntry.Details <> '' then
    OutputDebugString(PChar('Details: ' + AEntry.Details));
  {$ENDIF}

  {$IFDEF ANDROID}
  case AEntry.Level of
    TLogLevel.Trace: __android_log_write(ANDROID_LOG_VERBOSE, LMarshaller.AsAnsi('DXLogger').ToPointer, LMarshaller.AsAnsi(LFormattedMessage).ToPointer);
    TLogLevel.Debug: __android_log_write(ANDROID_LOG_DEBUG, LMarshaller.AsAnsi('DXLogger').ToPointer, LMarshaller.AsAnsi(LFormattedMessage).ToPointer);
    TLogLevel.Info:  __android_log_write(ANDROID_LOG_INFO, LMarshaller.AsAnsi('DXLogger').ToPointer, LMarshaller.AsAnsi(LFormattedMessage).ToPointer);
    TLogLevel.Warn:  __android_log_write(ANDROID_LOG_WARN, LMarshaller.AsAnsi('DXLogger').ToPointer, LMarshaller.AsAnsi(LFormattedMessage).ToPointer);
    TLogLevel.Error: __android_log_write(ANDROID_LOG_ERROR, LMarshaller.AsAnsi('DXLogger').ToPointer, LMarshaller.AsAnsi(LFormattedMessage).ToPointer);
  end;
  {$ENDIF}

  {$IFDEF MACOS}
  // IMPORTANT:
  // NSLog is a C varargs function (printf-style). Passing an Objective-C interface
  // (e.g. NSString from StrToNSStr) can crash due to Delphi marshalling.
  // Always pass an ObjC `id` (e.g. via StringToId / StrToId).
  NSLog(StringToId(LFormattedMessage));
  {$ENDIF}

  {$IFDEF LINUX}
  case AEntry.Level of
    TLogLevel.Trace: syslog(LOG_DEBUG, PAnsiChar(UTF8String(LFormattedMessage)));
    TLogLevel.Debug: syslog(LOG_DEBUG, PAnsiChar(UTF8String(LFormattedMessage)));
    TLogLevel.Info:  syslog(LOG_INFO, PAnsiChar(UTF8String(LFormattedMessage)));
    TLogLevel.Warn:  syslog(LOG_WARNING, PAnsiChar(UTF8String(LFormattedMessage)));
    TLogLevel.Error: syslog(LOG_ERR, PAnsiChar(UTF8String(LFormattedMessage)));
  end;
  {$ENDIF}
end;

{ TDXLogger }

constructor TDXLogger.Create;
begin
  inherited Create;
  FProviders := TList<ILogProvider>.Create;

  // Register default platform-specific provider. Keep the reference in
  // FDefaultProvider (distinct from anonymous registration) so Log can
  // dispatch to it directly while the configuration window is open, and
  // CompleteConfiguration can exclude it from the startup replay.
  FDefaultProvider := TDefaultLogProvider.Create;
  RegisterProvider(FDefaultProvider);
end;

destructor TDXLogger.Destroy;
begin
  FreeAndNil(FProviders);
  inherited;
end;

class destructor TDXLogger.Destroy;
begin
  // Stop the watchdog first: signal + join + free it, so no watchdog thread
  // can still be mid-timeout (or mid-CompleteConfiguration) while the rest
  // of this teardown runs below.
  StopWatchdog;

  // Flush a still-open window (e.g. a short-lived CLI process that never
  // called CompleteConfiguration and exits before the timeout) BEFORE
  // freeing the instance/lock. CompleteConfiguration is idempotent, so this
  // is also a safe no-op if the window was already closed.
  //
  // Finalization-order safety (named risk from the design doc, verified
  // while implementing this task): provider units (DX.Logger.Provider.*)
  // list DX.Logger in their `uses` clause, so per Delphi's unit
  // finalization order (reverse of initialization order) their class
  // destructors may well run BEFORE this one. That is safe here: every
  // shipped provider (TFileLogProvider, TSeqLogProvider, TUILogProvider)
  // follows the same pattern in its own `class destructor Destroy` --
  // "During shutdown, just set to nil without freeing / The instance will
  // be freed by the reference counting" -- i.e. it only nils its own
  // singleton class-var pointer and never frees the provider object
  // directly. The provider object itself stays alive purely through the
  // ILogProvider interface reference held in FInstance.FProviders, so it is
  // still fully live and functional at this point regardless of provider
  // unit finalization order. The provider objects are only actually
  // destroyed once FreeAndNil(FInstance) below releases FProviders
  // (interface refcount reaching zero triggers e.g. TAsyncLogProvider's
  // worker-thread shutdown) -- strictly AFTER this flush has dispatched to
  // them. No hazard found; no guard beyond the existing interface-refcount
  // discipline is needed.
  CompleteConfiguration;

  FreeAndNil(FInstance);
  FreeAndNil(FStartupBuffer);
  FreeAndNil(FLock);
end;

class function TDXLogger.Instance: TDXLogger;
var
  LCreated: Boolean;
begin
  LCreated := False;
  if not Assigned(FInstance) then
  begin
    TMonitor.Enter(FLock);
    try
      if not Assigned(FInstance) then  // Double-checked locking
      begin
        FInstance := TDXLogger.Create;
        LCreated := True;
      end;
    finally
      TMonitor.Exit(FLock);
    end;
  end;
  Result := FInstance;

  // Arm the fallback watchdog on the very first Instance access (in
  // practice: the first provider registration in a unit initialization
  // section, or the first Log call). LCreated is True exactly once per
  // process (guarded by the double-checked locking above), so this is
  // naturally idempotent without needing a separate "already armed" flag.
  // Deliberately done AFTER releasing FLock: ArmWatchdog creates and starts
  // an OS thread, which must never happen while holding a lock that the
  // watchdog thread's own body might need to re-acquire (it calls
  // CompleteConfiguration on timeout, which takes FLock) — see ArmWatchdog.
  if LCreated then
    ArmWatchdog;
end;

class procedure TDXLogger.SetMinLevel(ALevel: TLogLevel);
begin
  FMinLevel := ALevel;
end;

class function TDXLogger.IsLevelEnabled(ALevel: TLogLevel): Boolean;
begin
  Result := ALevel >= FMinLevel;
end;

{$IFDEF MSWINDOWS}
function GetAppVersionFromExe: string;
var
  LFileName: string;
  LDummy: DWORD;
  LSize: DWORD;
  LBuffer: TBytes;
  LFixedInfo: PVSFixedFileInfo;
  LFixedSize: UINT;
begin
  Result := '';
  LFileName := ParamStr(0);
  LSize := GetFileVersionInfoSize(PChar(LFileName), LDummy);
  if LSize = 0 then
    Exit;

  SetLength(LBuffer, LSize);
  if not GetFileVersionInfo(PChar(LFileName), 0, LSize, LBuffer) then
    Exit;

  LFixedInfo := nil;
  LFixedSize := 0;
  if not VerQueryValue(LBuffer, '\', Pointer(LFixedInfo), LFixedSize) then
    Exit;
  if (LFixedInfo = nil) or (LFixedSize < SizeOf(TVSFixedFileInfo)) then
    Exit;

  Result := Format('%d.%d.%d.%d', [
    HiWord(LFixedInfo^.dwFileVersionMS),
    LoWord(LFixedInfo^.dwFileVersionMS),
    HiWord(LFixedInfo^.dwFileVersionLS),
    LoWord(LFixedInfo^.dwFileVersionLS)]);
end;
{$ENDIF}

class function TDXLogger.GetAppVersion: string;
begin
  TMonitor.Enter(FLock);
  try
    if (FAppVersion = '') and (not FAppVersionResolved) then
    begin
      {$IFDEF MSWINDOWS}
      try
        FAppVersion := GetAppVersionFromExe;
      except
        // Never let version-detection break logging.
        FAppVersion := '';
      end;
      {$ENDIF}
      // TODO macOS/Linux: read version from bundle / packaging metadata.
      // Until then, callers on those platforms must use SetAppVersion.
      FAppVersionResolved := True;
    end;
    Result := FAppVersion;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TDXLogger.SetAppVersion(const AVersion: string);
begin
  TMonitor.Enter(FLock);
  try
    FAppVersion := AVersion;
    // Empty value re-enables auto-detect on next read; a non-empty value
    // is treated as resolved so we never overwrite an explicit setting.
    FAppVersionResolved := AVersion <> '';
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TDXLogger.RegisterProvider(const AProvider: ILogProvider);
var
  LValidationProvider: ILogProviderValidation;
begin
  TMonitor.Enter(Self);
  try
    if not FProviders.Contains(AProvider) then
      FProviders.Add(AProvider);
  finally
    TMonitor.Exit(Self);
  end;

  // Validate connection if provider implements ILogProviderValidation
  if Supports(AProvider, ILogProviderValidation, LValidationProvider) then
    LValidationProvider.ValidateConnection;
end;

procedure TDXLogger.UnregisterProvider(const AProvider: ILogProvider);
begin
  TMonitor.Enter(Self);
  try
    FProviders.Remove(AProvider);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TDXLogger.Log(const AMessage: string; ALevel: TLogLevel = TLogLevel.Info; const ADetails: string = '');
begin
  Log(AMessage, ALevel, ADetails, nil);
end;

function MergePropertiesCallerWins(
  const ABase, ACaller: TArray<TPair<string, string>>): TArray<TPair<string, string>>;
var
  LBaseProp, LCallerProp: TPair<string, string>;
  LFound: Boolean;
  LResult: TArray<TPair<string, string>>;
begin
  // Strategie: Caller-Array komplett uebernehmen, dann Base-Eintraege hinzufuegen
  // deren Key nicht im Caller-Array vorkommt. O(n*m) — n,m typisch < 10.
  SetLength(LResult, 0);

  for LCallerProp in ACaller do
  begin
    SetLength(LResult, Length(LResult) + 1);
    LResult[High(LResult)] := LCallerProp;
  end;

  for LBaseProp in ABase do
  begin
    LFound := False;
    for LCallerProp in ACaller do
      if LCallerProp.Key = LBaseProp.Key then
      begin
        LFound := True;
        Break;
      end;
    if not LFound then
    begin
      SetLength(LResult, Length(LResult) + 1);
      LResult[High(LResult)] := LBaseProp;
    end;
  end;

  Result := LResult;
end;

procedure TDXLogger.Log(const AMessage: string; ALevel: TLogLevel; const ADetails: string;
  const AProperties: TArray<TPair<string, string>>);
var
  LEntry: TLogEntry;
  LProvider: ILogProvider;
  LCallbackProps: TArray<TPair<string, string>>;
  LWindowOpen: Boolean;
  LBuffered: Boolean;
begin
  // Startup configuration window: while open, the entry must be built and
  // buffered regardless of MinLevel (a later SetMinLevel(Trace) must still
  // recover early trace lines at replay time). Once the window is closed,
  // behavior is exactly as before the window existed: skip everything below
  // MinLevel right here. So the early-out below only fires when the window
  // is closed AND the level is filtered.
  //
  // This is a CHEAP PRE-FILTER only — a stale read here (window closes a
  // moment later) merely wastes building an entry that turns out to be
  // filtered; it can never lose data. The authoritative, race-free check is
  // the one immediately before the buffer append below, which re-reads
  // FWindowOpen under the same FLock that guards the append itself.
  TMonitor.Enter(FLock);
  try
    LWindowOpen := FWindowOpen;
  finally
    TMonitor.Exit(FLock);
  end;

  if (not LWindowOpen) and (ALevel < FMinLevel) then
    Exit;

  LEntry.Timestamp := Now;
  LEntry.Level := ALevel;
  LEntry.Message := AMessage;
  LEntry.Details := ADetails;
  LEntry.ThreadID := TThread.CurrentThread.ThreadID;
  LEntry.MemoryInfo := '';

  // Callback-Properties als Basis ermitteln. Exceptions schlucken — broken
  // Callback darf NIE Logging brechen (gleiche Disziplin wie MemoryInfoCallback).
  LCallbackProps := nil;
  if Assigned(FLogPropertiesCallback) then
  begin
    try
      LCallbackProps := FLogPropertiesCallback();
    except
      LCallbackProps := nil;
    end;
  end;

  // Caller-Properties haben Vorrang. Wenn Callback nichts liefert, einfach Caller verwenden.
  if Length(LCallbackProps) = 0 then
    LEntry.Properties := AProperties
  else
    LEntry.Properties := MergePropertiesCallerWins(LCallbackProps, AProperties);

  if Assigned(FMemoryInfoCallback) then
  begin
    try
      LEntry.MemoryInfo := FMemoryInfoCallback();
    except
      // A broken callback must never break logging — swallow silently.
      LEntry.MemoryInfo := '';
    end;
  end;

  // Authoritative, atomic check-and-act: re-read FWindowOpen under the same
  // FLock that guards the buffer mutation, so the "is the window still
  // open" decision and the buffer append happen as one indivisible step
  // with respect to CompleteConfiguration (which closes + snapshots + clears
  // under this very same lock). Without this re-check, an entry built while
  // the window looked open could still land in FStartupBuffer *after*
  // CompleteConfiguration already took its snapshot and cleared it — silent
  // permanent loss for every non-default provider.
  TMonitor.Enter(FLock);
  try
    LBuffered := FWindowOpen;
    if LBuffered then
    begin
      if FStartupBuffer.Count >= C_STARTUP_BUFFER_MAX then
        Inc(FStartupDropCount) // buffer full: drop the newest entry, keep the oldest ones
      else
        FStartupBuffer.Add(LEntry);
    end;
  finally
    TMonitor.Exit(FLock);
  end;

  if LBuffered then
  begin
    // Only the default provider writes immediately, and only if the
    // current MinLevel allows it — all other registered providers receive
    // nothing while the window is (still, as of the check above) open.
    if (ALevel >= FMinLevel) and Assigned(FDefaultProvider) then
      FDefaultProvider.Log(LEntry);
    Exit;
  end;

  // Authoritative level guard for the closed-window path, mirroring the
  // buffered branch's own MinLevel check just above. The cheap unlocked
  // pre-filter at the very top of this method reads FWindowOpen (not
  // FMinLevel) before the entry is built; in the narrow race where the
  // window closes between that read and here, a below-MinLevel entry could
  // otherwise reach the provider loop below unfiltered. Re-checking here —
  // after LBuffered has authoritatively confirmed the window is closed —
  // closes that gap.
  //
  // Defense-in-depth: this line is reachable in the ordinary case too
  // (whenever the window is already stably closed, the pre-filter above
  // already exits before this point is ever reached for a below-MinLevel
  // entry) — but it is only ever *load-bearing*, i.e. the thing that
  // actually stops an entry, in the race window described above, where the
  // window closed concurrently between the unlocked pre-filter read and
  // this point. That interleaving cannot be forced deterministically from
  // a unit test without a production test seam (and a timing-based
  // reproduction would be flaky); the closest thing this codebase has to
  // covering that race under real concurrent pressure is
  // TestNoEntryLostWhenClosingConcurrently (DX.Logger.Tests.Core.pas),
  // which hammers Log from a worker thread while CompleteConfiguration
  // runs concurrently on the main thread. TestClosedWindowFallThroughRespectsMinLevel
  // covers this guard's *code path* (stably-closed-window MinLevel
  // filtering) but not the race interleaving itself — see the comment on
  // that test.
  if ALevel < FMinLevel then
    Exit;

  // Window closed: unchanged single-loop dispatch to every registered
  // provider (including the default one), exactly as before the
  // configuration window existed.
  TMonitor.Enter(Self);
  try
    for LProvider in FProviders do
      LProvider.Log(LEntry);
  finally
    TMonitor.Exit(Self);
  end;
end;

class procedure TDXLogger.CompleteConfiguration;
var
  LSnapshot: TArray<TLogEntry>;
  LDropCount: Cardinal;
  LMinLevel: TLogLevel;
  LInstance: TDXLogger;
  LProvider: ILogProvider;
  LEntry: TLogEntry;
  LWarnEntry: TLogEntry;
  LWasOpen: Boolean;
begin
  // Defaults for the "already closed" path below, where these are never
  // read; silences a spurious W1036 (the compiler's flow analysis cannot
  // see that LWasOpen = True below implies they were assigned inside the
  // lock, since the guarding Exit sits outside the try/finally).
  LSnapshot := nil;
  LDropCount := 0;
  LMinLevel := TLogLevel.Trace;

  // Under the class lock: idempotent check-and-close, then snapshot + clear
  // the buffer and drop counter. LMinLevel is snapshotted here too — once,
  // alongside the buffer — so the entire replay batch below is filtered
  // with one consistent value instead of re-reading the live FMinLevel per
  // entry (which could itself change concurrently while replay is running).
  // Kept separate from the replay dispatch below (which needs the instance
  // monitor) to mirror the discipline used elsewhere: class-level lock for
  // class state, instance monitor for provider dispatch.
  TMonitor.Enter(FLock);
  try
    LWasOpen := FWindowOpen;
    if LWasOpen then
    begin
      FWindowOpen := False;
      LSnapshot := FStartupBuffer.ToArray;
      LDropCount := FStartupDropCount;
      LMinLevel := FMinLevel;
      FStartupBuffer.Clear;
      FStartupDropCount := 0;
    end;

    // CompleteConfiguration ALWAYS signals the watchdog event, on every
    // call (including no-op idempotent calls on an already-closed window)
    // — see the design doc's "Fallback timer" section. This lets a watchdog
    // thread that is still waiting exit immediately instead of sleeping out
    // the remainder of StartupTimeoutMs. Reading/signaling FWatchdogEvent
    // under FLock (the same lock StopWatchdog uses to snapshot-and-clear
    // it) guarantees we never call SetEvent on an event StopWatchdog has
    // already freed: either this runs first and StopWatchdog still finds a
    // live (soon-to-be-freed) event, or StopWatchdog already nil'd the
    // class var first and we simply see Assigned = False here.
    if Assigned(FWatchdogEvent) then
      FWatchdogEvent.SetEvent;
  finally
    TMonitor.Exit(FLock);
  end;

  if not LWasOpen then
    Exit; // already closed before this call: no-op, second and later calls are idempotent

  LInstance := Instance;

  TMonitor.Enter(LInstance);
  try
    // Replay in original order, filtered with the MinLevel valid now (at
    // close time) — not the MinLevel that was in effect when each entry was
    // originally logged. Every provider except the default one takes part;
    // the default provider already wrote each entry immediately when it was
    // logged.
    for LEntry in LSnapshot do
      if LEntry.Level >= LMinLevel then
        for LProvider in LInstance.FProviders do
          if LProvider <> LInstance.FDefaultProvider then
            LProvider.Log(LEntry);

    if LDropCount > 0 then
    begin
      // One final synthetic warning so the operator knows startup entries
      // were lost, sent to the same providers as the replay above.
      LWarnEntry.Timestamp := Now;
      LWarnEntry.Level := TLogLevel.Warn;
      LWarnEntry.Message := Format('DX.Logger: %d startup log entries were dropped (startup buffer full)', [LDropCount]);
      LWarnEntry.Details := '';
      LWarnEntry.ThreadID := TThread.CurrentThread.ThreadID;
      LWarnEntry.MemoryInfo := '';
      LWarnEntry.Properties := nil;

      for LProvider in LInstance.FProviders do
        if LProvider <> LInstance.FDefaultProvider then
          LProvider.Log(LWarnEntry);
    end;
  finally
    TMonitor.Exit(LInstance);
  end;
end;

class procedure TDXLogger.ResetStartupStateForTesting;
begin
  // Join + free any watchdog left over from a previous test/run BEFORE
  // reopening the window, so at most one watchdog is ever armed at a time
  // and the old thread cannot fire CompleteConfiguration concurrently with
  // the state reset below.
  StopWatchdog;

  TMonitor.Enter(FLock);
  try
    FWindowOpen := True;
    FStartupBuffer.Clear;
    FStartupDropCount := 0;
  finally
    TMonitor.Exit(FLock);
  end;

  // Re-arm with the current StartupTimeoutMs (no-op when 0).
  ArmWatchdog;
end;

class procedure TDXLogger.ArmWatchdog;
var
  LTimeoutMs: Cardinal;
  LEvent: TEvent;
  LThread: TThread;
begin
  // Cheap, non-blocking read-and-decide under FLock: nothing is created yet.
  TMonitor.Enter(FLock);
  try
    LTimeoutMs := FStartupTimeoutMs;
    if (LTimeoutMs = 0) or (not FWindowOpen) then
      Exit; // disabled, or window already closed: nothing to guard
  finally
    TMonitor.Exit(FLock);
  end;

  // Create the event and the thread OUTSIDE FLock: both are pure object
  // construction here. TThread.CreateAnonymousThread returns the thread in
  // a not-yet-running (suspended) state -- an explicit Start below is
  // required to actually resume it -- so no watchdog body can execute, and
  // nothing here needs to race FLock.
  LEvent := TEvent.Create(nil, False, False, ''); // auto-reset, initially unsignaled
  LThread := TThread.CreateAnonymousThread(
    procedure
    begin
      if LEvent.WaitFor(LTimeoutMs) = TWaitResult.wrTimeout then
        CompleteConfiguration;
      // wrSignaled (or any other result): CompleteConfiguration already
      // ran/is running elsewhere, or the watchdog was stopped — exit
      // without action either way.
    end);
  LThread.FreeOnTerminate := False; // joinable: StopWatchdog calls WaitFor + Free

  // FIX (review round 1, Critical -- use-after-free window): publish BOTH
  // FWatchdogEvent and FWatchdogThread together, in the SAME FLock section,
  // before Start. The original version assigned FWatchdogEvent, released
  // FLock, created+started the thread, and only THEN (a separate, later
  // FLock section) assigned FWatchdogThread. That left a window where a
  // concurrent StopWatchdog could run in between those two lock sections:
  // it would see FWatchdogEvent already set (so it frees the event) but
  // FWatchdogThread still nil (so it skips the join) -- freeing an event
  // the already-running watchdog closure was still waiting on
  // (use-after-free on the event handle) while leaving that thread itself
  // never stopped. Publishing both together under one lock closes the
  // window completely: StopWatchdog's own snapshot (also taken under
  // FLock, see StopWatchdog) can now only ever observe the fully-armed
  // pair or nothing at all -- never one without the other.
  TMonitor.Enter(FLock);
  try
    FWatchdogEvent := LEvent;
    FWatchdogThread := LThread;
  finally
    TMonitor.Exit(FLock);
  end;

  // Start only after releasing FLock: the watchdog body calls
  // CompleteConfiguration on timeout, which itself re-acquires FLock --
  // that must never run synchronously while this method still holds it.
  // Start itself is non-blocking (it just resumes the already-created,
  // currently-suspended thread), so deferring it to here costs nothing.
  //
  // Residual ordering note (verified while fixing the Critical above, per
  // "verify no other ordering assumption breaks"): between the publish
  // above and this Start call, a concurrent StopWatchdog could in
  // principle snapshot this exact (LThread, LEvent) pair and call
  // LThread.WaitFor before Start has actually run -- WaitFor on a
  // not-yet-started thread blocks until something resumes it, which would
  // only be this same Start call a few lines below. This is not a live
  // hazard given the actual call sites: ArmWatchdog is only ever reached
  // (a) once per process, from Instance's first-access path -- serialized
  // by the double-checked locking there, so no second "first access" can
  // exist to run a concurrent ArmWatchdog for the same instance -- or (b)
  // from ResetStartupStateForTesting, which always calls StopWatchdog
  // BEFORE ArmWatchdog on the SAME calling thread, so no other thread can
  // be inside StopWatchdog for this watchdog generation while this method
  // sits between publish and Start. No code path calls StopWatchdog and
  // ArmWatchdog concurrently on two different threads for the same
  // generation today; if one is ever added, this ordering would need
  // revisiting (e.g. moving Start inside the lock above, trading a larger
  // FLock hold time for eliminating this window outright).
  LThread.Start;
end;

class procedure TDXLogger.StopWatchdog;
var
  LThread: TThread;
  LEvent: TEvent;
begin
  // Snapshot-and-clear under FLock so a concurrent CompleteConfiguration
  // (which reads FWatchdogEvent under the same lock) can never be handed a
  // pointer to an object we are about to free below.
  TMonitor.Enter(FLock);
  try
    LThread := FWatchdogThread;
    LEvent := FWatchdogEvent;
    FWatchdogThread := nil;
    FWatchdogEvent := nil;
  finally
    TMonitor.Exit(FLock);
  end;

  // Release the watchdog from its WaitFor first (it must never be joined
  // while it could still be legitimately blocked for up to the full
  // timeout), then join and free the thread, and finally free the event it
  // was waiting on.
  if Assigned(LEvent) then
    LEvent.SetEvent;
  if Assigned(LThread) then
  begin
    LThread.WaitFor;
    LThread.Free;
  end;
  if Assigned(LEvent) then
    LEvent.Free;
end;

{ Global Functions }

procedure DXLog(const AMessage: string; ALevel: TLogLevel = TLogLevel.Info; const ADetails: string = '');
begin
  TDXLogger.Instance.Log(AMessage, ALevel, ADetails);
end;

procedure DXLogTrace(const AMessage: string);
begin
  TDXLogger.Instance.Log(AMessage, TLogLevel.Trace);
end;

procedure DXLogDebug(const AMessage: string);
begin
  TDXLogger.Instance.Log(AMessage, TLogLevel.Debug);
end;

procedure DXLogInfo(const AMessage: string);
begin
  TDXLogger.Instance.Log(AMessage, TLogLevel.Info);
end;

procedure DXLogWarn(const AMessage: string);
begin
  TDXLogger.Instance.Log(AMessage, TLogLevel.Warn);
end;

procedure DXLogError(const AMessage: string);
begin
  TDXLogger.Instance.Log(AMessage, TLogLevel.Error);
end;

function LogLevelToString(ALevel: TLogLevel): string;
begin
  case ALevel of
    TLogLevel.Trace: Result := 'TRACE';
    TLogLevel.Debug: Result := 'DEBUG';
    TLogLevel.Info:  Result := 'INFO';
    TLogLevel.Warn:  Result := 'WARN';
    TLogLevel.Error: Result := 'ERROR';
    TLogLevel.None:  Result := 'NONE';
  else
    Result := 'UNKNOWN';
  end;
end;

class constructor TDXLogger.Create;
begin
  {$IFDEF DEBUG}
  FMinLevel := TLogLevel.Trace; // Debug Default: log everything
  {$ELSE}
  FMinLevel := TLogLevel.Info; // Release Default: log Info & Errors only
  {$ENDIF}
  FLock := TObject.Create;

  // Configuration window open from process start (see docs/superpowers/
  // specs/2026-08-14-startup-configuration-window-design.md): early log
  // entries survive, unfiltered, until CompleteConfiguration replays them.
  FWindowOpen := True;
  FStartupBuffer := TList<TLogEntry>.Create;
  FStartupDropCount := 0;
  FStartupTimeoutMs := C_DEFAULT_STARTUP_TIMEOUT_MS;
end;

end.
