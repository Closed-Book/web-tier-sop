#!/usr/bin/env node
//
// ~/.claude/skills/web-tier/helper.mjs
//
// 直连独立 Chrome 9223 做 CDP 操作。零外部依赖。
// 用 Node 22+ 原生 WebSocket（用户环境 v24.13.1 默认开启）。
//
// 用法：node helper.mjs <command> [args]
// commands: version | new | wait | html | eval | close | list | check-login | refresh-cookies-from-main | alert

import { execSync } from 'node:child_process';
import { existsSync, mkdirSync, appendFileSync, copyFileSync } from 'node:fs';

const CDP_HOST = '127.0.0.1';
const CDP_PORT = 9223;
const CDP_BASE = `http://${CDP_HOST}:${CDP_PORT}`;
const REQ_TIMEOUT_MS = 30_000;

// 飞书 IM 告警目标 open_id —— 通过环境变量注入，避免硬编码个人标识。
// 跑 `lark-cli auth list` 拿你的 userOpenId，然后任选其一：
//   export WEB_TIER_ALERT_OPEN_ID=ou_xxxx
//   或写进 ~/.web-tier/config 并在调用前 source。
// 未设置时 alert 命令仅写本地日志，不发飞书（不报错）。
const ALERT_OPEN_ID = process.env.WEB_TIER_ALERT_OPEN_ID || '';

// ---------- CDP plumbing ----------

let _ws = null;
let _msgId = 0;
const _pending = new Map(); // id -> {resolve, reject, timer}
const _eventListeners = []; // {method, sessionId|null, cb}

async function connectBrowserWs() {
  if (_ws && _ws.readyState === 1) return _ws;
  let info;
  try {
    const res = await fetch(`${CDP_BASE}/json/version`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    info = await res.json();
  } catch (e) {
    console.error(`独立 Chrome 不在跑或 9223 不可达。跑 ~/.web-tier/health.sh 诊断。(${e.message})`);
    process.exit(2);
  }
  const url = info.webSocketDebuggerUrl;
  if (!url) {
    console.error('Chrome /json/version 没返回 webSocketDebuggerUrl');
    process.exit(2);
  }
  _ws = new WebSocket(url);
  await new Promise((resolve, reject) => {
    _ws.addEventListener('open', () => resolve(), { once: true });
    _ws.addEventListener('error', (e) => reject(new Error('WS error: ' + (e.message || 'unknown'))), { once: true });
  });
  _ws.addEventListener('message', (evt) => {
    let msg;
    try { msg = JSON.parse(evt.data); } catch { return; }
    if (msg.id != null && _pending.has(msg.id)) {
      const { resolve, reject, timer } = _pending.get(msg.id);
      clearTimeout(timer);
      _pending.delete(msg.id);
      if (msg.error) reject(new Error(`CDP error ${msg.error.code}: ${msg.error.message}`));
      else resolve(msg.result);
      return;
    }
    if (msg.method) {
      for (const l of _eventListeners) {
        if (l.method === msg.method && (l.sessionId == null || l.sessionId === msg.sessionId)) {
          try { l.cb(msg.params, msg.sessionId); } catch {}
        }
      }
    }
  });
  return _ws;
}

function sendCdp(method, params = {}, sessionId = null) {
  return new Promise(async (resolve, reject) => {
    await connectBrowserWs();
    const id = ++_msgId;
    const payload = { id, method, params };
    if (sessionId) payload.sessionId = sessionId;
    const timer = setTimeout(() => {
      _pending.delete(id);
      reject(new Error(`CDP request ${method} timed out after ${REQ_TIMEOUT_MS}ms`));
    }, REQ_TIMEOUT_MS);
    _pending.set(id, { resolve, reject, timer });
    try { _ws.send(JSON.stringify(payload)); }
    catch (e) {
      clearTimeout(timer);
      _pending.delete(id);
      reject(e);
    }
  });
}

function onEvent(method, sessionId, cb) {
  const entry = { method, sessionId, cb };
  _eventListeners.push(entry);
  return () => {
    const i = _eventListeners.indexOf(entry);
    if (i >= 0) _eventListeners.splice(i, 1);
  };
}

async function attachToTarget(targetId) {
  const { sessionId } = await sendCdp('Target.attachToTarget', { targetId, flatten: true });
  return sessionId;
}

// ---------- commands ----------

async function cmdVersion() {
  const res = await fetch(`${CDP_BASE}/json/version`);
  if (!res.ok) {
    console.error(`9223 不可达 HTTP ${res.status}`);
    process.exit(2);
  }
  const info = await res.json();
  console.log(JSON.stringify({
    ok: true,
    browser: info.Browser,
    protocolVersion: info['Protocol-Version'],
    userAgent: info['User-Agent'],
  }, null, 2));
}

async function cmdNew(url) {
  if (!url) { console.error('usage: new <url>'); process.exit(1); }
  const { targetId } = await sendCdp('Target.createTarget', { url, background: true });
  console.log(targetId);
}

async function cmdWait(targetId, timeoutMs) {
  if (!targetId) { console.error('usage: wait <targetId> [timeout_ms]'); process.exit(1); }
  const timeout = Number(timeoutMs) || 15000;
  const sessionId = await attachToTarget(targetId);
  await sendCdp('Page.enable', {}, sessionId);

  // 先看 readyState：如果已 complete，直接返回（避免错过已触发的 loadEventFired）
  const { result } = await sendCdp('Runtime.evaluate', {
    expression: 'document.readyState',
    returnByValue: true,
  }, sessionId);
  if (result && result.value === 'complete') {
    console.log('loaded');
    return;
  }

  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      off();
      reject(new Error(`wait timeout after ${timeout}ms`));
    }, timeout);
    const off = onEvent('Page.loadEventFired', sessionId, () => {
      clearTimeout(timer);
      off();
      resolve();
    });
  });
  console.log('loaded');
}

