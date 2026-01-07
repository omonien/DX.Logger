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
    Error
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
  end;

  /// <summary>
  /// Interface for log providers
  /// </summary>
  ILogProvider = interface
    ['{8F3D2A1B-4C5E-4F6D-8A9B-1C2D3E4F5A6B}']
    procedure Log(const AEntry: TLogEntry);
  end;

  /// <summary>
  /// Core logger class (singleton)
  /// </summary>
  TDXLogger = class sealed
  private
    class var FInstance: TDXLogger;
    class var FMinLevel: TLogLevel;
    class var FLock: TObject;
  private
    FProviders: TList<ILogProvider>;

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
    /// Get singleton instance
    /// </summary>
    class function Instance: TDXLogger;

    /// <summary>
    /// Set minimum log level (messages below this level are ignored)
    /// </summary>
    class procedure SetMinLevel(ALevel: TLogLevel);
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
  {$IFDEF ANDROID}
  LMarshaller: TMarshaller;
  {$ENDIF}
begin
  LFormattedMessage := Format('[%s] [%s] %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', AEntry.Timestamp),
     LogLevelToString(AEntry.Level),
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
  NSLog(StrToNSStr(LFormattedMessage));
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

procedure TDXLogger.RegisterProvider(const AProvider: ILogProvider);
begin
  TMonitor.Enter(Self);
  try
    if not FProviders.Contains(AProvider) then
      FProviders.Add(AProvider);
  finally
    TMonitor.Exit(Self);
  end;
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
