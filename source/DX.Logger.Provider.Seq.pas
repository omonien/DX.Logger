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
    TSeqLogProvider.SetSource('MyApplication'); // Optional, defaults to EXE name
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
  DX.Logger,
  DX.Logger.Provider.Async;

type
  /// <summary>
  /// Seq-based log provider with asynchronous batching
  /// </summary>
  TSeqLogProvider = class(TAsyncLogProvider, ILogProviderValidation)
  private
    class var FInstance: TSeqLogProvider;
    class var FServerUrl: string;
    class var FApiKey: string;
    class var FSource: string;
    class var FInstanceName: string;  // Instance identifier (e.g., "at.esculenta.elkerest-t")
    class var FBatchSize: Integer;
    class var FFlushInterval: Integer;
    class var FLock: TObject;
  private
    procedure SendBatch(const ABatch: TArray<TLogEntry>);
    function LogLevelToSeqLevel(ALevel: TLogLevel): string;
    function FormatCLEF(const AEntry: TLogEntry): string;
    // ILogProviderValidation implementation - calls class function
    function DoValidateConnection: Boolean;
    function ILogProviderValidation.ValidateConnection = DoValidateConnection;
  protected
    /// <summary>
    /// Write batch of log entries to Seq
    /// </summary>
    procedure WriteBatch(const AEntries: TArray<TLogEntry>); override;

    /// <summary>
    /// Override batch size from configuration
    /// </summary>
    function GetBatchSize: Integer; override;

    /// <summary>
    /// Override flush interval from configuration
    /// </summary>
    function GetFlushInterval: Integer; override;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>
    /// Set Seq server URL (e.g., 'https://seqsrv1.esculenta.at')
    /// </summary>
    class procedure SetServerUrl(const AUrl: string);

    /// <summary>
    /// Set Seq API key for authentication
    /// </summary>
    class procedure SetApiKey(const AKey: string);

    /// <summary>
    /// Set source identifier (default: application EXE name)
    /// </summary>
    class procedure SetSource(const ASource: string);

    /// <summary>
    /// Set instance identifier (e.g., "at.esculenta.elkerest-t")
    /// </summary>
    class procedure SetInstance(const AInstance: string);

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
    /// Cleanup on application exit
    /// </summary>
    class destructor Destroy;

    /// <summary>
    /// Validates the Seq server connection by sending a test request.
    /// Logs success or detailed error information to help diagnose configuration issues.
    /// Call this after configuring URL and API key to verify the connection works.
    /// </summary>
    /// <returns>True if connection is valid, False otherwise</returns>
    class function ValidateConnection: Boolean;
  end;

implementation

uses
  System.SyncObjs,
  System.Net.HttpClient,
  System.Net.URLClient,
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
end;

destructor TSeqLogProvider.Destroy;
begin
  inherited;
end;

class destructor TSeqLogProvider.Destroy;
begin
  // During shutdown, just set to nil without freeing
  // The instance will be freed by the reference counting
  FInstance := nil;
  FreeAndNil(FLock);
end;

class function TSeqLogProvider.Instance: TSeqLogProvider;
begin
  if not Assigned(FInstance) then
  begin
    if not Assigned(FLock) then
      FLock := TObject.Create;

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
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    FServerUrl := AUrl;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSeqLogProvider.SetApiKey(const AKey: string);
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    FApiKey := AKey;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSeqLogProvider.SetSource(const ASource: string);
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    FSource := ASource;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSeqLogProvider.SetInstance(const AInstance: string);
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    FInstanceName := AInstance;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSeqLogProvider.SetBatchSize(ASize: Integer);
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

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
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    if AInterval > 0 then
      FFlushInterval := AInterval;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSeqLogProvider.GetBatchSize: Integer;
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    Result := FBatchSize;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSeqLogProvider.GetFlushInterval: Integer;
begin
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    Result := FFlushInterval;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TSeqLogProvider.WriteBatch(const AEntries: TArray<TLogEntry>);
begin
  // Send batch to Seq server
  SendBatch(AEntries);
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
  LSource: string;
  LInstance: string;
