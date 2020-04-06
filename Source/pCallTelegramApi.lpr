{%BuildWorkingDir ../Release}
{%RunWorkingDir ../Release}
{%RunFlags MESSAGES+}
program pCallTelegramApi;

{$mode objfpc}{$H+}

uses {$IFDEF UNIX} {$IFDEF UseCThreads}
  cthreads, {$ENDIF} {$ENDIF}
  Classes,
  SysUtils,
  CustApp,
  { you can add units after this }
  idhttp,
  SynaCode,
  IniFiles,
  IdSSLOpenSSL,
  IdMultipartFormData;

type

  { CallTelegramApi }

  CallTelegramApi = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

  { CallTelegramApi }
  procedure CallTelegramApi.DoRun;
  var
    HTTP: TIdHTTP;
    SSL     : TIdSSLIOHandlerSocketOpenSSL;
    Url: string;
    INI: TINIFile;
    ProxyServer, Token, SendChatId: string;
    ProxyPort: integer;
    FormData: TIdMultipartFormDataStream;
  begin
    { add your program here }
    if (ParamCount = 0) or (ParamCount > 2) then
    begin
      writeln('Exampl: Param1 is SendText');
      writeln('        Param2 is SendFilePath');
      Terminate;
      exit;
    end;

    // 讀取ini設定
    INI := TINIFile.Create('CallTelegram.ini');
    ProxyServer := INI.ReadString('MAIN', 'ProxyServer', '');
    ProxyPort := INI.ReadInteger('MAIN', 'ProxyPort', 0);
    Token := INI.ReadString('MAIN', 'Token', '');
    SendChatId := INI.ReadString('MAIN', 'SendChatId', '');
    INI.Free;

    HTTP := TIdHTTP.Create(nil);
    SSL                         := TIdSSLIOHandlerSocketOpenSSL.Create(HTTP);
       SSL.ConnectTimeout          := HTTP.ConnectTimeout;
       SSL.ReadTimeout             := HTTP.ReadTimeout;
       SSL.SSLOptions.SSLVersions  := [sslvTLSv1, sslvTLSv1_1, sslvTLSv1_2];
       HTTP.IOHandler              := SSL;
    with HTTP do
    begin
      ProxyParams.ProxyServer := ProxyServer;
      ProxyParams.ProxyPort := ProxyPort;
      HandleRedirects := True;
      Request.ContentType := 'multipart/form-data';
    end;

    //傳送訊息
    Url :=
      'https://api.telegram.org/bot' + Token + '/sendMessage?chat_id=' +
      SendChatId + '&text=' + EncodeUrl(AnsiToUtf8(ParamStr(1)));
    HTTP.Get(Url);

    //--------------------------------------------------------------------------
    //傳送檔案
    if ParamCount = 2 then
    begin
      try
        Url := 'https://api.telegram.org/bot' + Token + '/sendDocument';

        FormData := TIdMultiPartFormDataStream.Create;
        FormData.AddFormField('chat_id', SendChatId);
        FormData.AddFile('document', ParamStr(2));
        HTTP.Post(Url, FormData);
      except
        on E: EIdHTTPProtocolException do
        begin
          WriteLn(E.Message);
          WriteLn(E.ErrorMessage);
        end;
        on E: Exception do
        begin
          WriteLn(E.Message);
        end;
      end;
    end;

    HTTP.Free;
    // stop program loop
    Terminate;
  end;

  constructor CallTelegramApi.Create(TheOwner: TComponent);
  begin
    inherited Create(TheOwner);
    StopOnException := True;
  end;

  destructor CallTelegramApi.Destroy;
  begin
    inherited Destroy;
  end;

var
  Application: CallTelegramApi;
begin
  Application := CallTelegramApi.Create(nil);
  Application.Title := 'TelegramApi';
  Application.Run;
  Application.Free;
end.
