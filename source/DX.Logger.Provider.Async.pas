unit DX.Logger.Provider.Async;

{
  DX.Logger.Provider.Async - Base class for asynchronous log providers
  
  Copyright (c) 2025 Olaf Monien
  SPDX-License-Identifier: MIT
  
  This base class provides:
    - Thread-safe singleton pattern
    - Worker thread with message queue
    - Automatic batching of log messages
    - Clean shutdown handling
    
  Usage:
    Inherit from TAsyncLogProvider and implement WriteBatch method:
    
    type
      TMyLogProvider = class(TAsyncLogProvider)
      protected
        procedure WriteBatch(const AEntries: TArray<TLogEntry>); override;
      end;
}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  DX.Logger;

type
  /// <summary>
  /// Base class for asynchronous log providers with batching support
  /// </summary>
  TAsyncLogProvider = class abstract(TInterfacedObject, ILogProvider)
  private
    FPendingMessages: TThreadedQueue<TLogEntry>;
    FWorkerThread: TThread;
    FShutdown: Boolean;
    
    procedure WorkerThreadExecute;
  protected
    /// <summary>
    /// Override this method to implement actual logging
    /// Called from worker thread with batched entries
    /// </summary>
    procedure WriteBatch(const AEntries: TArray<TLogEntry>); virtual; abstract;
    
    /// <summary>
    /// Override to customize batch size (default: 10)
    /// </summary>
    function GetBatchSize: Integer; virtual;
    
    /// <summary>
    /// Override to customize flush interval in ms (default: 100)
    /// </summary>
    function GetFlushInterval: Integer; virtual;
    
    /// <summary>
    /// Override to customize queue depth (default: 1000)
    /// </summary>
    function GetQueueDepth: Integer; virtual;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>
    /// Log message (queued for async processing)
    /// </summary>
    procedure Log(const AEntry: TLogEntry);
  end;

implementation

uses
  System.SyncObjs,
  System.DateUtils;

{ TAsyncLogProvider }

constructor TAsyncLogProvider.Create;
begin
  inherited Create;
  FShutdown := False;
  FPendingMessages := TThreadedQueue<TLogEntry>.Create(GetQueueDepth, INFINITE, GetFlushInterval);
  
  // Start worker thread
  FWorkerThread := TThread.CreateAnonymousThread(WorkerThreadExecute);
  FWorkerThread.FreeOnTerminate := False;
  FWorkerThread.Start;
end;

destructor TAsyncLogProvider.Destroy;
begin
  FShutdown := True;
  
  // Wait for worker thread to finish
  if Assigned(FWorkerThread) then
  begin
    FWorkerThread.Terminate;
    FWorkerThread.WaitFor;
    FreeAndNil(FWorkerThread);
  end;
  
  FreeAndNil(FPendingMessages);
  inherited;
end;

function TAsyncLogProvider.GetBatchSize: Integer;
begin
  Result := 10;
end;

function TAsyncLogProvider.GetFlushInterval: Integer;
begin
  Result := 100; // 100ms
end;

function TAsyncLogProvider.GetQueueDepth: Integer;
begin
  Result := 1000;
end;

procedure TAsyncLogProvider.Log(const AEntry: TLogEntry);
begin
  if not FShutdown then
    FPendingMessages.PushItem(AEntry);
end;

procedure TAsyncLogProvider.WorkerThreadExecute;
var
  LBatch: TList<TLogEntry>;
  LEntry: TLogEntry;
  LWaitResult: TWaitResult;
  LLastFlush: TDateTime;
begin
  LBatch := TList<TLogEntry>.Create;
  try
    LLastFlush := Now;

    while not FShutdown do
    begin
      // Try to get a message with timeout
      LWaitResult := FPendingMessages.PopItem(LEntry);

      // Exit if queue was shut down
      if LWaitResult = TWaitResult.wrAbandoned then
        Break;

      if LWaitResult = TWaitResult.wrSignaled then
      begin
        LBatch.Add(LEntry);
      end;

      // Flush batch if interval elapsed or we have enough messages
      if (LBatch.Count > 0) and
         ((MilliSecondsBetween(Now, LLastFlush) >= GetFlushInterval) or
          (LBatch.Count >= GetBatchSize)) then
      begin
        try
          WriteBatch(LBatch.ToArray);
        except
          // Silently ignore errors in WriteBatch to prevent thread crash
        end;
        LBatch.Clear;
        LLastFlush := Now;
      end;
    end;

    // Final flush on shutdown
    if LBatch.Count > 0 then
    begin
      try
        WriteBatch(LBatch.ToArray);
      except
        // Silently ignore errors during shutdown
      end;
    end;
  finally
    LBatch.Free;
  end;
end;

end.

