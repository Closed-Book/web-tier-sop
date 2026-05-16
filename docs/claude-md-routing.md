# 全局 CLAUDE.md 路由片段

把下面这段加进你的全局 `~/.claude/CLAUDE.md`（或项目 `CLAUDE.md`），
让 Claude 在任何 web 任务前强制走 web-tier SOP，而不是直接试 WebFetch/WebSearch。

```markdown
## Web 任务路由

**任何 web 任务（搜索 / 抓取 / 调研 / 登录后访问）调用工具前，必须先加载 `web-tier` skill 并按其 SOP 决策，不得直接试 WebFetch/WebSearch。**

- Tier 1 轻量：`WebFetch` / `WebSearch`（仅通用事实查询）
- Tier 2 默认：`web-access`（Chrome 9222 + proxy 3456）
- Tier 3 重型：`web-tier` 独立 Chrome 9223（高风控 / 强反爬）
- 专用：`fetch-rich`（公众号）/ `webapp-testing`（localhost）
- 加速层：`opencli-web`（OpenCLI 适配器，由 web-tier 路由调用，非关键词触发）

完整规则（三层判定、OpenCLI 加速层、高风控清单、安全约束、子 agent 委派、反模式）见 `web-tier` SKILL.md。
```

为什么需要这段：skill 的 `description` 只在语义匹配时才被 Claude 主动加载。
把硬规则写进 CLAUDE.md 能确保**每个** web 任务都先过 SOP 决策，不漏。
