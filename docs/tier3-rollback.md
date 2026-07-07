# Tier 3 已下线（2026-05-25）

**变更性质**：架构从三层（Tier 1/2/3）简化为两层（Tier 1/2）。Tier 3 独立浏览器链路下线，所有反爬 + 登录态任务（含 X / Twitter）统一走 Tier 2 主 Chrome 9222 后台 tab。

## 演化历史

- 2026-05-14 部署独立 Google Chrome 9223 + launchd 守护 `com.user.web-tier-chrome`
- 2026-05-25 上午 灰度休眠（误判用户场景不需要 Tier 3）
- 2026-05-25 下午 切换 Brave Browser（修正路径，希望解决图标混淆）
- 2026-05-25 晚 **架构合并下线 Tier 3**（用户决策："主 Chrome Default 已登 X，一个抓手闭环所有事"）

## 下线后的当前状态

| 项 | 值 |
|---|---|
| 主 Chrome 9222 | ✅ 唯一链路，承载所有反爬 + 登录态 |
| X 登录态 | ✅ 主 Chrome Default profile auth_token 实证存在 |
| 主 Chrome watchdog | ✅ `com.user.chrome-9222-watchdog` 每 60s 静默监控 |
| Tier 3 launchd plist | ⏸️ 改名 `.disabled` 防开机自启 |
| Brave profile | 📦 保留 `~/.web-tier-brave-profile/`（含 X 登录态备份） |
| 旧 Chrome profile | 📦 保留 `~/.web-tier-chrome-profile/` 316MB（2026-05-14 阶段备份） |
| Brave.app | 📦 保留 `/Applications/Brave Browser.app`（用户可手动卸载） |
| helper.mjs / launch.sh / health.sh | 📦 保留 `~/.web-tier/` 和 `~/.claude/skills/web-tier/`（连 9223 用，已无功能） |

## 复活流程（仅应急）

**何时考虑复活**：
- 主 Chrome 9222 抓 X 在 AI 日报实战中连续失败 ≥ 3 次（不是单次偶发）
- 用户明确指示"复活 Tier 3"
- 不要因单次抓取失败、不要因 X cookies 过期就自作主张复活

**30 秒复活步骤**：
```bash
# 1. plist 改名回 .plist
mv ~/Library/LaunchAgents/com.user.web-tier-chrome.plist.disabled \
   ~/Library/LaunchAgents/com.user.web-tier-chrome.plist

# 2. bootstrap 守护
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.web-tier-chrome.plist
sleep 2 && lsof -nP -iTCP:9223 -sTCP:LISTEN

# 3. helper.mjs 测连通
node ~/.claude/skills/web-tier/helper.mjs version
```

Brave profile `~/.web-tier-brave-profile/` 仍含 X 主号 cookies，复活立即可用（除非 X cookies 在此期间过期，则需用 launch.sh 启动 Brave 重登）。

## 彻底退役（确认不再需要 Tier 3）

```bash
# 1. 确认守护已停（如果复活过又停了）
launchctl bootout gui/$(id -u)/com.user.web-tier-chrome 2>/dev/null || true

# 2. 删 launchd plist 备份
rm ~/Library/LaunchAgents/com.user.web-tier-chrome.plist.disabled
rm -f ~/Library/LaunchAgents/com.user.web-tier-chrome.plist  # 万一复活过

# 3. 删两个 profile（含 X 登录态备份，无法恢复）
rm -rf ~/.web-tier-brave-profile        # ~146MB
rm -rf ~/.web-tier-chrome-profile       # ~316MB

# 4. 清 web-tier 工具脚本（保留 watchdog-9222.sh 是主 Chrome 监控，**不要删**）
rm ~/.web-tier/launch.sh ~/.web-tier/health.sh
rm ~/.web-tier/chrome.stderr.log ~/.web-tier/chrome.stdout.log
rm ~/.web-tier/access.log ~/.web-tier/alerts.log
rm -rf ~/.claude/skills/web-tier/helper.mjs

# 5. 卸 Brave.app（可选）
brew uninstall --cask brave-browser

# 6. 改文档：
#    - ~/.claude/skills/web-tier/SKILL.md 删第 3 节"Tier 3 已下线"段、删反模式相关项
#    - ~/Desktop/自动化工具记录.md 工具 03 状态改"已删除"
#    - 这份 ROLLBACK.md 删了
```

## 主 Chrome 9222 watchdog（唯一链路监控）

合并架构下 watchdog 价值提升：从"Tier 3 备份监控" 升级为"唯一链路健康保障"。

- 守护：`launchd com.user.chrome-9222-watchdog`，每 60s 跑 `~/.web-tier/watchdog-9222.sh`
- 静默阈值：持续 DOWN ≥ 5 分钟才飞书告警（避免日常 Cmd+Q 噪声）
- **不自动拉起 Chrome**（避免和用户日常 Cmd+Q 冲突）
- 控制命令 / 故障处置 详见 `~/Desktop/自动化工具记录.md` 工具 04