begin
  // Format timestamp as ISO 8601
  LTimestamp := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"',
    TTimeZone.Local.ToUniversalTime(AEntry.Timestamp));

  // Get source and instance (thread-safe)
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    LSource := FSource;
    LInstance := FInstanceName;
  finally
    TMonitor.Exit(FLock);
  end;

  LJson := TJSONObject.Create;
  try
    LJson.AddPair('@t', LTimestamp);
    LJson.AddPair('@l', LogLevelToSeqLevel(AEntry.Level));
    LJson.AddPair('@m', AEntry.Message);
    LJson.AddPair('ThreadId', TJSONNumber.Create(AEntry.ThreadID));

    // Add details if present
    if AEntry.Details <> '' then
      LJson.AddPair('Details', AEntry.Details);

    // Add instance if configured
    if LInstance <> '' then
      LJson.AddPair('Instance', LInstance);

    // Add source if configured
    if LSource <> '' then
      LJson.AddPair('source', LSource);

    Result := LJson.ToJSON;
  finally
    LJson.Free;
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

function TSeqLogProvider.DoValidateConnection: Boolean;
begin
  // Delegate to class function
  Result := ValidateConnection;
end;

class function TSeqLogProvider.ValidateConnection: Boolean;
var
  LHttpClient: THTTPClient;
  LResponse: IHTTPResponse;
  LUrl: string;
  LApiKey: string;
  LStatusCode: Integer;
  LStatusText: string;
begin
  Result := False;

  // Get current configuration (thread-safe)
  if not Assigned(FLock) then
    FLock := TObject.Create;

  TMonitor.Enter(FLock);
  try
    LUrl := FServerUrl;
    LApiKey := FApiKey;
  finally
    TMonitor.Exit(FLock);
  end;

  // Check if URL is configured
  if LUrl = '' then
  begin
    TDXLogger.Instance.Log('Seq configuration error: Server URL is not configured', TLogLevel.Error);
    Exit;
  end;

  LHttpClient := THTTPClient.Create;
  try
    // Set reasonable timeout for validation
    LHttpClient.ConnectionTimeout := 5000;  // 5 seconds
    LHttpClient.ResponseTimeout := 10000;   // 10 seconds

    // Set API key header if configured
    if LApiKey <> '' then
      LHttpClient.CustomHeaders['X-Seq-ApiKey'] := LApiKey;

    try
      // Use /api endpoint to check server availability
      // This endpoint returns server info and validates API key
      LResponse := LHttpClient.Get(LUrl + '/api');
      LStatusCode := LResponse.StatusCode;
      LStatusText := LResponse.StatusText;

      case LStatusCode of
        200:
          begin
            TDXLogger.Instance.Log(Format('Seq connection validated successfully - Server: %s', [LUrl]), TLogLevel.Info);
            Result := True;
          end;
        401, 403:
          begin
            TDXLogger.Instance.Log(
              Format('Seq authentication failed - Server: %s, Status: %d %s - Check your API key configuration',
                [LUrl, LStatusCode, LStatusText]), TLogLevel.Error);
          end;
        404:
          begin
            TDXLogger.Instance.Log(
              Format('Seq API endpoint not found - Server: %s, Status: %d %s - Verify the server URL is correct',
                [LUrl, LStatusCode, LStatusText]), TLogLevel.Error);
          end;
      else
        TDXLogger.Instance.Log(
          Format('Seq connection failed - Server: %s, Status: %d %s',
            [LUrl, LStatusCode, LStatusText]), TLogLevel.Error);
      end;

    except
      on E: ENetHTTPClientException do
      begin
        // Network-level errors (connection refused, timeout, DNS failure, etc.)
        TDXLogger.Instance.Log(
          Format('Seq connection failed - Server: %s - Network error: %s',
            [LUrl, E.Message]), TLogLevel.Error);
      end;
      on E: Exception do
      begin
        // Any other unexpected errors
        TDXLogger.Instance.Log(
          Format('Seq connection failed - Server: %s - Unexpected error (%s): %s',
            [LUrl, E.ClassName, E.Message]), TLogLevel.Error);
      end;
    end;
  finally
    LHttpClient.Free;
  end;
end;

initialization
  // Set defaults
  TSeqLogProvider.FBatchSize := C_DEFAULT_BATCH_SIZE;
  TSeqLogProvider.FFlushInterval := C_DEFAULT_FLUSH_INTERVAL;
  TSeqLogProvider.FServerUrl := '';
  TSeqLogProvider.FApiKey := '';
  TSeqLogProvider.FSource := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
  TSeqLogProvider.FInstanceName := '';

end.

