# CallTelegramApi

Windows 命令列傳送 Telegram 訊息與檔案，可指定自架 Telegram Bot API，支援串流上傳 1 GB 檔案。

## 使用方式

將 `Release` 內的 EXE、兩個 SSL DLL 與 `CallTelegram.ini` 放在同一資料夾，編輯設定：

```ini
[MAIN]
Token=你的機器人Token
SendChatId=你的聊天室ID
ApiBaseUrl=http://127.0.0.1:8081
ConnectTimeout=30000
ReadTimeout=3600000
ProxyServer=
ProxyPort=
```

`ApiBaseUrl` 填伺服器的根網址，不加 `/bot<Token>` 或方法名稱；可包含反向代理的路徑前綴，例如 `https://bot-api.example.com/telegram`。省略或留空時使用 `https://api.telegram.org`。HTTP 自架位址不需要載入 SSL DLL；HTTPS 延用專案附帶的 32 位元 OpenSSL DLL。

逾時單位為毫秒，連線預設 30 秒，等待回應預設 1 小時；慢速大檔案可提高 `ReadTimeout`。此值是網路讀取逾時，並非整次上傳的總時限。

```bat
pCallTelegramApi.exe "測試訊息"
pCallTelegramApi.exe "傳送備份" "D:\Backup\backup.zip"
```

仍維持先傳文字、再傳檔案的行為。檔案會從磁碟串流上傳，不會整份載入記憶體。設定檔固定從 EXE 所在資料夾讀取，因此可從排程或其他資料夾呼叫。成功回傳結束碼 `0`，設定、網路或 API 失敗回傳 `1`。若文字已成功、檔案失敗，文字不會撤回；程式不會自動重試，以免重複傳送。

## 1 GB 檔案的伺服器條件

Telegram 官方雲端 Bot API 的一般檔案上傳上限為 50 MB。單純更換網址不會提高上限：指定的伺服器必須是啟用 `--local` 的 [Telegram Bot API Server](https://github.com/tdlib/telegram-bot-api)，官方支援上傳最高 2000 MB。

1. 準備並啟動 Bot API Server，使用自己的 `api_id`、`api_hash`，加上 `--local`。若由其他電腦連入，設定適當的監聽位址與網路存取權限。
2. 若機器人原先使用雲端 API，先依官方流程向雲端呼叫 `logOut`，再切換到自架伺服器。本工具不會自行登出或搬移機器人。
3. 將 `ApiBaseUrl` 改為該伺服器位址。若經過反向代理，也必須放行大於 1 GB 的請求並調整代理逾時。

參考：[本機 Bot API 功能與限制](https://core.telegram.org/bots/api#using-a-local-bot-api-server)、[切換伺服器流程](https://github.com/tdlib/telegram-bot-api#moving-a-bot-to-a-local-server)。

## 編譯與測試

使用 Free Pascal 3.2.2 與 Indy 10 原始碼，不再需要 Synapse。此版本使用 Indy commit `e8f8c51f197813257f1157691cdf398b2f80615c` 編譯測試。

```powershell
git clone https://github.com/IndySockets/Indy.git ..\Indy
git -C ..\Indy checkout e8f8c51f197813257f1157691cdf398b2f80615c
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Fpc 'C:\FPC\3.2.2\bin\i386-win32\fpc.exe' -IndyRoot ..\Indy
python -m unittest discover -s tests -v
$env:TEST_LARGE_UPLOAD = '1'
python -m unittest discover -s tests -v
```

測試會複製編譯後的 EXE 至暫存目錄，使用假的 Token 和本機 HTTP 模擬伺服器，不會傳送 Telegram 訊息。大檔案測試實際從 EXE 上傳 1 GiB（1,073,741,824 bytes），需暫存磁碟空間與本機傳輸時間；它驗證客戶端傳輸，不代表實際自架伺服器或 Telegram 已完成收件。

Lazarus 使用 `Source/pCallTelegramApi.lpi`，需安裝 `indylaz` 套件。

## 更新

2026/11/08：新增 `ApiBaseUrl`、可設定逾時、API 回應檢查與非零錯誤結束碼，修正設定檔尋找位置及資源釋放，加入離線與 1 GiB 上傳測試。

2020/04/06：修正 SSL 版本導致不能傳送訊息。
