unit DX.Logger.Provider.JSONL;

{
  DX.Logger.Provider.JSONL - JSON Lines (JSONL) file logging provider for DX.Logger

  Copyright (c) 2025 Olaf Monien
  SPDX-License-Identifier: MIT

  Simple usage:
    uses
      DX.Logger,
      DX.Logger.Provider.JSONL;

    // JSONL file logging is automatically activated by using this unit

  Configuration:
    TJSONLLogProvider.SetLogFileName('myapp.jsonl');
    TJSONLLogProvider.SetMaxFileSize(10 * 1024 * 1024); // 10 MB

  Each log entry is written as a single JSON object on its own line:

    {"timestamp":"2026-08-08T12:34:56.789Z","level":"INFO","message":"...","threadId":1234,...}
}

interface

uses
  System.SysUtils,
  System.Classes,
  DX.Logger,
  DX.Logger.Provider.Async;

type
  /// <summary>
  /// JSON Lines (JSONL) file-based log provider with automatic rotation.
  /// Writes one structured JSON object per line — human-readable and
  /// machine-parseable. Ideal for log shipping, analytics pipelines and
  /// offline analysis with tools such as jq.
  /// </summary>
  TJSONLLogProvider = class(TAsyncLogProvider)
  private
    class var FInstance: TJSONLLogProvider;
    class var FLogFileName: string;
    class var FMaxFileSize: Int64;
    class var FLock: TObject;
  private
    procedure CheckAndRotateFile;
    function FormatJSONL(const AEntry: TLogEntry): string;
  protected
    /// <summary>
    /// Write batch of log entries as JSON Lines to file
    /// </summary>
    procedure WriteBatch(const AEntries: TArray<TLogEntry>); override;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Set log file name (default: application name + .jsonl)
    /// </summary>
    /// <remarks>
    /// Thread-safe. If a log file already exists under the previous name it is
    /// renamed to the new filename so existing entries are preserved.
    /// </remarks>
    class procedure SetLogFileName(const AFileName: string);

    /// <summary>
    /// Get current log file name
    /// </summary>
    class function GetLogFileName: string;

    /// <summary>
    /// Set maximum file size before rotation (default: 10 MB)
    /// </summary>
    /// <remarks>
    /// Should be called before the first log entry to avoid race conditions.
    /// </remarks>
    class procedure SetMaxFileSize(ASize: Int64);

    /// <summary>
    /// Get singleton instance
    /// </summary>
    class function Instance: TJSONLLogProvider;

    /// <summary>
    /// Cleanup on application exit
    /// </summary>
    class destructor Destroy;
  end;

implementation

uses
  System.IOUtils,
  System.SyncObjs,
  System.JSON,
  System.DateUtils,
  System.Generics.Collections
  {$IFDEF MSWINDOWS}
  , Winapi.Windows
  {$ENDIF}
  {$IF Defined(IOS)}
  , iOSapi.Foundation
  , Macapi.Helpers
  {$ELSEIF Defined(MACOS)}
  , Macapi.Foundation
  , Macapi.Helpers
  {$ENDIF}
  ;

{$IF Defined(MACOS) or Defined(IOS)}
function GetBundleIdentifier(const ADefault: string): string;
var
  LBundle: NSBundle;
  LId: NSString;
begin
  Result := ADefault;
  LBundle := TNSBundle.Wrap(TNSBundle.OCClass.mainBundle);
  if LBundle <> nil then
  begin
    LId := LBundle.bundleIdentifier;
    if LId <> nil then
      Result := NSStrToStr(LId);
  end;
end;

function GetAppleLogFileName(const AAppName: string): string;
var
  LBundleId: string;
begin
  LBundleId := GetBundleIdentifier(AAppName);
  Result := TPath.Combine(TPath.GetLibraryPath, 'Logs', LBundleId, AAppName + '.jsonl');
end;
{$ENDIF}

function GetDefaultLogFileName: string;
var
  LAppName: string;
begin
  LAppName := TPath.GetFileNameWithoutExtension(ParamStr(0));
  if LAppName = '' then
    LAppName := 'Application';

  {$IFDEF IOS}
    {$IF Defined(DEBUG) or Defined(TRACE)}
    Result := GetAppleLogFileName(LAppName);
    {$ELSE}
    Result := '';
    {$ENDIF}
  {$ELSEIF Defined(MACOS)}
  Result := GetAppleLogFileName(LAppName);
  {$ELSE}
  Result := TPath.ChangeExtension(ParamStr(0), '.jsonl');
  {$ENDIF}
end;

const
  C_DEFAULT_MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB
  C_WRITE_RETRY_COUNT = 10;
  C_WRITE_RETRY_DELAY_MS = 5;

{ TJSONLLogProvider }

constructor TJSONLLogProvider.Create;
begin
  inherited Create;

  if FLogFileName = '' then
    FLogFileName := GetDefaultLogFileName;
end;

