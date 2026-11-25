# Lionheart FX 儀器預約系統

**管理單位：中醫藥核心平台實驗室**  
**網站管理者：Dr. Shih-Hsuan (James) Chan**

Apple 風格、繁體中文、自適應桌機 / iPad / 手機的週預約網站。開放週一至週日 08:00–20:00，以每小時為單位，可一次預約同一天 08:00–20:00 之間的連續多小時時段。

## 網站檔案
- `index.html`：網站首頁與預約表單
- `styles.css`：響應式版面
- `app.js`：週曆及預約操作
- `config.js`：Supabase 連線設定
- `supabase.sql`：資料庫資料表及權限
- `.nojekyll`：GitHub Pages 相容設定

## GitHub Pages
進入 **Settings → Pages → Build and deployment**，選擇 **Deploy from a branch**，Branch 選 `main`，Folder 選 `/(root)`，儲存後可透過：
https://jessechan27.github.io/lionheart-fx-booking/

## 啟用多人同步
1. 在 https://supabase.com 建立專案。
2. 將 `supabase.sql` 貼到 SQL Editor 執行。
3. 在 `config.js` 輸入 Project URL 和公開的 anon/publishable key。
4. 重新部署後，預約將跨裝置共用；使用者可一次選擇日期、開始與結束時間，整段預約會以單一交易寫入，遇到任何時段衝突則整筆取消。

**注意**：沒有設定 Supabase 時，資料只存在使用者自己的瀏覽器 localStorage，僅供示範。不要把 service_role/secret key 上傳 GitHub。正式使用建議啟用帳號或校內 Email 驗證及防濫用機制；目前系統為公開匿名預約，訪客能看到預約者姓名、單位與備註（但不公開 Email）。

管理者可在 Supabase Table Editor 查閱、修改、刪除預約。

## 多小時預約（2026-11 更新）
點選「新增預約」或週曆空白時段，選擇日期、開始時間及結束時間（例如 09:00–13:00），再填寫一次姓名、單位、Email 與備註即可。資料庫仍以每小時一筆儲存，但由同一次操作建立，整段時間必須全部可用才會成功。

**既有 Supabase 專案務必重新執行最新版 `supabase.sql`**，新增 `create_booking_range` RPC 函式；僅更新 GitHub 前端而未執行 SQL 時，雲端模式的新預約會失敗。本機示範模式不需 SQL，但不同裝置不會同步。


## 會員註冊與登入（2026-11 更新）
網站已加入 Supabase Auth 電子郵件註冊／登入、忘記密碼、會員資料編輯及登出。註冊時填寫姓名、實驗室、Email 與密碼；登入後預約表單會顯示會員姓名與實驗室，無需重複填寫。

**部署必要步驟**
1. 在 Supabase 建立專案，將最新的 `supabase.sql` **完整執行**（舊資料表會保留，並增加 profiles 與 user_id）。
2. Supabase → Authentication → Providers → Email：啟用 Email 登入及建議開啟「Confirm email」。
3. Supabase → Authentication → URL Configuration：Site URL 設為 `https://jessechan27.github.io/lionheart-fx-booking/`，Redirect URLs 加入相同網址。
4. 將 Supabase Project URL 與 **publishable/anon key** 填入 `config.js`，不要上傳 secret/service_role key。
5. 重新整理網站，測試註冊 → Email 驗證 → 登入 → 預約 2 小時 → 編輯會員資料 → 登出。

**權限與資料安全**
- 只有已登入會員可以查閱週曆與新增預約。
- 個人 profile 只能由本人讀取／修改；預約使用的姓名、實驗室與 Email 由伺服器從會員資料取得，不能由前端偽造。
- 公開給已登入會員的預約資訊不含 Email；管理者可於 Supabase 後台檢視完整紀錄。
- 舊版匿名新增權限已撤銷；既有歷史預約保留。
- 預約仍以每小時一列儲存，整段時間在同一資料庫交易內建立，遇到衝突全部回滾。
- 若尚未設定 Supabase，會員功能會顯示未設定狀態，無法新增預約；不再使用本機示範資料。


## 管理者後台（2026-11）
進入 `admin.html`：https://jessechan27.github.io/lionheart-fx-booking/admin.html