async function cmdWaitFor(targetId, jsExpr, timeoutMs, pollMs) {
  if (!targetId || !jsExpr) { console.error("usage: wait-for <targetId> '<js-expr>' [timeout_ms=15000] [poll_ms=500]"); process.exit(1); }
  const timeout = Number(timeoutMs) || 15000;
  const poll = Number(pollMs) || 500;
  const sessionId = await attachToTarget(targetId);
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const { result, exceptionDetails } = await sendCdp('Runtime.evaluate', {
      expression: jsExpr,
      returnByValue: true,
    }, sessionId);
    if (!exceptionDetails && result?.value) {
      console.log(JSON.stringify({ ok: true, elapsed_ms: Date.now() - start, value: result.value }));
      return;
    }
    await new Promise(r => setTimeout(r, poll));
  }
  console.error(`wait-for timeout after ${timeout}ms`);
  process.exit(7);
}

async function cmdHtml(targetId) {
  if (!targetId) { console.error('usage: html <targetId>'); process.exit(1); }
  const sessionId = await attachToTarget(targetId);
  const { result } = await sendCdp('Runtime.evaluate', {
    expression: 'document.documentElement.outerHTML',
    returnByValue: true,
  }, sessionId);
  process.stdout.write(result?.value ?? '');
  process.stdout.write('\n');
}

async function cmdEval(targetId, expr) {
  if (!targetId || expr == null) { console.error("usage: eval <targetId> '<js-expr>'"); process.exit(1); }
  const sessionId = await attachToTarget(targetId);
  const { result, exceptionDetails } = await sendCdp('Runtime.evaluate', {
    expression: expr,
    returnByValue: true,
    awaitPromise: true,
  }, sessionId);
  if (exceptionDetails) {
    console.error('JS exception: ' + (exceptionDetails.text || exceptionDetails.exception?.description || JSON.stringify(exceptionDetails)));
    process.exit(4);
  }
  console.log(JSON.stringify(result?.value ?? null, null, 2));
}

async function cmdClose(targetId) {
  if (!targetId) { console.error('usage: close <targetId>'); process.exit(1); }
  await sendCdp('Target.closeTarget', { targetId });
  console.log('closed');
}

async function cmdList() {
  const { targetInfos } = await sendCdp('Target.getTargets');
  // 只留真页面：过滤掉 background_page / service_worker / extension / DevTools 自身
  const pages = (targetInfos || []).filter(t =>
    t.type === 'page'
    && !t.url.startsWith('chrome-extension://')
    && !t.url.startsWith('devtools://')
  );
  console.log(JSON.stringify(pages, null, 2));
}

