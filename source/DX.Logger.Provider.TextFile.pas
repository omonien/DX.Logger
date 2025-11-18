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
  DX.Logger;

type
  /// <summary>
  /// File-based log provider with automatic rotation
  /// </summary>
  TFileLogProvider = class(TInterfacedObject, ILogProvider)
  private
    class var FInstance: TFileLogProvider;
    class var FLogFileName: string;
    class var FMaxFileSize: Int64;
    class var FLock: TObject;
  private
    procedure CheckAndRotateFile;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Log message to file
    /// </summary>
    procedure Log(const AEntry: TLogEntry);

    /// <summary>
    /// Set log file name (default: application name + .log)
    /// </summary>
    /// <remarks>
    /// Must be called before first log entry to avoid race conditions
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
    /// Close the current log file (mainly for testing purposes)
    /// </summary>
    procedure Close;

    /// <summary>
    /// Cleanup on application exit
    /// </summary>
    class destructor Destroy;
  end;

implementation

uses
  System.IOUtils,
  System.SyncObjs;

const
  C_DEFAULT_MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB

{ TFileLogProvider }

constructor TFileLogProvider.Create;
begin
  inherited Create;

  // Set default filename if not set
  if FLogFileName = '' then
    FLogFileName := TPath.ChangeExtension(ParamStr(0), '.log');
end;

destructor TFileLogProvider.Destroy;
begin
  // Nothing to clean up - we don't keep files open
  inherited;
end;

class destructor TFileLogProvider.Destroy;
begin
  FreeAndNil(FInstance);
  FreeAndNil(FLock);
end;

class function TFileLogProvider.Instance: TFileLogProvider;
begin
  if not Assigned(FInstance) then
  begin
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
begin
  TMonitor.Enter(FLock);
  try
    FLogFileName := AFileName;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TFileLogProvider.SetMaxFileSize(ASize: Int64);
begin
  TMonitor.Enter(FLock);
  try
    FMaxFileSize := ASize;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TFileLogProvider.Close;
begin
  // Nothing to do - we don't keep files open
  // This method exists for testing purposes (to ensure all data is flushed)
end;

procedure TFileLogProvider.CheckAndRotateFile;
var
  LBackupFileName: string;
  LFileSize: Int64;
  LCounter: Integer;
begin
  // Check if file exists and get its size
  if not TFile.Exists(FLogFileName) then
    Exit;

  LFileSize := TFile.GetSize(FLogFileName);

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

procedure TFileLogProvider.Log(const AEntry: TLogEntry);
var
  LLogLine: string;
  LDirectory: string;
  LStream: TFileStream;
  LBytes: TBytes;
begin
  TMonitor.Enter(FLock);
  try
    // Skip logging if no filename is set
    if FLogFileName = '' then
      Exit;

    // Ensure directory exists
    LDirectory := TPath.GetDirectoryName(FLogFileName);
    if (LDirectory <> '') and not TDirectory.Exists(LDirectory) then
      TDirectory.CreateDirectory(LDirectory);

    // Format log entry
    LLogLine := Format('[%s] [%s] [Thread:%d] %s',
      [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', AEntry.Timestamp),
       LogLevelToString(AEntry.Level),
       AEntry.ThreadID,
       AEntry.Message]) + sLineBreak;

    // Convert to bytes
    LBytes := TEncoding.UTF8.GetBytes(LLogLine);

    // Check if rotation is needed BEFORE writing
    // This ensures we don't rotate while other threads might be writing
    CheckAndRotateFile;

    // Open file in append mode, write, and close
    if TFile.Exists(FLogFileName) then
      LStream := TFileStream.Create(FLogFileName, fmOpenWrite or fmShareDenyWrite)
    else
      LStream := TFileStream.Create(FLogFileName, fmCreate or fmShareDenyWrite);
    try
      // Seek to end for appending
      LStream.Seek(0, soEnd);
      // Write bytes
      LStream.WriteBuffer(LBytes[0], Length(LBytes));
    finally
      LStream.Free;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

initialization
  // Set defaults
  TFileLogProvider.FLock := TObject.Create;
  TFileLogProvider.FMaxFileSize := C_DEFAULT_MAX_FILE_SIZE;
  TFileLogProvider.FLogFileName := '';

  // Note: File provider is NOT auto-registered
  // Users must manually register it after setting the filename:
  //   TFileLogProvider.SetLogFileName('myapp.log');
  //   TDXLogger.Instance.RegisterProvider(TFileLogProvider.Instance);

end.
