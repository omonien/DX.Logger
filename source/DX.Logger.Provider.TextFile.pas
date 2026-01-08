unit DX.Logger.Provider.TextFile;

{
  DX.Logger.Provider.TextFile - File logging provider for DX.Logger

  Copyright (c) 2025 Olaf Monien
  SPDX-License-Identifier: MIT

  Simple usage:
    uses
      DX.Logger,
      DX.Logger.Provider.TextFile;

    // File logging is automatically activated by using this unit

  Configuration:
    TFileLogProvider.SetLogFileName('myapp.log');
    TFileLogProvider.SetMaxFileSize(10 * 1024 * 1024); // 10 MB
}

interface

uses
  System.SysUtils,
  System.Classes,
  DX.Logger,
  DX.Logger.Provider.Async;

type
  /// <summary>
  /// File-based log provider with automatic rotation
  /// </summary>
  TFileLogProvider = class(TAsyncLogProvider)
  private
    class var FInstance: TFileLogProvider;
    class var FLogFileName: string;
    class var FMaxFileSize: Int64;
    class var FLock: TObject;
  private
    procedure CheckAndRotateFile;
  protected
    /// <summary>
    /// Write batch of log entries to file
    /// </summary>
    procedure WriteBatch(const AEntries: TArray<TLogEntry>); override;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Set log file name (default: application name + .log)
    /// </summary>
    /// <remarks>
    /// Thread-safe operation protected by locks. Can be safely called at any time.
    /// If a log file already exists with the previous name, it will be
    /// automatically renamed to the new filename to preserve all log entries.
    /// If renaming fails, a new log file is created with a warning message.
    /// </remarks>
    class procedure SetLogFileName(const AFileName: string);

    /// <summary>
    /// Set maximum file size before rotation (default: 10 MB)
    /// </summary>
    /// <remarks>
    /// Must be called before first log entry to avoid race conditions
    /// </remarks>
    class procedure SetMaxFileSize(ASize: Int64);

    /// <summary>
    /// Get singleton instance
    /// </summary>
    class function Instance: TFileLogProvider;

    /// <summary>
    /// Cleanup on application exit
    /// </summary>
    class destructor Destroy;
  end;

implementation

uses
  System.IOUtils,
  System.SyncObjs;

function GetDefaultLogFileName: string;
var
  LAppName: string;
  LLogDir: string;
begin
  LAppName := TPath.GetFileNameWithoutExtension(ParamStr(0));
  if LAppName = '' then
    LAppName := 'Application';

  {$IFDEF MACOS}
  // In a .app bundle the executable directory is not a suitable/writable place.
  // Use the user's (or sandbox container) Logs folder instead.
  LLogDir := TPath.Combine(TPath.GetHomePath, 'Library/Logs');
  LLogDir := TPath.Combine(LLogDir, LAppName);
  Result := TPath.Combine(LLogDir, LAppName + '.log');
  {$ELSE}
  Result := TPath.ChangeExtension(ParamStr(0), '.log');
  {$ENDIF}
end;

const
  C_DEFAULT_MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

{ TFileLogProvider }

constructor TFileLogProvider.Create;
begin
  inherited Create;

  // Set default filename if not set
  if FLogFileName = '' then
    FLogFileName := GetDefaultLogFileName;
end;

destructor TFileLogProvider.Destroy;
begin
  inherited;
end;

class destructor TFileLogProvider.Destroy;
begin
  // During shutdown, just set to nil without freeing
  // The instance will be freed by the reference counting
  FInstance := nil;
  FreeAndNil(FLock);
end;

class function TFileLogProvider.Instance: TFileLogProvider;
begin
  if not Assigned(FInstance) then
  begin
    if not Assigned(FLock) then
      FLock := TObject.Create;

    TMonitor.Enter(FLock);
    try
      if not Assigned(FInstance) then  // Double-checked locking
        FInstance := TFileLogProvider.Create;
    finally
      TMonitor.Exit(FLock);
    end;
  end;
  Result := FInstance;
end;

class procedure TFileLogProvider.SetLogFileName(const AFileName: string);
var
  LOldFileName: string;
  LDirectory: string;
  LStream: TFileStream;
  LBytes: TBytes;
  LLogLine: string;
  LMoveSucceeded: Boolean;
  LErrorMessage: string;
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    LOldFileName := FLogFileName;
    LMoveSucceeded := False;
    LErrorMessage := '';

    // If changing to a different filename and old file exists, rename it
    if (LOldFileName <> '') and (LOldFileName <> AFileName) and TFile.Exists(LOldFileName) then
    begin
      try
        // Ensure directory exists for new filename
        LDirectory := TPath.GetDirectoryName(AFileName);
        if (LDirectory <> '') and not TDirectory.Exists(LDirectory) then
          TDirectory.CreateDirectory(LDirectory);

        // Move the existing log file to the new name
        TFile.Move(LOldFileName, AFileName);
        LMoveSucceeded := True;
      except
        on E: Exception do
        begin
          // Move failed - we'll create a new file and log the situation
          LErrorMessage := E.Message;
        end;
      end;
    end;

    // Update the filename
    FLogFileName := AFileName;

    // If move failed, create new log file with explanation
    if (LOldFileName <> '') and (LOldFileName <> AFileName) and
       TFile.Exists(LOldFileName) and not LMoveSucceeded then
    begin
      try
        // Ensure directory exists
        LDirectory := TPath.GetDirectoryName(AFileName);
        if (LDirectory <> '') and not TDirectory.Exists(LDirectory) then
          TDirectory.CreateDirectory(LDirectory);

        // Create new log file with explanation
        LLogLine := Format('[%s] [WARN] [Thread:%d] Log file name changed from "%s" to "%s". ' +
          'Previous log file could not be renamed (Error: %s). Early log entries remain in: %s' + sLineBreak,
          [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now),
           TThread.Current.ThreadID,
           LOldFileName,
           AFileName,
           LErrorMessage,
           LOldFileName]);

        LBytes := TEncoding.UTF8.GetBytes(LLogLine);
        LStream := TFileStream.Create(FLogFileName, fmCreate or fmShareDenyWrite);
        try
          LStream.WriteBuffer(LBytes[0], Length(LBytes));
        finally
          LStream.Free;
        end;
      except
        // Silently fail if we can't create the new file either
        // Logging system should not crash the application
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TFileLogProvider.SetMaxFileSize(ASize: Int64);
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