功能：
- 審核會員：待審核／核准／拒絕／停用；未核准者無法新增預約。
- 依日期範圍統計各實驗室預約使用時數（每小時紀錄算 1 小時）與使用者人數；可匯出 CSV。
- 查看預約紀錄，取消單一小時或同一批連續預約的所有小時；可匯出 CSV。
- 僅 `admin_users` 內的授權管理者可使用後台，伺服器端 RPC 每次都驗證權限。

**必要部署步驟：**
1. 先確認原本 `supabase.sql` 已執行，且 `config.js` 已填寫 Supabase URL 與公開 anon/publishable key。
2. 在 Supabase SQL Editor 執行 **`admin_migration.sql`**（不是只更新前端）。
3. 管理者先在網站註冊並完成 Email 驗證。
4. 在 Supabase SQL Editor 以專案管理權限執行以下 SQL，將該帳號設為第一位管理員：

```sql
insert into public.admin_users(user_id)
select id from auth.users where email = 'YOUR_ADMIN_EMAIL@example.com'
on conflict (user_id) do nothing;
```

將示例 Email 換成您註冊使用的 Email。管理員權限**不可**由前端註冊自行取得。
5. 重新登入網站，首頁會顯示「管理後台」連結。打開 `admin.html` 以管理者帳號登入。
6. 測試一般會員註冊後為待審核、管理員核准後才能預約；測試報表及取消預約。

**注意：** 未設定 Supabase 或尚未執行管理者 migration 時，後台不會正常運作。管理者後台的權限判斷在資料庫執行，並非只靠隱藏前端按鈕。既有會員預設為待審核，須逐一核准。取消預約為刪除紀錄，目前未提供稽核日誌或復原功能。使用時數為預約時數，非實際儀器運轉紀錄。

## 新會員申請：申請時間記錄與 Email 通知（2026-11）
- **記錄申請時間**：每位會員的 `profiles.requested_at` 記錄申請預約權限（註冊）的時間；管理後台「會員審核」表格顯示「申請時間」（台灣時間），依申請時間由新到舊排序。既有會員以帳號建立時間補上。
- **通知管理者**：有新使用者註冊時，寄信給管理者，信中註明「有新使用者需要管理者核准」，附姓名、實驗室／單位、Email、申請時間及管理後台連結。
- **通知使用者**：管理者在後台按「核准」後，寄信給該使用者。主旨「Lionheart FX註冊申請通過」，內文「（使用者姓名）您好，您申請之Lionheart FX使用帳號業已通過，可以開始使用預約系統。」署名「中醫藥核心平台實驗室」。

運作方式：Supabase 資料庫觸發器透過 `pg_net` 呼叫管理者自己的 Google Apps Script（`google_apps_script_mailer.gs`），由管理者的 Gmail 寄出，寄件人顯示為「中醫藥核心平台實驗室」。不需要自有網域或其他寄信服務。寄信在背景送出，**寄信失敗不會影響註冊或審核**。前端不會暴露驗證碼或管理者 Email。

**必要部署步驟：**
1. 以**管理者 Google 帳號**登入 https://script.google.com →「新專案」，專案命名為 `Lionheart FX Mailer`。
2. **刪除預設程式碼（包含 `function myFunction() {}`）**，貼上本 repo 的 `google_apps_script_mailer.gs` 全部內容，按 Ctrl+S 儲存。
3. 確認「執行」右邊的函式選單選的是 `setup`（不是 `myFunction`）→「執行」→ 依提示授權（出現「Google 尚未驗證這個應用程式」時，按「進階」→「前往 Lionheart FX Mailer」；這是您自己的程式）。執行完成後：
   - 信箱會收到兩封測試信（管理者通知、核准通知）。
   - 下方「執行紀錄」會顯示 `MAILER_TOKEN`，請複製備用。
   - 管理者收件 Email 預設為部署者的 Gmail；如需更改，到「專案設定 → 指令碼屬性」修改 `ADMIN_EMAIL`。
4. 右上角「部署」→「新增部署作業」→ 類型選「網頁應用程式」；**執行身分：我**；**誰可以存取：所有人** →「部署」，複製「網頁應用程式網址」（`/exec` 結尾）。
5. 在 Supabase SQL Editor 執行 **`new_member_application_migration.sql`**（需已執行 `supabase.sql` 與 `admin_migration.sql`）。若之後重新執行 `admin_migration.sql`，請再執行一次本檔。
6. 在 Supabase SQL Editor 執行（換成步驟 4 的網址與步驟 3 的 MAILER_TOKEN；會存入 Supabase Vault，不會出現在 GitHub）：