destructor TJSONLLogProvider.Destroy;
begin
  inherited;
end;

class destructor TJSONLLogProvider.Destroy;
begin
  FInstance := nil;
  FreeAndNil(FLock);
end;

class function TJSONLLogProvider.Instance: TJSONLLogProvider;
begin
  if not Assigned(FInstance) then
  begin
    if not Assigned(FLock) then
      FLock := TObject.Create;

    TMonitor.Enter(FLock);
    try
      if not Assigned(FInstance) then
        FInstance := TJSONLLogProvider.Create;
    finally
      TMonitor.Exit(FLock);
    end;
  end;
  Result := FInstance;
end;

class procedure TJSONLLogProvider.SetLogFileName(const AFileName: string);
var
  LOldFileName: string;
  LDirectory: string;
  LStream: TFileStream;
  LBytes: TBytes;
  LLogLine: string;
  LMoveSucceeded: Boolean;
  LErrorMessage: string;
  LShareMode: Word;
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  // Drain pending writes against the previous filename first.
  if Assigned(FInstance) then
    FInstance.Flush;

  TMonitor.Enter(FLock);
  try
    LOldFileName := FLogFileName;
    LMoveSucceeded := False;
    LErrorMessage := '';

    if (LOldFileName <> '') and (LOldFileName <> AFileName) and TFile.Exists(LOldFileName) then
    begin
      try
        LDirectory := TPath.GetDirectoryName(AFileName);
        if (LDirectory <> '') and not TDirectory.Exists(LDirectory) then
          TDirectory.CreateDirectory(LDirectory);

        TFile.Move(LOldFileName, AFileName);
        LMoveSucceeded := True;
      except
        on E: Exception do
          LErrorMessage := E.Message;
      end;
    end;

    FLogFileName := AFileName;

    // If rename failed, write a warning entry into the new file.
    if (LOldFileName <> '') and (LOldFileName <> AFileName) and
       TFile.Exists(LOldFileName) and not LMoveSucceeded then
    begin
      try
        LDirectory := TPath.GetDirectoryName(AFileName);
        if (LDirectory <> '') and not TDirectory.Exists(LDirectory) then
          TDirectory.CreateDirectory(LDirectory);

        LLogLine := Format(
          '{"timestamp":"%s","level":"WARN","message":"Log file name changed from \"%s\" to \"%s\". ' +
          'Previous log file could not be renamed (Error: %s). Early log entries remain in: %s","threadId":%d}' + sLineBreak,
          [FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', TTimeZone.Local.ToUniversalTime(Now)),
           LOldFileName,
           AFileName,
           LErrorMessage,
           LOldFileName,
           TThread.CurrentThread.ThreadID]);

        LBytes := TEncoding.UTF8.GetBytes(LLogLine);
        {$IFDEF MSWINDOWS}
        LShareMode := fmShareDenyWrite;
        {$ELSE}
        LShareMode := fmShareDenyNone;
        {$ENDIF}
        LStream := TFileStream.Create(FLogFileName, fmCreate or LShareMode);
        try
          LStream.WriteBuffer(LBytes[0], Length(LBytes));
        finally
          LStream.Free;
        end;
      except
        // Logging must never crash the application
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TJSONLLogProvider.GetLogFileName: string;
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    Result := FLogFileName;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TJSONLLogProvider.SetMaxFileSize(ASize: Int64);
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    FMaxFileSize := ASize;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TJSONLLogProvider.CheckAndRotateFile;
var
  LBackupFileName: string;
  LFileSize: Int64;
  LCounter: Integer;
  LSearchRec: TSearchRec;
begin
  if FindFirst(FLogFileName, faAnyFile, LSearchRec) <> 0 then
    Exit;
  try
    LFileSize := LSearchRec.Size;
  finally
    System.SysUtils.FindClose(LSearchRec);
  end;

  if LFileSize >= FMaxFileSize then
  begin
    LBackupFileName := TPath.ChangeExtension(FLogFileName, '') +
      '.' + FormatDateTime('yyyymmdd-hhnnsszzz', Now) +
      TPath.GetExtension(FLogFileName);

    LCounter := 1;
    while TFile.Exists(LBackupFileName) do
    begin
      LBackupFileName := TPath.ChangeExtension(FLogFileName, '') +
        '.' + FormatDateTime('yyyymmdd-hhnnsszzz', Now) +
        '_' + IntToStr(LCounter) +
        TPath.GetExtension(FLogFileName);
      Inc(LCounter);
    end;

    if TFile.Exists(FLogFileName) then
      TFile.Move(FLogFileName, LBackupFileName);
  end;
end;

function TJSONLLogProvider.FormatJSONL(const AEntry: TLogEntry): string;
var
  LJson: TJSONObject;
  LTimestamp: string;
  LAppVersion: string;
  LProp: TPair<string, string>;
