<div align="center">

# 🌐 web-tier SOP

**Claude Code 的 Web 任务两层路由 SOP**

让 AI 在每个联网任务前先做路由决策，而不是无脑试 `WebFetch` / `WebSearch`。

`macOS` · `Claude Code` · `Node.js 22+` · `MIT`

</div>

---

## ✨ 本 SOP 的特色

> 一句话：把「联网任务该用哪个工具」从 AI 的临场猜测，变成一套有纪律、可复现、带安全边界的标准流程。

- **🚦 两层分级路由** —— 工具按「轻 → 重」排序，能用轻的不用重的。通用查询走 `WebFetch`，反爬 + 登录态任务统一走主 Chrome 9222 后台 tab。从源头避免「无脑 WebFetch 撞反爬必败」。
- **🛡️ 主 Chrome 9222 健康监控** —— launchd watchdog 每 60s 静默检查 9222，持续 DOWN ≥ 5min 才飞书告警、不自动拉起，贴合「无感」诉求。（原 Tier 3 独立浏览器 2026-05-25 下线合并，应急复活资产见 `docs/tier3-rollback.md`）
- **🔒 安全加固，不留暴露面** —— cdp-proxy「用完即 kill」、opencli daemon「用完即停」，把无鉴权本地端口的暴露窗口从「持续」压到「分钟级」，挡住 DNS rebinding 与供应链攻击两条非本地触发面。
- **⚡ OpenCLI 加速层** —— ~75 个站点免登录结构化取数，输出致密省 token，还能拿下 `WebFetch` 返 403 的站（npm 等）。失败自动回落，不影响主链路。
- **📉 失效优雅降级** —— 登录态过期时飞书告警 + 跳过该板块，不中断整体流程；需要时用户在主 Chrome 重登一次即可。
- **🧩 单一抓手闭环** —— 一个主 Chrome 承载所有反爬 + 登录态任务，少一个浏览器实例 = 少一份图标混淆 + cookies 续期 + launchd 维护。
- **🧠 经 GPT 对抗 review** —— OpenCLI 路径经 3 轮对抗 review + 实测，定为 opt-in 而非默认竞速路径 —— 不为「看起来先进」牺牲可靠性。
- **📚 站点经验沉淀** —— `site-patterns/` 累积每站 DOM 选择器、登录态探针、风控提示，越用越准。

---

## 🚦 两层路由总览

| Tier | 工具 | 典型场景 |
|:--:|---|---|
| **1 · 轻量** | `WebFetch` / `WebSearch` | Wikipedia / GitHub / 英文官方 docs 等通用事实查询 |
| **2 · 默认** | `web-access`（主 Chrome 9222 + cdp-proxy 3456，后台 tab） | 日常已登录的**所有**反爬站点（含 X / 微博 / 知乎 / 小红书 …）、临时调试、单次任务 |
| ⚡ 加速层 | `opencli-web`（OpenCLI 适配器） | 由 web-tier 路由调用，~75 站免登录结构化取数 |
| 🎯 专用 | `fetch-rich` / `webapp-testing` | 公众号图文 / localhost 开发服务器 |

> 📌 2026-05-25 起原 Tier 3 独立浏览器 9223 链路下线，与 Tier 2 合并；X / Twitter 等也走主 Chrome。历史与应急复活见 [`docs/tier3-rollback.md`](docs/tier3-rollback.md)。
>
> 完整决策表、高风控站点清单、安全约束、反模式见 [`skills/web-tier/SKILL.md`](skills/web-tier/SKILL.md)。

---

## 📂 仓库结构

```
web-tier-sop/
├── install.sh                       # 一键安装（--host claude|codex|both，软链 skill + watchdog + 装依赖）
├── skills/
│   ├── web-tier/                    # 两层路由 SOP（+ Tier 3 下线残留工具）
│   │   ├── SKILL.md                 #   路由决策主文档
│   │   ├── README.md                #   Tier 3 独立浏览器预热指南（应急复活用）
│   │   ├── helper.mjs               #   零依赖 CDP 工具（Tier 3 残留，两层默认不用）
│   │   └── references/site-patterns/ #  每站抓取模板（DOM 选择器 / 登录态探针）
│   └── opencli-web/                 # OpenCLI 适配器加速层
│       ├── SKILL.md
│       ├── references/adapters.md   #   ~75 个免登录站点清单
│       └── package.json             #   锁定 @jackwener/opencli 1.7.22
├── runtime/
│   ├── watchdog-9222.sh             # 主 Chrome 9222 健康监控（每 60s，两层唯一链路）
│   ├── com.user.chrome-9222-watchdog.plist.template  # watchdog launchd 配置模板
│   ├── launch.sh                    # Tier 3 独立浏览器预热脚本（应急复活用）
│   ├── health.sh                    # Tier 3 健康诊断（应急复活用）
│   └── com.user.web-tier-chrome.plist.template  # Tier 3 launchd 配置模板
└── docs/
    ├── 安装教程.md                   # 📖 完整中文安装教程（依赖 / 安放 / 改地址）
    ├── tier3-rollback.md            # Tier 3 下线历史 + 应急复活/退役流程
    └── claude-md-routing.md         # 加进全局 CLAUDE.md 的强制路由片段
```