```sql
select lionheart_private.set_mailer_settings('https://script.google.com/macros/s/……/exec', '您的MAILER_TOKEN');
```

7. 從資料庫寄測試信並確認：

```sql
select lionheart_private.send_mail(jsonb_build_object('type','approved','name','測試使用者','email','您的Email'));
-- 數秒後查詢：status_code 為 302 或 200 代表已送達 Apps Script
select id, status_code, error_msg, created from net._http_response order by created desc limit 5;
```

8. 用一個新 Email 在網站註冊 → 確認管理者收到通知 → 在後台核准 → 確認該 Email 收到「Lionheart FX註冊申請通過」。

**注意：**
- 新會員通知在使用者送出註冊時寄出，此時對方可能尚未完成 Email 驗證；完成驗證前對方無法登入。
- 停用後再次核准，會再寄一次核准通知信。管理者帳號不會收到核准通知。
- Gmail 個人帳號透過 Apps Script 每日最多寄給 100 位收件者。
- 修改 `google_apps_script_mailer.gs` 後，須在 Apps Script「部署 → 管理部署作業」編輯並選「新版本」，網址不變。
- 收不到信時，到 Apps Script 左側「執行項目」查看 `doPost` 紀錄：出現「MAILER_TOKEN 不符」代表步驟 6 的驗證碼與指令碼屬性不同；`net._http_response` 出現 401/403/404 多為部署時「誰可以存取」未選「所有人」或網址錯誤。

## 取消預約（2026-11）
登入後點選週曆上已預約的時段，「預約資訊」視窗會依權限顯示取消按鈕：
- **會員**：可取消**自己**的預約，且限尚未開始的時段；已開始或已過去的時段不能取消。
- **管理者**：可取消**任何會員**的預約（包含已過去的時段），與管理後台「預約紀錄管理」相同。
- 「取消此小時」只取消該 1 小時；同一次預約有多個小時時，另有「取消整段預約（N 小時）」。會員取消整段時，只會取消其中尚未開始的時段。
- 取消即刪除紀錄，時段立即重新開放，無法復原。權限由資料庫函式 `cancel_booking` 檢查，不能由前端繞過。

**必要部署步驟（順序很重要）：**
1. 先在 Supabase SQL Editor 執行 **`cancel_booking_migration.sql`**（需已執行 `supabase.sql` 與 `admin_migration.sql`）。
2. 再推送前端（`index.html`、`app.js`、`styles.css`）到 GitHub。若先推前端、未執行 SQL，登入後的週曆會因無法讀取 `booking_group` 欄位而顯示讀取失敗。
3. 測試：一般會員預約 2 小時 → 點選該時段 → 取消此小時 → 再取消整段；用另一位會員確認看不到取消按鈕；用管理者帳號取消他人預約。

**注意：** 若之後重新執行 `supabase.sql`，它會重設 bookings 的欄位權限，請再執行一次 `cancel_booking_migration.sql`。

## 預約必填校內分機（2026-11）
- 新增預約表單增加「校內分機」必填欄位（3–10 碼，數字開頭，可含 `-` 或 `#`，例如 `1234`、`2203-15`）。前端與資料庫都會檢查，未填或格式錯誤無法預約。
- 系統記住會員最近一次填寫的分機，下次預約自動帶入，可直接修改。
- 分機只記錄在預約資料中，**不公開給其他會員**；管理後台「預約紀錄管理」表格及 CSV 匯出會顯示分機。
- 既有的舊預約沒有分機，後台顯示「—」。

**必要部署步驟（順序很重要）：**
1. 在 Supabase SQL Editor 執行 **`campus_extension_migration.sql`**（需已執行 `supabase.sql` 與 `admin_migration.sql`）。
2. 執行後立即推送前端（`index.html`、`app.js`、`auth.js`、`admin.html`、`admin.js`）。SQL 會移除舊版不含分機的預約函式，因此兩者之間的空檔，舊版網頁無法新增預約；反之若先推前端，登入時會讀不到會員資料。
3. 測試：登入 → 新增預約，不填分機應無法送出 → 填入分機完成預約 → 再次新增預約，分機應自動帶入 → 管理後台確認分機欄位與 CSV。

**注意：** 若之後重新執行 `supabase.sql` 或 `admin_migration.sql`，會還原為不含分機的舊版預約函式，請再執行一次 `campus_extension_migration.sql`。
