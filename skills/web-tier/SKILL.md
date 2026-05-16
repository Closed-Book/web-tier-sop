---
name: web-tier
description: 任何 web 任务调用工具前必看本 skill。覆盖三层路由决策（WebFetch / 默认 web-access / 独立 Chrome 9223 重型链路）、高风控站点清单、专用路径（公众号 / localhost）、web-access 使用规则（后台静默 + Proxy 生命周期）、独立 Chrome SOP、子 agent 委派、站点经验、失效处理。
---

# Web 任务路由 SOP（必看）

**任何 web 任务（搜索、抓取、调研、登录后访问）调用工具前，先看本 skill。** 跳过这一步可能导致：反爬必败、远程 SSH 时弹 GUI 卡死、proxy 暴露面残留、子 agent 锚定到错误工具失败。

---

## 0. 路由决策表

### 三层路由（按"轻 → 重"排序）

| Tier | 工具 | 典型场景 |
|---|---|---|
| **1 轻量** | `WebFetch` / `WebSearch` | Wikipedia / GitHub repo+issues+PR / HN / TechCrunch / 大部分英文官方 docs |
| **2 默认** | `web-access` skill（主 Chrome 9222 + cdp-proxy 3456） | 用户日常已登录的站点、临时调试、单次任务 |
| **3 重型** | `web-tier`（独立 Chrome 9223，**本 skill**） | 高风控持久任务 / 远程 SSH / AI 日报定时抓 X |

**默认策略**：能用 Tier 1 不用 Tier 2，能用 Tier 2 不用 Tier 3。但 **高风控站点必须 Tier 2 起步**，部分场景升 Tier 3。

### 专用路径（优先匹配，不走三层）

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
- 高风控登录站（zhihu / weibo / x / xiaohongshu / bilibili / douyin 等）**默认仍走 Tier 2/3 web-access**，OpenCLI `[cookie]` 不自动接管、不竞速、不自动路由
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
- 一次失败立即切 Tier 2/3，不要重试

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

---

## 3. Tier 3: `web-tier`（本 skill，独立 Chrome 重型链路）

### 何时升 Tier 3

**命中任一就用本 skill**：
1. 任务在远程 SSH 上跑 + 站点需要登录态（远程时主 Chrome 9222 的 Allow 黄条点不了）
2. 长跑定时任务（如 AI 日报每日抓 X），需要登录态永驻
3. 同一站点连续访问 ≥ 5 次（避免主 Chrome cdp-proxy 反复冷启动）
4. Tier 2 默认 web-access 失败 / 拒绝 / 超时

**不要用本 skill**：单次临时调试、公开静态页、用户主 Chrome 已能看到的页面。

### 高风控站点路由

| 站点 | 推荐 | 备注 |
|---|---|---|
| **x.com / twitter.com** | **Tier 3** | 独立 profile 已预热主号；helper.mjs check-login x |
| weibo.com / m.weibo.cn | Tier 2 | 主 Chrome 已登录；WebFetch 必败（302） |
| xiaohongshu.com | Tier 2 | 主 Chrome 已登录；强反爬 |
| zhihu.com | Tier 2 | 主 Chrome 已登录；WebFetch 返 403 |
| douyin.com / tiktok.com | Tier 2 | 同上 |
| bilibili.com 登录后 | Tier 2 | 主 Chrome 已登录 |
| instagram.com | Tier 2 | 国内访问要走代理 |
| npmjs.com 包详情 | Tier 2 | WebFetch 返 403 |
| developer.apple.com | Tier 2 | SPA 路由 |

未列出的反爬站点默认走 Tier 2；只有"AI 日报定时抓 + 需要登录态 + 想远程时能跑"才升 Tier 3。

### helper.mjs 命令速查

底层 CDP 工具，零依赖（Node 22+ 原生 WebSocket）：

```bash
node ~/.claude/skills/web-tier/helper.mjs <command> [args]
```

| Command | 用途 |
|---|---|
| `version` | 测 9223 健康 |
| `new <url>` | 后台开 tab，输出 targetId |
| `wait <tid> [ms]` | 等 Page.loadEventFired（多页适用） |
| `wait-for <tid> '<js-expr>' [ms] [poll-ms]` | polling 等 JS 表达式 truthy（SPA 必备） |
| `html <tid>` | 拿 outerHTML |
| `eval <tid> '<js>'` | 跑 JS 拿 JSON 结果 |
| `close <tid>` | 关 tab |
| `list` | 列所有真页面 tab（过滤扩展） |
| `check-login <tid> <x\|weibo\|xiaohongshu>` | 检测登录态 |
| `refresh-cookies-from-main` | 从主 Chrome 拷 cookies 续期 |
| `alert <message>` | lark-cli 发飞书 IM 告警到用户 vivo |

完整每站抓取流程见 `references/site-patterns/<domain>.md`。预热步骤见 `README.md`。

### 失效处理三层

**D（默认）：飞书告警 + 跳过**
```bash
node ~/.claude/skills/web-tier/helper.mjs alert "X 登录态失效"
# 任务标注 [失效，下次物理机前补]，不中断整体流程
```