begin
  // ISO 8601 UTC — consistent with the Seq provider / CLEF
  LTimestamp := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',
    TTimeZone.Local.ToUniversalTime(AEntry.Timestamp));

  LAppVersion := TDXLogger.GetAppVersion;

  LJson := TJSONObject.Create;
  try
    LJson.AddPair('timestamp', LTimestamp);
    LJson.AddPair('level', LogLevelToString(AEntry.Level));
    LJson.AddPair('message', AEntry.Message);
    LJson.AddPair('threadId', TJSONNumber.Create(AEntry.ThreadID));

    if AEntry.MemoryInfo <> '' then
      LJson.AddPair('memoryInfo', AEntry.MemoryInfo);

    if AEntry.Details <> '' then
      LJson.AddPair('details', AEntry.Details);

    if LAppVersion <> '' then
      LJson.AddPair('appVersion', LAppVersion);

    // Structured properties as top-level fields. Skip empty keys and
    // anything starting with '@' (reserved by CLEF / common conventions).
    for LProp in AEntry.Properties do
    begin
      if (LProp.Key = '') or LProp.Key.StartsWith('@') then
        Continue;
      // Avoid overwriting the canonical fields we already wrote.
      if SameText(LProp.Key, 'timestamp') or
         SameText(LProp.Key, 'level') or
         SameText(LProp.Key, 'message') or
         SameText(LProp.Key, 'threadId') or
         SameText(LProp.Key, 'memoryInfo') or
         SameText(LProp.Key, 'details') or
         SameText(LProp.Key, 'appVersion') then
        Continue;
      LJson.AddPair(LProp.Key, LProp.Value);
    end;

    Result := LJson.ToJSON;
  finally
    LJson.Free;
  end;
end;

procedure TJSONLLogProvider.WriteBatch(const AEntries: TArray<TLogEntry>);
var
  LLogLine: string;
  LDirectory: string;
  LStream: TFileStream;
  LBytes: TBytes;
  LAllBytes: TMemoryStream;
  LEntry: TLogEntry;
  LShareMode: Word;
  LOpenMode: Word;
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    if FLogFileName = '' then
      Exit;

    try
      LDirectory := TPath.GetDirectoryName(FLogFileName);
      if (LDirectory <> '') and not TDirectory.Exists(LDirectory) then
        TDirectory.CreateDirectory(LDirectory);

      try
        CheckAndRotateFile;
      except
        // Rotation must never break logging
      end;

      LAllBytes := TMemoryStream.Create;
      try
        for LEntry in AEntries do
        begin
          LLogLine := FormatJSONL(LEntry) + sLineBreak;
          LBytes := TEncoding.UTF8.GetBytes(LLogLine);
          LAllBytes.WriteBuffer(LBytes[0], Length(LBytes));
        end;

        if LAllBytes.Size > 0 then
        begin
          {$IFDEF MSWINDOWS}
          LShareMode := fmShareDenyWrite;
          {$ELSE}
          LShareMode := fmShareDenyNone;
          {$ENDIF}
          LOpenMode := fmOpenReadWrite or LShareMode;

          var LSucceeded: Boolean := False;
          var LLastError: string := '';
          var LAttempt: Integer;
          for LAttempt := 1 to C_WRITE_RETRY_COUNT do
          begin
            try
              if TFile.Exists(FLogFileName) then
                LStream := TFileStream.Create(FLogFileName, LOpenMode)
              else
                LStream := TFileStream.Create(FLogFileName, fmCreate or LShareMode);
              try
                LStream.Seek(0, soEnd);
                LAllBytes.Position := 0;
                LStream.CopyFrom(LAllBytes, LAllBytes.Size);
              finally
                LStream.Free;
              end;
              LSucceeded := True;
              Break;
            except
              on E: Exception do
              begin
                LLastError := E.ClassName + ': ' + E.Message;
                if LAttempt < C_WRITE_RETRY_COUNT then
                  Sleep(C_WRITE_RETRY_DELAY_MS);
              end;
            end;
          end;

          if not LSucceeded then
          begin
            try
              var LReport: string := Format(
                '[DX.Logger] TJSONLLogProvider dropped batch of %d bytes for "%s" ' +
                'after %d attempts: %s',
                [LAllBytes.Size, FLogFileName, C_WRITE_RETRY_COUNT, LLastError]);
              {$IFDEF MSWINDOWS}
              OutputDebugString(PChar(LReport));
              {$ELSE}
              try
                Writeln(ErrOutput, LReport);
              except
              end;
              {$ENDIF}
            except
            end;
          end;
        end;
      finally
        LAllBytes.Free;
      end;
    except
      // Logging system must never crash the application
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

initialization
  TJSONLLogProvider.FMaxFileSize := C_DEFAULT_MAX_FILE_SIZE;
  TJSONLLogProvider.FLogFileName := ''; // Effective default: GetDefaultLogFileName
  TDXLogger.Instance.RegisterProvider(TJSONLLogProvider.Instance);
end.