// 各站登录态检测 JS 表达式：返回探针对象，cmdCheckLogin 据此判定
const LOGIN_PROBES = {
  x: `(() => ({
    hasLoginLink: !!document.querySelector('a[href="/login"]'),
    hasSignupLink: !!document.querySelector('a[href="/i/flow/signup"], a[href="/signup"]'),
    hasComposer: !!document.querySelector('a[href="/compose/post"], a[data-testid="SideNav_NewTweet_Button"]')
  }))()`,
  weibo: `(() => ({
    hasLoginBtn: !!document.querySelector('a[node-type="loginBtn"], a[action-type="login"]'),
    hasUserNav: !!document.querySelector('a[href*="/profile"], div[node-type="loginInfo"]')
  }))()`,
  xiaohongshu: `(() => ({
    bodyHasLogin: (document.body?.innerText || '').includes('登录'),
    hasUserAvatar: !!document.querySelector('.user-avatar, .reds-avatar')
  }))()`,
};

async function cmdCheckLogin(targetId, site) {
  if (!targetId || !site) { console.error('usage: check-login <targetId> <x|weibo|xiaohongshu>'); process.exit(1); }
  const probe = LOGIN_PROBES[site];
  if (!probe) { console.error(`unknown site: ${site}. supported: x, weibo, xiaohongshu`); process.exit(1); }
  const sessionId = await attachToTarget(targetId);
  const { result, exceptionDetails } = await sendCdp('Runtime.evaluate', {
    expression: probe,
    returnByValue: true,
  }, sessionId);
  if (exceptionDetails) {
    console.log(JSON.stringify({ logged_in: false, site, reason: 'probe-exception', detail: exceptionDetails.text }));
    return;
  }
  const r = result?.value || {};
  let logged_in = false;
  let reason = '';
  if (site === 'x') {
    logged_in = !r.hasLoginLink && !r.hasSignupLink;
    reason = logged_in ? 'no-login-link' : 'login-link-present';
  } else if (site === 'weibo') {
    logged_in = !r.hasLoginBtn && r.hasUserNav;
    reason = logged_in ? 'user-nav-present' : 'login-btn-present';
  } else if (site === 'xiaohongshu') {
    logged_in = r.hasUserAvatar && !r.bodyHasLogin;
    reason = logged_in ? 'avatar-present' : 'login-text-or-no-avatar';
  }
  console.log(JSON.stringify({ logged_in, site, reason, probe: r }));
}

async function cmdRefreshCookiesFromMain() {
  const HOME = process.env.HOME;
  const SRC = `${HOME}/Library/Application Support/Google/Chrome/Default/Cookies`;
  const DST_DIR = `${HOME}/.web-tier-chrome-profile/Default`;
  const DST = `${DST_DIR}/Cookies`;
  const TMP = '/tmp/web-tier-cookies-backup.db';

  if (!existsSync(SRC)) {
    console.error(`主 Chrome cookies 不存在: ${SRC}`);
    process.exit(5);
  }
  if (!existsSync(DST_DIR)) {
    console.error(`独立 profile 目录不存在: ${DST_DIR}\n先跑过 ~/.web-tier/launch.sh 让独立 Chrome 初始化目录。`);
    process.exit(5);
  }

  // 覆盖前先备份目标 cookies（如果存在）
  const BAK = `${DST}.bak.${Date.now()}`;
  if (existsSync(DST)) {
    try {
      copyFileSync(DST, BAK);
      console.log(`已备份原 cookies: ${BAK}`);
    } catch (e) {
      console.error(`备份失败（继续操作有风险）: ${e.message}`);
      process.exit(5);
    }
  }

  try {
    // sqlite3 .backup 走快照，避开运行中文件锁
    execSync(`sqlite3 "${SRC}" ".backup '${TMP}'"`, { stdio: 'pipe' });
    execSync(`cp "${TMP}" "${DST}"`, { stdio: 'pipe' });
    execSync(`rm -f "${TMP}"`, { stdio: 'pipe' });
  } catch (e) {
    console.error('拷 cookies 失败: ' + (e.stderr?.toString() || e.message));
    // 失败时恢复备份
    if (existsSync(BAK)) {
      try { copyFileSync(BAK, DST); console.error(`已从备份恢复: ${BAK}`); } catch {}
    }
    process.exit(5);
  }

  console.log('Cookies 已从主 Chrome 拷到独立 profile。');
  console.log(`原 cookies 备份在: ${BAK}（确认无问题后可删）`);
  console.log('请运行：launchctl kickstart -k gui/$(id -u)/com.user.web-tier-chrome 重启独立 Chrome');
}

