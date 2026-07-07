---
name: web-tier
description: 任何 web 任务调用工具前必看本 skill。覆盖**两层路由决策**（WebFetch / 默认 web-access 主 Chrome 9222 **后台 tab**）、高风控站点清单（含 X / Twitter）、专用路径（公众号 / localhost）、web-access 使用规则（后台静默 + Proxy 生命周期）、主 Chrome 9222 健康监控、子 agent 委派、站点经验、失效处理。Tier 3 独立 Brave 链路已于 2026-05-25 下线合并到 Tier 2。
---

# Web 任务路由 SOP（必看）

**任何 web 任务（搜索、抓取、调研、登录后访问）调用工具前，先看本 skill。** 跳过这一步可能导致：反爬必败、proxy 暴露面残留、子 agent 锚定到错误工具失败。

---

## 0. 路由决策表

### 两层路由

| Tier | 工具 | 典型场景 |
|---|---|---|
| **1 轻量** | `WebFetch` / `WebSearch` | Wikipedia / GitHub repo+issues+PR / HN / TechCrunch / 大部分英文官方 docs |
| **2 默认** | `web-access` skill（主 Chrome 9222 + cdp-proxy 3456，**后台 tab**） | 用户日常已登录的**所有**反爬站点：X / Twitter / 微博 / 知乎 / 小红书 / B站 / Instagram / 抖音 / npm / Apple docs ... |

**默认策略**：能用 Tier 1 不用 Tier 2。Tier 2 是**唯一**承载反爬 + 登录态的链路。

> 📌 **2026-05-25 架构合并**：原 Tier 3 独立 Brave Browser 9223 链路**已下线**，与 Tier 2 合并。**X / Twitter 抓取也走 Tier 2**（用户主 Chrome Default profile 已登 X 主号，sqlite Cookies 实证 auth_token 在）。底层逻辑：主 Chrome 常驻、多 profile 切换工作、不远程 SSH、AI 日报 on-demand —— 一个主 Chrome 抓手闭环所有 web 任务，少一个浏览器实例 = 少一份图标混淆 + cookies 续期 + launchd 维护。launchd plist 改名为 `.disabled` 防开机自启，Brave profile `~/.web-tier-brave-profile/` 保留供未来应急复活（详见 `~/.web-tier/ROLLBACK.md`）。

### 专用路径（优先匹配，不走两层）

| URL 模式 | 工具 | 说明 |
|---|---|---|
| `mp.weixin.qq.com` 图文 | `fetch-rich` | 公众号专用，独立 skill |
| `localhost` dev server | `webapp-testing` | 本地开发专用，独立 skill |

---

## 0.5 OpenCLI 加速层（流程一替代 / 流程二 opt-in）

OpenCLI 适配器作为 Tier 1/2 的加速层接入。**命中下列条件时，加载 `opencli-web` skill 并按其指引执行**——`opencli-web` 是执行组件，不会被对话关键词触发，只能从本 SOP 这里显式进入。

**流程一 —— `[public]` 优化替代 WebFetch（Tier 1 增强）**
- 触发：本该走 Tier 1 WebFetch + 目标站在 OpenCLI `[public]` 适配器清单内（~75 站，见 `opencli-web/references/adapters.md`）
- 动作：`opencli <site> <cmd> -f yaml` 替代 WebFetch；失败（非零退出 / 空输出 / 适配器报错）→ 回落 WebFetch
- 收益：确定性 schema、输出致密省 token、能拿下 WebFetch 403 的站（npm 等）
- 例外：通用英文静态页（Wikipedia / HN / arxiv）WebFetch 本就够用、速度同量级，**不强制替代**

**流程二 —— `[cookie]` 命令（opt-in，非默认路径）**
- 高风控登录站（zhihu / weibo / x / xiaohongshu / bilibili / douyin 等）**默认仍走 Tier 2 web-access**，OpenCLI `[cookie]` 不自动接管、不竞速、不自动路由
- 仅两种情况作为 opt-in 备选：①用户当前对话明确点名要用 OpenCLI 抓某站 ②web-access 已失败/超时/拒绝，兜底再试一手
- 用时规程：先 `opencli doctor` 确认扩展在线（间歇掉线就放弃回 web-access）；命令带 25s perl alarm 超时护栏；结果须 reasoning 层判断内容真实性（cookie 命令可能返回格式合法但内容是登录墙/验证码页的 JSON）；用完 daemon stop
- 为何 opt-in：经 3 轮 GPT 对抗 review + 实测——扩展间歇掉线、cookie 命令间歇卡死、内容可信无法机器校验，做默认路径复杂度超过收益。**不要自作主张升级成默认竞速路径**