**C（手动续期）：从主 Chrome 拷 cookies**
```bash
node ~/.claude/skills/web-tier/helper.mjs refresh-cookies-from-main
launchctl kickstart -k gui/$(id -u)/com.user.web-tier-chrome
```

**SSH 应急（Tailscale 已配）**
```bash
ssh <mac-tailscale-host>
~/.web-tier/launch.sh   # 拉起独立 Chrome（headful 但远程看不到无碍）
# helper.mjs 操作 X 登录，密码 + 2FA 在 SSH 里输
launchctl load ~/Library/LaunchAgents/com.user.web-tier-chrome.plist
```

### 预检与维护

```bash
~/.web-tier/health.sh                                                 # 健康诊断
launchctl list | grep web-tier-chrome                                 # 看守护状态
launchctl kickstart -k gui/$(id -u)/com.user.web-tier-chrome          # 重启
launchctl unload ~/Library/LaunchAgents/com.user.web-tier-chrome.plist  # 完全停
node ~/.claude/skills/web-tier/helper.mjs list              # 看当前 tab
```

---

## 4. 子 Agent 联网委派

通过 Agent tool 派发联网子任务时：

- prompt 必须明确指定路由层级或 skill。涉及反爬 / 登录态 / SPA 时，加一句"**必须加载 web-access skill（或 web-tier，按本 SOP 决策）并遵循指引**"
- 用**目标动词**（获取 / 调研 / 了解 / 核实），**禁用手段动词**（搜索 / 抓取 / 爬取）—— 手段动词会把子 agent 锚定到 WebSearch，反爬站点必败
- 多个独立目标分治给多个子 agent 并行
- Tier 2 多 agent 共享同一主 Chrome + Proxy（tab 级隔离）；Tier 3 多 agent 共享同一独立 Chrome 9223（tab 级隔离）

## 5. 站点经验

- Tier 2（web-access）：`ls ~/.claude/plugins/cache/web-access/web-access/*/references/site-patterns/`
- Tier 3（本 skill）：`ls ~/.claude/skills/web-tier/references/site-patterns/`

CDP 操作成功后发现新 URL 模式 / 反爬行为 / 必需参数，主动写回对应 `{domain}.md`（写到操作所用 Tier 的目录）。新站点扩展流程见 `references/site-patterns/README.md`。

## 6. Tier 3 与 Tier 2 的对照

| 维度 | Tier 2 默认 web-access | Tier 3 本 skill |
|---|---|---|
| Chrome 实例 | 用户主 Chrome | 独立 Chrome |
| 端口 | 9222 | 9223 |
| 生命周期 | proxy 用完即 kill | launchd 守护永远在跑 |
| 登录态 | 跟用户日常浏览器 | 独立 profile，主号 cookies |
| 远程 SSH | 要点 Allow 黄条 | 守护进程，远程无感 |
| 中间层 | cdp-proxy 3456 | 无 proxy，helper.mjs 直连 9223 |
| 安全 | proxy 暴露面要 kill | Chrome 148 自带 Host 校验防 DNS rebinding |

**两个 skill 并存互补，不互相替代**。

---

## 反模式（全 Tier 通用）

- ❌ 把 `WebSearch` 当默认 —— 默认是 Tier 2 `web-access`
- ❌ 同一搜索方式反复重试 —— 失败证据 = 换方式 / 升 Tier 的信号
- ❌ 让 `WebFetch` / `WebSearch` 处理反爬站点或登录后内容（看上面实测清单）
- ❌ 用 `web-artifacts-builder` 处理搜索（它只是 artifacts 生成器）
- ❌ 让 `webapp-testing` 做外网任务
- ❌ 跳过"前台/后台"确认直接开 Tier 2 tab —— 用户可能正在当前 Chrome 窗口做事
- ❌ 无脑升 Tier 3 —— 单次任务 Tier 1/2 够；Tier 3 是为持久 / 远程 / 高风控场景设计
- ❌ Tier 3 把 `targetId` 跨进程缓存 —— tab 关了就废
- ❌ Tier 3 循环高频 `new` 不 `close` —— tab 堆积
- ❌ 远程时手动 `~/.web-tier/launch.sh` —— headful 启动会弹 GUI，必须物理机前预热
- ❌ 让本 skill 处理 `mp.weixin.qq.com` 或 `localhost` —— 那些走专用 skill
- ❌ 目标站有 OpenCLI `[public]` 适配器还硬用 WebFetch —— 走流程一替代
- ❌ 直接因关键词触发 `opencli-web` skill —— 它只能从本 SOP 的 0.5 节显式进入
- ❌ 用 `opencli web read` 当通用网页抓取替代 web-access —— 实测漏 3/6 CSS 隐藏注入，通用抓取仍走原三层
- ❌ 把 OpenCLI `[cookie]` 命令自作主张升级成高风控站的默认/竞速路径 —— 经 3 轮 GPT review 定为 opt-in，高风控站默认走 web-access
- ❌ 用 `[cookie]` 命令时不带超时护栏、或只看 exit 0 不判断内容真实性 —— cookie 命令会卡死，也可能返回登录墙/验证码页的合法 JSON
