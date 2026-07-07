# Web-Tier Tier 3 独立浏览器应急复活预热

> ⚠️ **2026-05-25 架构已合并为两层**：默认路由是 Tier 1 `WebFetch` / Tier 2 主 Chrome 9222，**不需要本文档的预热**（默认只需 `./install.sh` + 让主 Chrome 带 `--remote-debugging-port=9222` + 启动 watchdog）。
>
> **本文档仅用于 Tier 3 独立浏览器应急复活**（`./install.sh --with-tier3`，仅当主 Chrome 抓 X 连续失败 ≥ 3 次且你明确要复活时）。复活背景见 [`../../docs/tier3-rollback.md`](../../docs/tier3-rollback.md)。
>
> 📌 下文历史措辞里的「独立 Chrome」**现已是独立 Brave**（2026-05-25 从 Google Chrome 切换）：profile 为 `~/.web-tier-brave-profile/`，端口 `9223`，二进制 `/Applications/Brave Browser.app`。命令按此对应即可。

**（应急复活时）必须在物理机前（不是远程 SSH）完成这一步，约 5 分钟。**

SKILL.md 是两层路由 SOP，本文档只讲 Tier 3 复活时首次怎么把独立 Brave 拉起来。

## 1. 启动独立 Chrome（手动跑一次，不通过 launchd）

```
~/.web-tier/launch.sh
```

会有 Chrome 窗口弹出，打开 about:blank。

## 2. 处理 Keychain 提示

首次启动可能弹 "Chrome 想访问 Chrome Safe Storage" 对话框 → 点 **始终允许**（Always Allow）。

如果不点 Always Allow，launchd 守护模式下 Chrome 进程会卡住等待——这是 GPT 标的关键风险点。

## 3. 登录目标账号

地址栏依次访问需要登录的站点 → 用你日常主号登录。

**MVP 推荐先登 X**（AI 日报 4 大账号抓取的主力站点）：
- https://x.com/login

其他站点按需登：weibo / xiaohongshu / zhihu / B 站 / instagram 等——**只有你**计划用独立 Chrome 抓的站点才需要登。日常一次性调研走 Tier 2 默认 web-access 即可（主 Chrome 已登录），不需要在独立 profile 重复登。

注：每个站点服务器看到的是"同一账号在主 Chrome 和独立 Chrome 两个实例"，理论有微小风控风险，实测无影响。如果未来真被风控盯上，再考虑切小号。

## 4. 禁扩展 + 禁密码管理（手动）

- `chrome://extensions/` → 关掉所有扩展（避免 background_page 污染 `list` 输出 + 避免扩展自动联网）
- `chrome://settings/passwords` → 关掉"提供保存密码"和"自动登录"

## 5. 关闭这个 Chrome 窗口（Cmd+Q 完全退出）

确认进程退干净：
```
pgrep -af "web-tier-chrome-profile" | head -5
```
应该没有匹配。

## 6. 交给 launchd 守护

```
launchctl load ~/Library/LaunchAgents/com.user.web-tier-chrome.plist
```

验证 5 秒后：
```
curl http://127.0.0.1:9223/json/version
```
应该返回 Chrome 版本号。失败跑 `~/.web-tier/health.sh` 诊断。

## 7. 端到端测试

```
TID=$(node ~/.claude/skills/web-tier/helper.mjs new "https://x.com/AnthropicAI")
node ~/.claude/skills/web-tier/helper.mjs wait "$TID" 15000
node ~/.claude/skills/web-tier/helper.mjs check-login "$TID" x
node ~/.claude/skills/web-tier/helper.mjs close "$TID"
```

`check-login` 应返回 `{"logged_in": true, "site": "x", ...}`。

## 失效降级（cookies 过期时）

### 策略 D（默认，远程 SSH 安全）

AI 日报 / 调用方检测失效 → 自动发飞书 IM 告警 + 跳过 X 板块：

```bash
node ~/.claude/skills/web-tier/helper.mjs alert "X 登录态失效，AI 日报跳过 X 板块"
# 跳过 X 抓取
```

日报正文标注 `[X 登录态失效，下次物理机前补]`，不中断整体流程。

### 策略 C（手动续期）

远程时若急用，可跑：

```
node ~/.claude/skills/web-tier/helper.mjs refresh-cookies-from-main
launchctl kickstart -k gui/$(id -u)/com.user.web-tier-chrome
```

从主 Chrome（你日常用的那个）拷 cookies 到独立 profile，重启独立 Chrome 加载新 cookies。两个 profile 都用主号，cookies 互通——这是给独立 profile 续命。

### 策略 SSH 远程登录（Tailscale 已配，应急用）

如果 cookies 完全失效需要远程重登：

```bash
ssh <mac-tailscale-hostname>
# 远程 Mac shell 里：
~/.web-tier/launch.sh                           # 拉起独立 Chrome（headful 但远程看不到）
# launch.sh 会输出 PID + 9223 就绪。然后在 SSH 里通过 helper.mjs 操作 Chrome 登录：
TID=$(node ~/.claude/skills/web-tier/helper.mjs new "https://x.com/login")
# 之后用 helper.mjs eval 自动输邮箱 + 你 SSH 里输密码 + 2FA OTP
# 完成后 launchctl load 让 launchd 接管守护
```

物理 Mac 在家，你出差时通过 Tailscale 也能远程救回。

## 日常维护

- 独立 Chrome 由 launchd 守护：Cmd+Q 干净退出**不会**被拉起（plist `SuccessfulExit=false`），但崩溃会自动重启（`Crashed=true`）
- 重启（cookies 刷新后必须）：`launchctl kickstart -k gui/$(id -u)/com.user.web-tier-chrome`
- **完全停用守护**（macOS 12+ 推荐用 bootout）：
  ```bash
  launchctl bootout gui/$(id -u)/com.user.web-tier-chrome
  ```
  或旧式：`launchctl unload ~/Library/LaunchAgents/com.user.web-tier-chrome.plist`
- 看进程：`pgrep -af "web-tier-chrome-profile"`
- 看 9223：`curl -s http://127.0.0.1:9223/json/version | jq .Browser`
- 看 tab：`node ~/.claude/skills/web-tier/helper.mjs list`
- 看告警日志：`tail -20 ~/.web-tier/alerts.log`