详细执行步骤、四类安全红线（禁 plugin install / 禁 web read 替代 / 禁 ui 写操作 / 数据不可信）、daemon「用完即停」生命周期，全部见 `opencli-web` skill。

---

## 1. Tier 1: WebFetch / WebSearch 边界（2026-05-14 实测）

### WebFetch 能用（zero CDP cost）
- Wikipedia 静态条目
- GitHub repo 主页 / issues / PR 列表
- TechCrunch、HN 等媒体列表
- 大部分英文官方 docs（认 301 跟跳）

### WebFetch 必败必上 CDP
- `zhihu.com`（HTTP 403）
- `weibo.cn` / `m.weibo.cn`（302 跳登录墙）
- `x.com`（HTTP 402）
- `xiaohongshu.com`、`douyin.com`（强反爬）
- `npmjs.com` 包详情（403，意外发现）
- `developer.apple.com`（SPA 404）

### WebSearch 严格条件（全部满足才用）
- 通用事实性查询（版本号、发布日期、官方文档页）
- 不需要登录态
- 一次失败立即切 Tier 2，不要重试

**实测 GitHub 未屏蔽**（旧规则的"已知屏蔽 GitHub"假设已过期）。

---

## 2. Tier 2: 默认 `web-access` skill 使用规则

### 执行默认：后台静默

所有 CDP 操作在**后台 tab** 执行，**不切走用户当前 Chrome 前台，不问**。`/new` API 本身 `background: true` 就是默认值。

规则：
- 只有用户主动说"切过去看""前台打开""我要盯着"之类明确前台意图时，才用 `Target.activateTarget`
- 任务结束用 `/close` 关掉自建 tab，**绝不动用户原有 tab**
- 执行前告诉用户一句"在后台 tab 跑 [目标]"即可，不用等确认
- 需要用户点 Chrome "Allow remote debugging" 黄条时，提前告知："Chrome 窗口顶部会有黄色授权条要点一次 Allow，每次 Cmd+Q 完全退 Chrome 后首次连会再弹一次，日常不影响"

### 高风控站点路由（2026-05-25 合并后统一 Tier 2）

| 站点 | 主 Chrome 登录态 | 备注 |
|---|---|---|
| **x.com / twitter.com** | **Default profile 已登** ✓ | 2026-05-25 起从 Tier 3 Brave 合并到 Tier 2；如果实战发现 X cookies 过期，用户在主 Chrome 重登一次即可 |
| weibo.com / m.weibo.cn | 已登 | WebFetch 必败（302） |
| xiaohongshu.com | 已登 | 强反爬 |
| zhihu.com | 已登 | WebFetch 返 403 |
| douyin.com / tiktok.com | 已登 | 同上 |
| bilibili.com 登录后 | 已登 | |
| instagram.com | 已登 | 国内访问要走代理 |
| npmjs.com 包详情 | 无需 | WebFetch 返 403 |
| developer.apple.com | 无需 | SPA 路由 |

**未列出的反爬站点默认也走 Tier 2**。架构合并后**没有 Tier 3 兜底**，主 Chrome 是唯一登录态承载。

### Proxy 生命周期：用完即 kill（安全加固）

**默认策略**：用完即 kill。**覆盖** Tier 2 skill 原默认"Proxy 持续运行"。

理由：CDP Proxy bind `127.0.0.1:3456` 但**无鉴权、无 Host 校验、无 CORS**，存在 DNS rebinding（恶意网页短 TTL DNS 打本机 loopback）与供应链攻击（恶意 npm / Electron / VS Code 扩展 / Docker host 网络）两条**非本地**触发面。让 Proxy 仅在任务执行期存活，把暴露窗口从"持续"压到"分钟级"。