---

## 🚀 快速开始

```bash
git clone <本仓库地址> web-tier-sop
cd web-tier-sop
./install.sh
```

`install.sh` 会：软链两个 skill 到 `~/.claude/skills/`、`npm ci` 装 opencli 依赖、
拷 runtime 脚本到 `~/.web-tier/`、把 plist 模板渲染到 `~/Library/LaunchAgents/`。

Codex 用户可显式指定安装目标（复用同一套 skill，仅安装目录不同）：

```bash
./install.sh --host codex    # 软链到 Codex 的 ~/.agents/skills/
./install.sh --host both     # Claude Code 与 Codex 都装
```

之后在**物理机前**启动主 Chrome 9222 健康监控（两层架构唯一链路）：

```bash
# 1. 确认主 Chrome 启动时带 --remote-debugging-port=9222（已登 X / 微博等账号）
# 2. 启动 watchdog（持续 DOWN ≥ 5min 才飞书告警，不自动拉起 Chrome）
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.chrome-9222-watchdog.plist
```

> 原 Tier 3 独立浏览器预热流程（`launch.sh` / 9223）已改为 opt-in 应急复活资产，见 [`docs/tier3-rollback.md`](docs/tier3-rollback.md)。

最后把 [`docs/claude-md-routing.md`](docs/claude-md-routing.md) 的片段加进全局
`~/.claude/CLAUDE.md`，让 Claude 强制走 SOP。

> **📖 完整步骤** —— 环境依赖、各依赖安装方式、skill 安放位置、需按自己机器修改的地址，
> 全部见 **[docs/安装教程.md](docs/安装教程.md)**。下面是依赖速览。

---

## 📦 依赖一览

**必需**（不装跑不起来）：

| 依赖 | 要求 | 检查 |
|---|---|---|
| macOS | —— | `sw_vers` |
| Claude Code | 最新版 | 宿主环境 |
| Node.js | **≥ 22** | `node -v` |
| Google Chrome | 任意近版 | `ls "/Applications/Google Chrome.app"` |

**可选**（按用到的功能装）：

| 依赖 | 用途 | 不装的后果 |
|---|---|---|
| `web-access` 插件 | Tier 2 路由（唯一反爬 + 登录态链路） | 只剩 Tier 1 |
| `lark-cli` | 飞书 IM 告警 | 告警只写本地日志 |
| `jq` | 跑 site-patterns 抓取示例 | 示例脚本 `jq` 行失败 |
| Tailscale | Tier 3 应急复活时远程救回登录态 | 两层默认用不到 |

**自动安装**：`@jackwener/opencli`（锁定 1.7.22，`install.sh` 跑 `npm ci`）。

> `web-access` 是第三方插件（不在本仓），安装方式与「更改来源地址」说明见
> [docs/安装教程.md 第二节](docs/安装教程.md)。

---

## ⚙️ 配置

| 环境变量 | 用途 | 必填 |
|---|---|---|
| `WEB_TIER_ALERT_OPEN_ID` | 登录态失效时发飞书 IM 告警的目标 open_id | 否（不设则仅写本地日志） |

跑 `lark-cli auth list` 拿你的 open_id，`export WEB_TIER_ALERT_OPEN_ID=ou_xxxx`。

---

## 🙏 致谢

- Tier 2 `web-access` 插件 —— [一泽 Eze / eze-is/web-access](https://github.com/eze-is/web-access)
- 加速层 OpenCLI —— [@jackwener/opencli](https://www.npmjs.com/package/@jackwener/opencli)

## 📄 License

MIT（见 [LICENSE](LICENSE)）。仅覆盖本仓自有内容；`web-access` 与 OpenCLI 各自遵循原协议。
