# Site Patterns

每个反爬 / 登录后 / SPA 站点一个 `.md`，记录 URL 模式、DOM 选择器、登录态检测、抓取流程经验。

非代码——是给调用方（Claude 主上下文 / PE prompt / sub-agent）的参考。`helper.mjs` 不会读这里，只用作人类 / Agent 查阅。

**注**：站点路由速查表（"哪个站点走 Tier 几"）的唯一来源是 [`../../SKILL.md`](../../SKILL.md) 第 3 节"高风控站点路由"。本目录只放每站具体的 DOM 选择器 / 抓取模板，**不复述路由表**。

## 已有模板

- [x.com.md](x.com.md) — X (Twitter) 抓取模板（DOM + 登录态 + 风控提示）

## 加新站点的流程

如果你发现某个反爬站点高频用到、想沉淀 site pattern：

1. **如果只是 Tier 2 默认 web-access 用**：写一个 `<domain>.md` 文档（参考 x.com.md 结构）记录 DOM 选择器 / 登录态检测 / 风控提示。**不需要改 helper.mjs**。
2. **如果要升 Tier 3 dedicated**（独立 profile 抓）：
   - a. 物理机前跑 `~/.web-tier/launch.sh` 启动独立 Chrome
   - b. 在弹出窗口里登录该站点主号 → cookies 持久化到独立 profile
   - c. 关 Chrome 让 launchd 守护接管
   - d. 在 `helper.mjs` 的 `LOGIN_PROBES` 加该站点登录态探针（提供 DOM 选择器）
   - e. 在 SKILL.md 的 `check-login` 行更新 site 枚举
   - f. 在 SKILL.md 第 3 节"高风控站点路由"把对应行 Tier 改为 **3 dedicated**
   - g. 写 `<domain>.md` 模板到本目录

## 站点 .md 模板（参考 x.com.md）

每个 site .md 包含：
- URL 模式
- DOM 选择器（每隔几个月会失效，注释 "截至 YYYY-MM"）
- 登录态检测探针
- 抓取流程示例（含 D 降级分支）
- 风控提示
- 调试技巧