执行：
1. **任务启动**：`check-deps.mjs` 自动拉起 Proxy（2–3 秒冷启动可接受）
2. **任务结束**：所有 CDP 完成、`/close` 自建 tab 后主动 kill Proxy：
   ```bash
   lsof -ti:3456 | xargs kill 2>/dev/null || true
   ```
3. **例外**：用户明确说"接下来还要连续跑多个联网任务"才保留 Proxy；偏好仅当次对话有效
4. **优先级**：本规则**覆盖** Tier 2 skill 的 `Proxy 持续运行` 默认（用户安全偏好 > skill 默认）

不影响 Chrome 9222 端口（Chrome 自身校验 Host header + Allow UI，由 Chrome 生命周期管理）。

### 主 Chrome 9222 健康监控（唯一链路保障）

合并架构下主 Chrome 9222 是**唯一**承载所有 web 任务的链路，健康监控由 launchd 守护 `com.user.chrome-9222-watchdog` 兜底：
- 每 60s 静默检查 9222 端口
- 持续 DOWN ≥ 5 分钟才飞书告警（避免日常 Cmd+Q / 系统重启噪声）
- **不自动拉起 Chrome**（避免和用户日常 Cmd+Q 冲突）
- 详细控制命令见 `~/Desktop/自动化工具记录.md` 工具 04

---

## 3. Tier 3 已下线（2026-05-25）

原独立 Brave Browser 9223 链路于 2026-05-25 与 Tier 2 合并下线。

**残留资产**（保留供应急复活，用户后续可手动彻底清理）：
| 资产 | 路径 | 用途 |
|---|---|---|
| launchd plist（已 disable） | `~/Library/LaunchAgents/com.user.web-tier-chrome.plist.disabled` | 改名 `.disabled` 防开机自启；rename 回 `.plist` + bootstrap 即可复活 |
| Brave profile | `~/.web-tier-brave-profile/` | 含 X 主号 cookies，复活后立即可用 |
| 旧 Chrome profile | `~/.web-tier-chrome-profile/`（316MB） | 2026-05-14 阶段的应急备份 |
| helper.mjs | `~/.claude/skills/web-tier/helper.mjs` | 9223 直连 CDP，下线期间不会被加载 |
| launch.sh / health.sh | `~/.web-tier/` | 首次预热脚本 |
| 切换备忘 | `~/.web-tier/ROLLBACK.md` | 复活流程 |

**Brave.app 本体保留**（`/Applications/Brave Browser.app`），用户可手动 `brew uninstall --cask brave-browser` 卸载。

**何时复活 Tier 3**：仅当主 Chrome 9222 抓 X 连续失败 ≥ 3 次 + 用户明确指示复活时（流程见 `~/.web-tier/ROLLBACK.md`）。

---

## 4. 子 Agent 联网委派

通过 Agent tool 派发联网子任务时：

- prompt 必须明确指定路由层级。涉及反爬 / 登录态 / SPA 时，加一句"**必须加载 web-access skill 并遵循指引**"
- 用**目标动词**（获取 / 调研 / 了解 / 核实），**禁用手段动词**（搜索 / 抓取 / 爬取）—— 手段动词会把子 agent 锚定到 WebSearch，反爬站点必败
- 多个独立目标分治给多个子 agent 并行
- 多 agent 共享同一主 Chrome + Proxy（tab 级隔离）
- **prompt 末尾必须强调**：

> "**Tier 2 web-access 调用必须 `background: true`，禁止 `Target.activateTarget` 切前台；用户正在主 Chrome 里多 profile 切换工作，前台不能动**"

## 5. 站点经验

**两套目录、按性质分工**（不要写错地方）：

| 内容类型 | 目录 | 维护责任 | 升级时是否会丢 |
|---|---|---|---|
| 平台特征 / 反爬机制 / DOM 选择器 / 签名 headers / cursor 协议 / 速率退避表 | `~/.claude/plugins/cache/web-access/web-access/*/references/site-patterns/` | web-access plugin 自身 | **会**（plugin 升级覆盖） |
| **可复用操作序列**（多步、跨会话复用的执行流程） | `~/.claude/skills/web-tier/references/site-patterns/` | 用户长期沉淀资产 | 不会 |

