unit DX.Logger.Provider.UI;

{
  DX.Logger.Provider.UI - UI logging provider for DX.Logger

  Copyright (c) 2025 Olaf Monien
  SPDX-License-Identifier: MIT

  Simple usage:
    uses
      DX.Logger,
      DX.Logger.Provider.UI;

    // Register UI provider with TMemo.Lines
    TUILogProvider.Instance.ExternalStrings := MemoInfo.Lines;
    TUILogProvider.Instance.AppendOnTop := False;
    TDXLogger.Instance.RegisterProvider(TUILogProvider.Instance);

    // Unregister when form closes
    TUILogProvider.Instance.ExternalStrings := nil;

  Features:
    - Thread-safe logging to TStrings (TMemo.Lines, etc.)
    - Synchronization to main thread via TThread.Synchronize
    - Optional append on top or bottom
    - Automatic batching for better performance
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Logger,
  DX.Logger.Provider.Async;

type
  /// <summary>
  /// UI-based log provider for displaying logs in TMemo or similar controls
  /// </summary>
  TUILogProvider = class(TAsyncLogProvider)
  private
    class var FInstance: TUILogProvider;
    class var FLock: TObject;
  private
    FExternalStrings: TStrings;
    FAppendOnTop: Boolean;

    procedure UpdateExternalStrings(const AMessages: TArray<string>);
    function FormatLogEntry(const AEntry: TLogEntry): string;
  protected
    /// <summary>
    /// Write batch of log entries to UI
    /// </summary>
    procedure WriteBatch(const AEntries: TArray<TLogEntry>); override;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Set external strings (e.g., TMemo.Lines) to log to
    /// </summary>
    property ExternalStrings: TStrings read FExternalStrings write FExternalStrings;

    /// <summary>
    /// Insert new log messages on top (default: False)
    /// </summary>
    property AppendOnTop: Boolean read FAppendOnTop write FAppendOnTop;

    /// <summary>
    /// Get singleton instance
    /// </summary>
    class function Instance: TUILogProvider;

    /// <summary>
    /// Cleanup on application exit
    /// </summary>
    class destructor Destroy;
  end;

implementation

{ TUILogProvider }

constructor TUILogProvider.Create;
begin
  inherited Create;
  FAppendOnTop := False;
  FExternalStrings := nil;
end;

destructor TUILogProvider.Destroy;
begin
  // Disconnect from external strings first to prevent UI updates during shutdown
  FExternalStrings := nil;
  inherited;
end;

class destructor TUILogProvider.Destroy;
begin
  // During shutdown, just set to nil without freeing
  // The instance will be freed by the reference counting
  FInstance := nil;
  FreeAndNil(FLock);
end;

class function TUILogProvider.Instance: TUILogProvider;
begin
  if not Assigned(FInstance) then
  begin
    if not Assigned(FLock) then
      FLock := TObject.Create;

    TMonitor.Enter(FLock);
    try
      if not Assigned(FInstance) then  // Double-checked locking
        FInstance := TUILogProvider.Create;
    finally
      TMonitor.Exit(FLock);
    end;
  end;
  Result := FInstance;
end;

function TUILogProvider.FormatLogEntry(const AEntry: TLogEntry): string;
begin
  Result := Format('[%s] [%s] %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', AEntry.Timestamp),
     LogLevelToString(AEntry.Level),
     AEntry.Message]);
end;

procedure TUILogProvider.WriteBatch(const AEntries: TArray<TLogEntry>);
var
  LMessages: TList<string>;
  LEntry: TLogEntry;
  LMessagesArray: TArray<string>;
begin
  // Skip if no external strings assigned
  if not Assigned(FExternalStrings) then
    Exit;

  // Format all entries (main message + optional details as separate line)
  LMessages := TList<string>.Create;
  try
    for LEntry in AEntries do
    begin
      // Add main log message
      LMessages.Add(FormatLogEntry(LEntry));

      // Add details as separate TRACE line if present (truncated to 50 chars)
      if LEntry.Details <> '' then
      begin
        var LDetailsDisplay: string;
        if Length(LEntry.Details) > 50 then
          LDetailsDisplay := Copy(LEntry.Details, 1, 50) + '... [see log file for details]'
        else
          LDetailsDisplay := LEntry.Details;

        LMessages.Add(Format('[%s] [%s] %s',
          [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', LEntry.Timestamp),
           'TRACE',
           LDetailsDisplay]));
      end;
    end;

    // Convert to array
    LMessagesArray := LMessages.ToArray;
  finally
    LMessages.Free;
  end;

  // Update UI
  UpdateExternalStrings(LMessagesArray);
end;

procedure TUILogProvider.UpdateExternalStrings(const AMessages: TArray<string>);
begin
  // Skip if no external strings
  if not Assigned(FExternalStrings) then
    Exit;

  // Synchronize to main thread for UI update
  TThread.Synchronize(nil,
    procedure
    var
      LMessage: string;
    begin
      if not Assigned(FExternalStrings) then
        Exit;

      try
        FExternalStrings.BeginUpdate;
        try
          if FAppendOnTop then
          begin
            // Insert at top in reverse order to maintain chronological order
            for var i := High(AMessages) downto Low(AMessages) do
              FExternalStrings.Insert(0, AMessages[i]);
          end
          else
          begin
            // Append at bottom
            for LMessage in AMessages do
              FExternalStrings.Add(LMessage);
          end;
        finally
          FExternalStrings.EndUpdate;
        end;
      except
        // Silently ignore UI update errors
      end;
    end);
end;

end.

