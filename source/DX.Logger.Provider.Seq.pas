unit DX.Logger.Provider.Seq;

{
  DX.Logger.Provider.Seq - Seq logging provider for DX.Logger

  Copyright (c) 2025 Olaf Monien
  SPDX-License-Identifier: MIT

  Simple usage:
    uses
      DX.Logger,
      DX.Logger.Provider.Seq;

    // Configure and register Seq provider
    TSeqLogProvider.SetServerUrl('https://your-seq-server.example.com');
    TSeqLogProvider.SetApiKey('your-api-key-here');
    TDXLogger.Instance.RegisterProvider(TSeqLogProvider.Instance);

  Features:
    - Asynchronous logging (non-blocking)
    - Automatic batching of log events
    - CLEF (Compact Log Event Format) support
    - Configurable batch size and flush interval
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Logger;

type
  /// <summary>
  /// Seq-based log provider with asynchronous batching
  /// </summary>
  TSeqLogProvider = class(TInterfacedObject, ILogProvider)
  private
    class var FInstance: TSeqLogProvider;
    class var FServerUrl: string;
    class var FApiKey: string;
    class var FBatchSize: Integer;
    class var FFlushInterval: Integer;
    class var FLock: TObject;
  private
    FEventQueue: TThreadedQueue<TLogEntry>;
    FWorkerThread: TThread;
    FShutdown: Boolean;

    procedure WorkerThreadExecute;
    procedure SendBatch(const ABatch: TArray<TLogEntry>);
    function LogLevelToSeqLevel(ALevel: TLogLevel): string;
    function FormatCLEF(const AEntry: TLogEntry): string;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Log message to Seq (queued for async processing)
    /// </summary>
    procedure Log(const AEntry: TLogEntry);

    /// <summary>
    /// Set Seq server URL (e.g., 'https://seqsrv1.esculenta.at')
    /// </summary>
    class procedure SetServerUrl(const AUrl: string);

    /// <summary>
    /// Set Seq API key for authentication
    /// </summary>
    class procedure SetApiKey(const AKey: string);

    /// <summary>
    /// Set batch size (default: 10)
    /// </summary>
    class procedure SetBatchSize(ASize: Integer);

    /// <summary>
    /// Set flush interval in milliseconds (default: 2000)
    /// </summary>
    class procedure SetFlushInterval(AInterval: Integer);

    /// <summary>
    /// Get singleton instance
    /// </summary>
    class function Instance: TSeqLogProvider;

    /// <summary>
    /// Flush all pending log entries immediately
    /// </summary>
    procedure Flush;

    /// <summary>
    /// Cleanup on application exit
    /// </summary>
    class destructor Destroy;
  end;

implementation

uses
  System.SyncObjs,
  System.Net.HttpClient,
  System.DateUtils,
  System.JSON;

const
  C_DEFAULT_BATCH_SIZE = 10;
  C_DEFAULT_FLUSH_INTERVAL = 2000; // 2 seconds
  C_QUEUE_DEPTH = 1000;

{ TSeqLogProvider }

constructor TSeqLogProvider.Create;
begin
  inherited Create;
  FShutdown := False;
  FEventQueue := TThreadedQueue<TLogEntry>.Create(C_QUEUE_DEPTH, INFINITE, 100);

  // Start worker thread
  FWorkerThread := TThread.CreateAnonymousThread(WorkerThreadExecute);
  FWorkerThread.FreeOnTerminate := False;
  FWorkerThread.Start;
end;

destructor TSeqLogProvider.Destroy;
begin
  // Signal shutdown
  FShutdown := True;

  // Close queue to unblock worker thread
  if Assigned(FEventQueue) then
    FEventQueue.DoShutDown;

  // Wait for worker thread to finish
  if Assigned(FWorkerThread) then
  begin
    FWorkerThread.WaitFor;
    FreeAndNil(FWorkerThread);
  end;

  FreeAndNil(FEventQueue);
  inherited;
end;

class destructor TSeqLogProvider.Destroy;
begin
  // Don't free instance here - let it be freed naturally
  // This prevents access violations during shutdown
  FLock.Free;
  FLock := nil;
end;

class function TSeqLogProvider.Instance: TSeqLogProvider;
begin
  if not Assigned(FInstance) then
  begin
    TMonitor.Enter(FLock);
    try
      if not Assigned(FInstance) then  // Double-checked locking
        FInstance := TSeqLogProvider.Create;
    finally
      TMonitor.Exit(FLock);
    end;
  end;
  Result := FInstance;
end;

class procedure TSeqLogProvider.SetServerUrl(const AUrl: string);
begin
  TMonitor.Enter(FLock);
  try
    FServerUrl := AUrl;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSeqLogProvider.SetApiKey(const AKey: string);
begin
  TMonitor.Enter(FLock);
  try
    FApiKey := AKey;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSeqLogProvider.SetBatchSize(ASize: Integer);
begin
  TMonitor.Enter(FLock);
  try
    if ASize > 0 then
      FBatchSize := ASize;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSeqLogProvider.SetFlushInterval(AInterval: Integer);
begin
  TMonitor.Enter(FLock);
  try
    if AInterval > 0 then
      FFlushInterval := AInterval;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TSeqLogProvider.Log(const AEntry: TLogEntry);
begin
  // Queue the entry for async processing
  FEventQueue.PushItem(AEntry);
end;

procedure TSeqLogProvider.Flush;
var
  LBatch: TList<TLogEntry>;
  LEntry: TLogEntry;
begin
  LBatch := TList<TLogEntry>.Create;
  try
    // Drain the queue
    while FEventQueue.PopItem(LEntry) = TWaitResult.wrSignaled do
      LBatch.Add(LEntry);

    // Send if we have entries
    if LBatch.Count > 0 then
      SendBatch(LBatch.ToArray);
  finally
    LBatch.Free;
  end;
end;

function TSeqLogProvider.LogLevelToSeqLevel(ALevel: TLogLevel): string;
begin
  case ALevel of
    TLogLevel.Trace: Result := 'Verbose';
    TLogLevel.Debug: Result := 'Debug';
    TLogLevel.Info:  Result := 'Information';
    TLogLevel.Warn:  Result := 'Warning';
    TLogLevel.Error: Result := 'Error';
  else
    Result := 'Information';
  end;
end;

function TSeqLogProvider.FormatCLEF(const AEntry: TLogEntry): string;
var
  LJson: TJSONObject;
  LTimestamp: string;
begin
  // Format timestamp as ISO 8601
  LTimestamp := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',
    TTimeZone.Local.ToUniversalTime(AEntry.Timestamp));

  LJson := TJSONObject.Create;
  try
    LJson.AddPair('@t', LTimestamp);
    LJson.AddPair('@l', LogLevelToSeqLevel(AEntry.Level));
    LJson.AddPair('@m', AEntry.Message);
    LJson.AddPair('ThreadId', TJSONNumber.Create(AEntry.ThreadID));

    Result := LJson.ToJSON;
  finally
    LJson.Free;
  end;
