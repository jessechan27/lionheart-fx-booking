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
