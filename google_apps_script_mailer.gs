/**
 * Lionheart FX 預約系統：通知信寄送服務（Google Apps Script）
 *
 * 由 Supabase 資料庫觸發器呼叫，以部署者本人的 Gmail 寄出兩種通知信：
 *   new_member：新使用者註冊 → 通知管理者「有新使用者需要管理者核准」
 *   approved  ：管理者核准   → 通知使用者「Lionheart FX註冊申請通過」
 *
 * 本程式碼不含任何密碼或 Email。ADMIN_EMAIL（管理者收件信箱）與 MAILER_TOKEN（驗證碼）
 * 存在「專案設定 → 指令碼屬性」，第一次執行 setup() 時自動建立。
 * 設定步驟請見 README「新會員申請」章節。
 */
const SITE_URL = 'https://jessechan27.github.io/lionheart-fx-booking/';
const ADMIN_URL = SITE_URL + 'admin.html';
const LAB_NAME = '中醫藥核心平台實驗室';

/** 第一次設定：在編輯器選擇 setup 後按「執行」，依提示授權。 */
function setup() {
  const props = PropertiesService.getScriptProperties();
  if (!props.getProperty('ADMIN_EMAIL')) {
    props.setProperty('ADMIN_EMAIL', Session.getEffectiveUser().getEmail());
  }
  if (!props.getProperty('MAILER_TOKEN')) {
    props.setProperty('MAILER_TOKEN', Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, ''));
  }
  const admin = props.getProperty('ADMIN_EMAIL');
  sendNewMemberEmail_({
    name: '測試使用者', lab: '測試實驗室', email: 'test@example.com',
    requested_at: Utilities.formatDate(new Date(), 'Asia/Taipei', 'yyyy-MM-dd HH:mm')
  });
  sendApprovedEmail_({ name: '測試使用者', email: admin });
  console.log('管理者收件 Email：' + admin);
  console.log('MAILER_TOKEN（請複製到 Supabase 設定）：' + props.getProperty('MAILER_TOKEN'));
  console.log('已寄出兩封測試信到 ' + admin + '，請到信箱確認。今日剩餘寄信額度：' + MailApp.getRemainingDailyQuota());
}

/** Supabase 呼叫的入口（部署為網頁應用程式）。 */
function doPost(e) {
  try {
    const data = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    const token = PropertiesService.getScriptProperties().getProperty('MAILER_TOKEN');
    if (!token || data.token !== token) {
      console.warn('拒絕：MAILER_TOKEN 不符');
      return json_({ ok: false, error: 'unauthorized' });
    }
    if (data.type === 'new_member') sendNewMemberEmail_(data);
    else if (data.type === 'approved') sendApprovedEmail_(data);
    else return json_({ ok: false, error: 'unknown type' });
    console.log('已寄出通知信：' + data.type);
    return json_({ ok: true });
  } catch (err) {
    console.error('寄信失敗：' + err);
    return json_({ ok: false, error: String(err) });
  }
}

/** 新使用者註冊 → 通知管理者。 */
function sendNewMemberEmail_(d) {
  const admin = PropertiesService.getScriptProperties().getProperty('ADMIN_EMAIL');
  if (!admin) throw new Error('尚未設定 ADMIN_EMAIL，請先執行 setup()');
  const name = clean_(d.name, 60) || '未填寫姓名';
  const lab = clean_(d.lab, 100) || '未填寫實驗室';
  const email = clean_(d.email, 150) || '（無）';
  const time = clean_(d.requested_at, 40) || '—';
  const rows = [['姓名', name], ['實驗室／單位', lab], ['Email', email], ['申請時間', time + '（台灣時間）']];

  const text = '有新使用者需要管理者核准。\n\n'
    + rows.map(r => r[0] + '：' + r[1]).join('\n')
    + '\n\n請登入管理後台審核：' + ADMIN_URL + '\n';
  const cellStyle = 'padding:8px 0;border-top:1px solid #e5e5ea';
  const html = '<div style="font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',\'Microsoft JhengHei\',sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#1d1d1f">'
    + '<p style="font-size:13px;color:#6e6e73;margin:0 0 8px">Lionheart FX 儀器預約系統 · ' + LAB_NAME + '</p>'
    + '<h2 style="font-size:20px;margin:0 0 16px">有新使用者需要管理者核准</h2>'
    + '<p style="font-size:15px;line-height:1.6;margin:0 0 16px">以下使用者剛完成註冊並申請預約權限，目前狀態為「待審核」，經管理者核准後才能預約儀器。</p>'
    + '<table style="border-collapse:collapse;width:100%;font-size:15px;border-bottom:1px solid #e5e5ea">'
    + rows.map(r => '<tr><td style="' + cellStyle + ';color:#6e6e73;width:110px">' + esc_(r[0]) + '</td><td style="' + cellStyle + '">' + esc_(r[1]) + '</td></tr>').join('')
    + '</table>'
    + '<p style="margin:24px 0"><a href="' + ADMIN_URL + '" style="background:#0071e3;color:#ffffff;text-decoration:none;padding:10px 20px;border-radius:980px;display:inline-block;font-size:15px">前往管理後台審核</a></p>'
    + '<p style="font-size:12px;color:#86868b;line-height:1.6;margin:0">使用者須完成 Email 驗證後才能登入。此信由系統自動發送。</p>'
    + '</div>';

  const options = {
    to: admin,
    subject: '【Lionheart FX】有新使用者需要管理者核准：' + name,
    body: text,
    htmlBody: html,
    name: 'Lionheart FX 預約系統'
  };
  if (isEmail_(email)) options.replyTo = email;
  MailApp.sendEmail(options);
}

/** 管理者核准 → 通知使用者。 */
function sendApprovedEmail_(d) {
  const to = clean_(d.email, 150);
  if (!isEmail_(to)) throw new Error('使用者 Email 無效');
  const name = clean_(d.name, 60) || '使用者';

  const text = name + '您好，\n\n'
    + '您申請之Lionheart FX使用帳號業已通過，可以開始使用預約系統。\n\n'
    + LAB_NAME + '\n';
  const html = '<div style="font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',\'Microsoft JhengHei\',sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#1d1d1f;font-size:15px;line-height:1.8">'
    + '<p style="margin:0 0 16px">' + esc_(name) + '您好，</p>'
    + '<p style="margin:0 0 28px">您申請之Lionheart FX使用帳號業已通過，可以開始使用<a href="' + SITE_URL + '" style="color:#0071e3">預約系統</a>。</p>'
    + '<p style="margin:0">' + LAB_NAME + '</p>'
    + '</div>';

  MailApp.sendEmail({
    to: to,
    subject: 'Lionheart FX註冊申請通過',
    body: text,
    htmlBody: html,
    name: LAB_NAME
  });
}

function clean_(value, max) {
  return String(value == null ? '' : value).replace(/[\r\n]+/g, ' ').trim().slice(0, max);
}

function isEmail_(value) {
  return /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(value || '');
}

function esc_(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