end;

procedure TSeqLogProvider.WorkerThreadExecute;
var
  LBatch: TList<TLogEntry>;
  LEntry: TLogEntry;
  LLastFlush: TDateTime;
  LWaitResult: TWaitResult;
begin
  LBatch := TList<TLogEntry>.Create;
  try
    LLastFlush := Now;

    while not FShutdown do
    begin
      // Try to get an entry with timeout
      LWaitResult := FEventQueue.PopItem(LEntry);

      // Exit if queue was shut down
      if LWaitResult = TWaitResult.wrAbandoned then
        Break;

      if LWaitResult = TWaitResult.wrSignaled then
      begin
        LBatch.Add(LEntry);

        // Send batch if size reached
        if LBatch.Count >= FBatchSize then
        begin
          SendBatch(LBatch.ToArray);
          LBatch.Clear;
          LLastFlush := Now;
        end;
      end;

      // Send batch if flush interval elapsed
      if (LBatch.Count > 0) and
         (MilliSecondsBetween(Now, LLastFlush) >= FFlushInterval) then
      begin
        SendBatch(LBatch.ToArray);
        LBatch.Clear;
        LLastFlush := Now;
      end;
    end;

    // Final flush on shutdown
    if LBatch.Count > 0 then
      SendBatch(LBatch.ToArray);
  finally
    LBatch.Free;
  end;
end;

procedure TSeqLogProvider.SendBatch(const ABatch: TArray<TLogEntry>);
var
  LHttpClient: THTTPClient;
  LRequest: IHTTPRequest;
  LResponse: IHTTPResponse;
  LPayload: TStringBuilder;
  LEntry: TLogEntry;
  LStream: TStringStream;
begin
  // Skip if no server URL configured
  if FServerUrl = '' then
    Exit;

  LHttpClient := THTTPClient.Create;
  try
    LPayload := TStringBuilder.Create;
    try
      // Build newline-delimited JSON (CLEF format)
      for LEntry in ABatch do
      begin
        LPayload.AppendLine(FormatCLEF(LEntry));
      end;

      LStream := TStringStream.Create(LPayload.ToString, TEncoding.UTF8);
      try
        // Create request
        LRequest := LHttpClient.GetRequest('POST', FServerUrl + '/api/events/raw');
        LRequest.SourceStream := LStream;

        // Set headers
        LRequest.SetHeaderValue('Content-Type', 'application/vnd.serilog.clef');
        if FApiKey <> '' then
          LRequest.SetHeaderValue('X-Seq-ApiKey', FApiKey);

        // Send request (ignore errors to avoid blocking logging)
        try
          LResponse := LHttpClient.Execute(LRequest);
          // Optionally log response status for debugging
          // if LResponse.StatusCode <> 201 then
          //   ; // Handle error
        except
          // Silently ignore HTTP errors to prevent logging from breaking the app
        end;
      finally
        LStream.Free;
      end;
    finally
      LPayload.Free;
    end;
  finally
    LHttpClient.Free;
  end;
end;

initialization
  // Set defaults
  TSeqLogProvider.FLock := TObject.Create;
  TSeqLogProvider.FBatchSize := C_DEFAULT_BATCH_SIZE;
  TSeqLogProvider.FFlushInterval := C_DEFAULT_FLUSH_INTERVAL;
  TSeqLogProvider.FServerUrl := '';
  TSeqLogProvider.FApiKey := '';

end.

