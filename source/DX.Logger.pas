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
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

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
  private
    FProviders: TList<ILogProvider>;
    FMemoryInfoCallback: TMemoryInfoCallback;

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

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  {$IFDEF ANDROID}
  Androidapi.Log,
  {$ENDIF}
  {$IFDEF MACOS}
	Macapi.Helpers,
	Macapi.Foundation,
  {$ENDIF}
  {$IFDEF LINUX}
  Posix.Syslog,
  {$ENDIF}
  System.SyncObjs;

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

  // Register default platform-specific provider
  RegisterProvider(TDefaultLogProvider.Create);
end;

destructor TDXLogger.Destroy;
begin
  FreeAndNil(FProviders);
  inherited;
end;

class destructor TDXLogger.Destroy;
begin
  FreeAndNil(FInstance);
  FreeAndNil(FLock);
end;

class function TDXLogger.Instance: TDXLogger;
begin
  if not Assigned(FInstance) then
  begin
    TMonitor.Enter(FLock);
    try
      if not Assigned(FInstance) then  // Double-checked locking
        FInstance := TDXLogger.Create;
    finally
      TMonitor.Exit(FLock);
    end;
  end;
  Result := FInstance;
end;

class procedure TDXLogger.SetMinLevel(ALevel: TLogLevel);
begin
  FMinLevel := ALevel;
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

procedure TDXLogger.Log(const AMessage: string; ALevel: TLogLevel; const ADetails: string;
  const AProperties: TArray<TPair<string, string>>);
var
  LEntry: TLogEntry;
  LProvider: ILogProvider;
begin
  // Check minimum log level
  if ALevel < FMinLevel then
    Exit;

  LEntry.Timestamp := Now;
  LEntry.Level := ALevel;
  LEntry.Message := AMessage;
  LEntry.Details := ADetails;
  LEntry.ThreadID := TThread.CurrentThread.ThreadID;
  LEntry.MemoryInfo := '';
  LEntry.Properties := AProperties;
  if Assigned(FMemoryInfoCallback) then
  begin
    try
      LEntry.MemoryInfo := FMemoryInfoCallback();
    except
      // A broken callback must never break logging — swallow silently.
      LEntry.MemoryInfo := '';
    end;
  end;

  TMonitor.Enter(Self);
  try
    for LProvider in FProviders do
      LProvider.Log(LEntry);
  finally
    TMonitor.Exit(Self);
  end;
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
end;

end.
