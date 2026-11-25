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

## 新會員申請：記錄申請時間與 Email 通知管理者（2026-11）
- **記錄申請時間**：每位會員的 `profiles.requested_at` 記錄申請預約權限（註冊）的時間；管理後台「會員審核」表格新增「申請時間」欄（台灣時間），依申請時間由新到舊排序。既有會員以帳號建立時間補上。
- **Email 通知**：有新使用者註冊時，系統自動寄信給管理者，信中註明「有新使用者需要管理者核准」，並附上姓名、實驗室／單位、Email、申請時間及管理後台連結。

運作方式：使用者註冊後建立 `profiles`（狀態為待審核），資料庫觸發器透過 Supabase `pg_net` 呼叫 [Resend](https://resend.com) Email API 寄信。寄信在背景送出，**寄信失敗不會影響使用者註冊**。前端不會暴露任何金鑰或管理者 Email。

**必要部署步驟：**
1. 到 https://resend.com 以**管理者收件信箱**註冊免費帳號（未驗證自有網域時，Resend 只能寄到註冊帳號本人的信箱）。
2. Resend → **API Keys** → Create API Key（權限選 Sending access 即可），複製 `re_` 開頭的金鑰。
3. 在 Supabase SQL Editor 執行 **`new_member_application_migration.sql`**（需已執行 `supabase.sql` 與 `admin_migration.sql`）。執行後「申請時間」即開始記錄；若之後重新執行 `admin_migration.sql`，請再執行一次本檔。
4. 在 Supabase SQL Editor 執行以下指令，將金鑰與收件 Email 存入 Supabase Vault（不會出現在 GitHub）：

```sql
select lionheart_private.set_notification_settings('re_您的ResendAPIKey', '管理者收件Email');
```

5. 寄測試信並確認結果：

```sql
select lionheart_private.send_member_notification('測試使用者', '測試實驗室', 'test@example.com');
-- 數秒後查詢，status_code 為 200 代表 Resend 已接受寄送
select id, status_code, content, error_msg, created from net._http_response order by created desc limit 5;
```

6. 用一個新 Email 在網站註冊，確認管理者信箱收到通知。第一次收信若在垃圾郵件匣，請標記為「非垃圾郵件」。

**注意：**
- 通知在使用者送出註冊時寄出，此時對方可能尚未完成 Email 驗證；完成驗證前對方無法登入。
- 更換金鑰或收件 Email：再次執行步驟 4 即可覆寫。
- Resend 免費方案每日 100 封、每月 3,000 封。若日後驗證自有網域，可將 SQL 中寄件者 `onboarding@resend.dev` 改為自有網域地址，並可寄給多位管理者。
- 收不到信時，先以步驟 5 查詢 `net._http_response`：401/403 多為金鑰錯誤，422 多為收件信箱不是 Resend 帳號本人信箱。