CDP 操作成功后发现新 URL 模式 / 反爬行为 / 必需参数，主动写回 plugin 目录对应 `{domain}.md`（这部分可接受被升级覆盖——下一版 web-access 通常也会带最新经验）。

**`## 可复用操作序列` 写哪里** —— 当同一类多步操作会跨任务/跨会话**重复跑 3+ 次**时（典型场景：竞品调研、AI 日报循环抓取、规模化采集），在 **web-tier 目录** 的 `{domain}.md` 写/追加 `## 可复用操作序列` 段。格式：触发条件 + 步骤序列（每步含等待/校验/异常分支）+ 适用浏览器模式（web-access / WebFetch / fetch-rich）+ 上次验证日期 + 失效信号（什么现象说明序列腐烂需重测）。**一次性抓单页不写**——沉淀腐烂成本 > 复用收益。示范见 `~/.claude/skills/web-tier/references/site-patterns/xiaohongshu.com.md`。

> 旧 Tier 3 站点经验文件（如 `x.com.md`）也在 web-tier 目录里——保留作为历史参考，新经验如果是"操作序列"性质追加到对应文件即可，"平台特征"性质则写到 plugin 目录。

---

## 反模式

- ❌ 把 `WebSearch` 当默认 —— 默认是 Tier 2 `web-access`
- ❌ 同一搜索方式反复重试 —— 失败证据 = 换方式
- ❌ 让 `WebFetch` / `WebSearch` 处理反爬站点或登录后内容（看上面实测清单）
- ❌ 用 `web-artifacts-builder` 处理搜索（它只是 artifacts 生成器）
- ❌ 让 `webapp-testing` 做外网任务
- ❌ 跳过"后台 tab" 直接切前台 —— 用户正在主 Chrome 多 profile 切换工作
- ❌ 让本 skill 处理 `mp.weixin.qq.com` 或 `localhost` —— 走专用 skill
- ❌ 目标站有 OpenCLI `[public]` 适配器还硬用 WebFetch —— 走流程一替代
- ❌ 直接因关键词触发 `opencli-web` skill —— 它只能从本 SOP 的 0.5 节显式进入
- ❌ 用 `opencli web read` 当通用网页抓取替代 web-access —— 实测漏 3/6 CSS 隐藏注入，通用抓取仍走 Tier 2
- ❌ 把 OpenCLI `[cookie]` 命令自作主张升级成高风控站的默认/竞速路径 —— 经 3 轮 GPT review 定为 opt-in
- ❌ 用 `[cookie]` 命令时不带超时护栏、或只看 exit 0 不判断内容真实性
- ❌ **自作主张复活 Tier 3 独立 Brave 链路** —— 已下线（2026-05-25），未经用户明确指示不重启守护；连续 3 次失败 + 用户明示才走复活流程
- ❌ **告警/续期/Allow 黄条提示给得太频繁** —— 用户"无感"诉求 = **只在真故障时打扰**：watchdog 已 5min 阈值，X cookies 过期才提示重登
- ❌ **暗示用户在某个浏览器里"再登一次"账号** —— 主 Chrome Default profile 已是登录态权威；新登录站点直接走 Tier 2 即可，不要建议跨浏览器迁移登录态
- ❌ **调用 `~/.claude/skills/web-tier/helper.mjs`** —— Tier 3 下线后 helper 是**无功能残留**（连 9223 不通即失败）；它的保留只为应急复活场景；未经"复活 Tier 3"明示禁止调用，调了必败
- ❌ **把一次性任务写成"可复用操作序列"沉淀进 `{domain}.md`** —— 沉淀腐烂成本（DOM/路由/反爬月度漂移）> 一次性任务的复用收益；只有同一类操作会跨任务/跨会话重复跑 3+ 次才进沉淀
- ⚠️ **风险知情（合并架构的 trade-off）**：Tier 2 抓 X 走主 Chrome Default profile cookies，如 X 触发风控（captcha / 限流），可能殃及用户日常浏览主号体验。**如发现频繁触发**：(1) 降低抓取频率；(2) 用户明示后复活 Tier 3 隔离 profile
