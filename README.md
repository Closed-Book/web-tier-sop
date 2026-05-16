# web-tier SOP

Claude Code 的 **Web 任务三层路由 SOP**：让 AI 在任何联网任务前先做路由决策，
而不是无脑试 `WebFetch` / `WebSearch` —— 反爬站点必败、远程 SSH 弹 GUI 卡死、
proxy 暴露面残留，这些坑用一套 SOP 收口。

> macOS 专用。依赖 Node.js 22+、Google Chrome、Claude Code。

## 三层路由总览

| Tier | 工具 | 典型场景 |
|---|---|---|
| **1 轻量** | `WebFetch` / `WebSearch` | Wikipedia / GitHub / 英文官方 docs 等通用事实查询 |
| **2 默认** | `web-access`（主 Chrome 9222 + cdp-proxy 3456） | 日常已登录站点、临时调试、单次任务 |
| **3 重型** | `web-tier`（独立 Chrome 9223，launchd 守护） | 高风控持久任务 / 远程 SSH / 定时抓取 |
| 加速层 | `opencli-web`（OpenCLI 适配器） | 由 web-tier 路由调用，~75 站免登录结构化取数 |
| 专用 | `fetch-rich` / `webapp-testing` | 公众号图文 / localhost 开发服务器 |

完整决策表、高风控站点清单、安全约束、反模式见 [`skills/web-tier/SKILL.md`](skills/web-tier/SKILL.md)。

## 仓库结构

```
web-tier-sop/
├── install.sh                       # 一键安装（软链 skill + 渲染 plist + 装依赖）
├── skills/
│   ├── web-tier/                    # Tier 3 路由 SOP + 独立 Chrome CDP 工具
│   │   ├── SKILL.md                 #   路由决策主文档
│   │   ├── README.md                #   独立 Chrome 一次性预热指南
│   │   ├── helper.mjs               #   零依赖 CDP 工具（直连 9223）
│   │   └── references/site-patterns/ #  每站抓取模板（DOM 选择器 / 登录态探针）
│   └── opencli-web/                 # OpenCLI 适配器加速层
│       ├── SKILL.md
│       ├── references/adapters.md   #   ~75 个免登录站点清单
│       └── package.json             #   锁定 @jackwener/opencli 1.7.22
├── runtime/
│   ├── launch.sh                    # 独立 Chrome 手动预热脚本
│   ├── health.sh                    # 5 项健康诊断
│   └── com.user.web-tier-chrome.plist.template  # launchd 守护配置模板
└── docs/
    └── claude-md-routing.md         # 加进全局 CLAUDE.md 的强制路由片段
```

## 前置依赖

### Tier 2 的 `web-access` 插件（第三方，需另装）

本仓**不含** Tier 2 的 `web-access` —— 它是第三方插件，版权归原作者「一泽 Eze」。
完整 SOP 要跑通需另行安装：

```
/plugin marketplace add https://github.com/eze-is/web-access.git
/plugin install web-access
```

只用 Tier 1/3 不装 `web-access` 也能跑，但路由表里的 Tier 2 分支会缺位。

## 安装

```bash
git clone <this-repo> web-tier-sop
cd web-tier-sop
./install.sh
```

`install.sh` 会：软链两个 skill 到 `~/.claude/skills/`、`npm ci` 装 opencli 依赖、
拷 runtime 脚本到 `~/.web-tier/`、把 plist 模板渲染到 `~/Library/LaunchAgents/`。

之后**必须在物理机前**手动完成预热（不能远程 SSH，会弹 GUI）：

```bash
~/.web-tier/launch.sh                # 1. 启动独立 Chrome
# 2. 弹出窗口里登录目标账号、关扩展、关密码管理，Cmd+Q 退出
launchctl load ~/Library/LaunchAgents/com.user.web-tier-chrome.plist  # 3. 交给守护
~/.web-tier/health.sh                # 4. 验证 9223 健康
```

详细预热流程见 [`skills/web-tier/README.md`](skills/web-tier/README.md)。

最后把 [`docs/claude-md-routing.md`](docs/claude-md-routing.md) 里的片段加进你的全局
`~/.claude/CLAUDE.md`，让 Claude 强制走 SOP。

## 配置

| 环境变量 | 用途 | 必填 |
|---|---|---|
| `WEB_TIER_ALERT_OPEN_ID` | 登录态失效时发飞书 IM 告警的目标 open_id | 否（不设则仅写本地日志） |

跑 `lark-cli auth list` 拿你的 userOpenId，`export WEB_TIER_ALERT_OPEN_ID=ou_xxxx`。

## 致谢

- Tier 2 `web-access` 插件 —— [一泽 Eze / eze-is/web-access](https://github.com/eze-is/web-access)
- 加速层 OpenCLI —— [@jackwener/opencli](https://www.npmjs.com/package/@jackwener/opencli)

## License

MIT（见 [LICENSE](LICENSE)）。仅覆盖本仓自有内容；`web-access` 与 OpenCLI 各自遵循原协议。
