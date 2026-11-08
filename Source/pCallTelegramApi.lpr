program pCallTelegramApi;

{$mode objfpc}{$H+}{$codepage utf8}

uses
  Classes, SysUtils, IniFiles, fpjson, jsonparser,
  IdHTTP, IdSSLOpenSSL, IdMultipartFormData;

procedure CheckResponse(const Response: string);
var
  Data, OK: TJSONData;
begin
  Data := GetJSON(Response);
  try
    if Data.JSONType <> jtObject then
      raise Exception.Create('Invalid Bot API response');
    OK := TJSONObject(Data).Find('ok');
    if (OK = nil) or (OK.JSONType <> jtBoolean) then
      raise Exception.Create('Invalid Bot API response: missing ok');
    if not OK.AsBoolean then
      raise Exception.Create('Bot API: ' + TJSONObject(Data).Get('description', 'request failed'));
  finally
    Data.Free;
  end;
end;

procedure Send;
var
  HTTP: TIdHTTP;
  SSL: TIdSSLIOHandlerSocketOpenSSL;
  INI: TIniFile;
  MessageData, FileData: TIdMultiPartFormDataStream;
  ApiBaseUrl, Token, ChatId, ProxyServer, ConfigPath: string;
  ConnectTimeout, ReadTimeout, ProxyPort: Integer;
begin
  Token := '';
  HTTP := nil;
  MessageData := nil;
  FileData := nil;
  try
    try
      if (ParamCount < 1) or (ParamCount > 2) then
        raise Exception.Create('Usage: pCallTelegramApi.exe "message" ["file path"]');
      ConfigPath := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'CallTelegram.ini';
      if not FileExists(ConfigPath) then
        raise Exception.Create('CallTelegram.ini must be beside the executable');
      INI := TIniFile.Create(ConfigPath);
      try
        Token := Trim(INI.ReadString('MAIN', 'Token', ''));
        ChatId := Trim(INI.ReadString('MAIN', 'SendChatId', ''));
        ApiBaseUrl := Trim(INI.ReadString('MAIN', 'ApiBaseUrl', 'https://api.telegram.org'));
        ProxyServer := Trim(INI.ReadString('MAIN', 'ProxyServer', ''));
        ProxyPort := StrToIntDef(INI.ReadString('MAIN', 'ProxyPort', ''), 0);
        ConnectTimeout := INI.ReadInteger('MAIN', 'ConnectTimeout', 30000);
        ReadTimeout := INI.ReadInteger('MAIN', 'ReadTimeout', 3600000);
      finally
        INI.Free;
      end;
      if (Token = '') or (ChatId = '') then
        raise Exception.Create('Token and SendChatId must be configured');
      if ApiBaseUrl = '' then ApiBaseUrl := 'https://api.telegram.org';
      while (Length(ApiBaseUrl) > 0) and (ApiBaseUrl[Length(ApiBaseUrl)] = '/') do
        Delete(ApiBaseUrl, Length(ApiBaseUrl), 1);
      if (Pos('http://', LowerCase(ApiBaseUrl)) <> 1) and
         (Pos('https://', LowerCase(ApiBaseUrl)) <> 1) then
        raise Exception.Create('ApiBaseUrl must start with http:// or https://');
      if (Pos('?', ApiBaseUrl) > 0) or (Pos('#', ApiBaseUrl) > 0) then
        raise Exception.Create('ApiBaseUrl must not contain a query or fragment');
      if (ConnectTimeout <= 0) or (ReadTimeout <= 0) then
        raise Exception.Create('Timeouts must be positive milliseconds');
      if (ProxyServer <> '') and ((ProxyPort < 1) or (ProxyPort > 65535)) then
        raise Exception.Create('ProxyPort must be between 1 and 65535');

      { Open the file before sending anything. Indy streams the attachment
        from disk instead of loading the entire file into memory. }
      if ParamCount = 2 then
      begin
        FileData := TIdMultiPartFormDataStream.Create;
        FileData.AddFormField('chat_id', ChatId, 'utf-8').ContentTransfer := '8bit';
        FileData.AddFile('document', ParamStr(2), 'application/octet-stream');
      end;
      HTTP := TIdHTTP.Create(nil);
      HTTP.ConnectTimeout := ConnectTimeout;
      HTTP.ReadTimeout := ReadTimeout;
      HTTP.ProxyParams.ProxyServer := ProxyServer;
      HTTP.ProxyParams.ProxyPort := ProxyPort;
      { Do not follow redirects with a bot token or replay an upload. }
      HTTP.HandleRedirects := False;
      if Pos('https://', LowerCase(ApiBaseUrl)) = 1 then
      begin
        SSL := TIdSSLIOHandlerSocketOpenSSL.Create(HTTP);
        SSL.ConnectTimeout := ConnectTimeout;
        SSL.ReadTimeout := ReadTimeout;
        SSL.SSLOptions.SSLVersions := [sslvTLSv1_2];
        HTTP.IOHandler := SSL;
      end;
      ApiBaseUrl := ApiBaseUrl + '/bot' + Token + '/';
      MessageData := TIdMultiPartFormDataStream.Create;
      MessageData.AddFormField('chat_id', ChatId, 'utf-8').ContentTransfer := '8bit';
      MessageData.AddFormField('text', AnsiToUtf8(ParamStr(1)), 'utf-8').ContentTransfer := '8bit';
      CheckResponse(HTTP.Post(ApiBaseUrl + 'sendMessage', MessageData));
      if FileData <> nil then
        CheckResponse(HTTP.Post(ApiBaseUrl + 'sendDocument', FileData));
      WriteLn('OK');
    except
      on E: Exception do
      begin
        { Exception messages may include a request URL. Never print the token. }
        if Token <> '' then
          WriteLn(StdErr, 'Error: ', StringReplace(E.Message, Token, '<REDACTED>', [rfReplaceAll]))
        else
          WriteLn(StdErr, 'Error: ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    FileData.Free;
    MessageData.Free;
    HTTP.Free;
  end;
end;

begin
  Send;
end.