async function cmdAlert(message) {
  if (!message) { console.error('usage: alert <message>'); process.exit(1); }

  // 兜底：所有告警先写本地日志，飞书发送独立于此
  const LOG_DIR = `${process.env.HOME}/.web-tier`;
  const LOG_FILE = `${LOG_DIR}/alerts.log`;
  try {
    if (!existsSync(LOG_DIR)) mkdirSync(LOG_DIR, { recursive: true });
    appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${message}\n`);
  } catch (e) {
    console.error(`本地日志写入失败: ${e.message}`);
  }

  if (!ALERT_OPEN_ID) {
    console.log(JSON.stringify({
      ok: true,
      channels: ['local-log'],
      log_file: LOG_FILE,
      text: message,
      note: 'WEB_TIER_ALERT_OPEN_ID 未设置，仅写本地日志。设置该环境变量后可发飞书 IM。',
    }));
    return;
  }

  try {
    const result = execSync(
      `lark-cli im +messages-send --user-id "${ALERT_OPEN_ID}" --text ${JSON.stringify(message)} --as bot`,
      { stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8' }
    );
    const m = result.match(/"message_id"\s*:\s*"([^"]+)"/);
    console.log(JSON.stringify({
      ok: true,
      channels: ['lark-im', 'local-log'],
      message_id: m ? m[1] : null,
      log_file: LOG_FILE,
      text: message,
    }));
  } catch (e) {
    console.error('飞书告警发送失败: ' + (e.stderr?.toString() || e.message));
    // 飞书失败但本地日志已写
    console.log(JSON.stringify({
      ok: false,
      channels: ['local-log'],
      log_file: LOG_FILE,
      text: message,
      reason: 'lark-cli send failed; check `lark-cli auth list` token status. 告警已写入本地日志兜底。',
    }));
    process.exit(6);
  }
}

// ---------- entry ----------

function usage() {
  console.error(`Usage: node helper.mjs <command> [args]

Commands:
  version
  new <url>
  wait <targetId> [timeout_ms=15000]
  wait-for <targetId> '<js-expr>' [timeout_ms=15000] [poll_ms=500]
  html <targetId>
  eval <targetId> '<js-expr>'
  close <targetId>
  list
  check-login <targetId> <x|weibo|xiaohongshu>
  refresh-cookies-from-main
  alert <message>
`);
}

function auditLog(cmd, args) {
  // 任务 2b：所有 helper 调用写本地审计日志，事后可查（不阻塞主流程）
  try {
    const LOG_DIR = `${process.env.HOME}/.web-tier`;
    const LOG_FILE = `${LOG_DIR}/access.log`;
    if (!existsSync(LOG_DIR)) mkdirSync(LOG_DIR, { recursive: true });
    // 截断长 args（如 eval 表达式）避免日志爆炸，url 截 100 字符
    const argStr = (args || []).map(a => String(a).slice(0, 100)).join(' ');
    appendFileSync(LOG_FILE, `[${new Date().toISOString()}] ${cmd} ${argStr}\n`);
  } catch {} // 日志失败不阻塞
}

async function main() {
  const [, , cmd, ...args] = process.argv;
  if (!cmd) { usage(); process.exit(1); }
  auditLog(cmd, args);
  try {
    switch (cmd) {
      case 'version': await cmdVersion(); break;
      case 'new': await cmdNew(args[0]); break;
      case 'wait': await cmdWait(args[0], args[1]); break;
      case 'wait-for': await cmdWaitFor(args[0], args[1], args[2], args[3]); break;
      case 'html': await cmdHtml(args[0]); break;
      case 'eval': await cmdEval(args[0], args[1]); break;
      case 'close': await cmdClose(args[0]); break;
      case 'list': await cmdList(); break;
      case 'check-login': await cmdCheckLogin(args[0], args[1]); break;
      case 'refresh-cookies-from-main': await cmdRefreshCookiesFromMain(); break;
      case 'alert': await cmdAlert(args.join(' ')); break;
      default: usage(); process.exit(1);
    }
  } catch (e) {
    console.error('Error: ' + (e.message || String(e)));
    process.exit(3);
  } finally {
    try { _ws?.close(); } catch {}
  }
}

main();