procedure TFileLogProvider.CheckAndRotateFile;
var
  LBackupFileName: string;
  LFileSize: Int64;
  LCounter: Integer;
  LSearchRec: TSearchRec;
begin
  // Check if file exists and get its size (Delphi 10 compatible)
  if FindFirst(FLogFileName, faAnyFile, LSearchRec) <> 0 then
    Exit;
  try
    LFileSize := LSearchRec.Size;
  finally
    FindClose(LSearchRec);
  end;

  // Check if rotation is needed
  if LFileSize >= FMaxFileSize then
  begin
    // Create backup filename with timestamp (including milliseconds)
    LBackupFileName := TPath.ChangeExtension(FLogFileName, '') +
      '.' + FormatDateTime('yyyymmdd-hhnnsszzz', Now) +
      TPath.GetExtension(FLogFileName);

    // If file exists, add counter to make it unique
    LCounter := 1;
    while TFile.Exists(LBackupFileName) do
    begin
      LBackupFileName := TPath.ChangeExtension(FLogFileName, '') +
        '.' + FormatDateTime('yyyymmdd-hhnnsszzz', Now) +
        '_' + IntToStr(LCounter) +
        TPath.GetExtension(FLogFileName);
      Inc(LCounter);
    end;

    // Rename current file to backup
    if TFile.Exists(FLogFileName) then
      TFile.Move(FLogFileName, LBackupFileName);

    // New log file will be created automatically on next write
  end;
end;

procedure TFileLogProvider.WriteBatch(const AEntries: TArray<TLogEntry>);
var
  LLogLine: string;
  LDirectory: string;
  LStream: TFileStream;
  LBytes: TBytes;
  LAllBytes: TMemoryStream;
  LEntry: TLogEntry;
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    // Skip logging if no filename is set
    if FLogFileName = '' then
      Exit;

    try
      // Ensure directory exists
      LDirectory := TPath.GetDirectoryName(FLogFileName);
      if (LDirectory <> '') and not TDirectory.Exists(LDirectory) then
        TDirectory.CreateDirectory(LDirectory);

      // Check if rotation is needed BEFORE writing
      try
        CheckAndRotateFile;
      except
        // Ignore rotation errors - logging must never crash the application
      end;

      // Build all log lines in memory first
      LAllBytes := TMemoryStream.Create;
      try
        for LEntry in AEntries do
        begin
          // Format main log entry
          LLogLine := Format('[%s] [%s] [Thread:%d] %s',
            [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', LEntry.Timestamp),
             LogLevelToString(LEntry.Level),
             LEntry.ThreadID,
             LEntry.Message]) + sLineBreak;

          // Convert to bytes and add to stream
          LBytes := TEncoding.UTF8.GetBytes(LLogLine);
          LAllBytes.WriteBuffer(LBytes[0], Length(LBytes));

          // Add details as separate TRACE line if present
          if LEntry.Details <> '' then
          begin
            LLogLine := Format('[%s] [%s] [Thread:%d] %s',
              [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', LEntry.Timestamp),
               'TRACE',
               LEntry.ThreadID,
               LEntry.Details]) + sLineBreak;

            LBytes := TEncoding.UTF8.GetBytes(LLogLine);
            LAllBytes.WriteBuffer(LBytes[0], Length(LBytes));
          end;
        end;

        // Write all bytes in one operation
        if LAllBytes.Size > 0 then
        begin
          try
            if TFile.Exists(FLogFileName) then
              LStream := TFileStream.Create(FLogFileName, fmOpenWrite or fmShareDenyWrite)
            else
              LStream := TFileStream.Create(FLogFileName, fmCreate or fmShareDenyWrite);
            try
              // Seek to end for appending
              LStream.Seek(0, soEnd);
              // Write all bytes
              LAllBytes.Position := 0;
              LStream.CopyFrom(LAllBytes, LAllBytes.Size);
            finally
              LStream.Free;
            end;
          except
            // Silently ignore file I/O errors (e.g. permission problems)
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
  // Set defaults
  TFileLogProvider.FMaxFileSize := C_DEFAULT_MAX_FILE_SIZE;
  TFileLogProvider.FLogFileName := ''; // Effective default: GetDefaultLogFileName
  TDXLogger.Instance.RegisterProvider(TFileLogProvider.Instance);
end.
