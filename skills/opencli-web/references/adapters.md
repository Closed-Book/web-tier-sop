# OpenCLI 适配器清单（实测 2026-05-16，v1.7.22）

权威来源永远是 `$OC list`。本文件是快速查表，定期与 `$OC list` 对账。

## `[public]` 免登录站点（流程一候选，~75 站）

走 HTTP 直连，无需扩展。命中即可 `$OC <site> <cmd> -f yaml` 替代 WebFetch：

```
1point3acres 36kr aibase apple-podcasts arxiv baidu-scholar bbc binance
bloomberg bluesky brave coingecko crates ctrip dblp defillama devto
dictionary dockerhub duckduckgo eastmoney endoflife flathub gitee google
google-scholar goproxy gov-law gov-policy hackernews hf homebrew hupu imdb
lesswrong lichess lobsters maven mdn medium nowcoder npm nuget nvd oeis
openalex openfda openreview osv packagist paperreview producthunt pubmed
pypi rest-countries rfc rubygems sinablog sinafinance spotify stackoverflow
steam substack tieba toutiao tvmaze uisdc uiverse v2ex wanfang weixin
weread wikidata wikipedia wttr xiaoyuzhou yahoo yollomi
```

注意：同一站点不同子命令标签可能不同（如 `36kr news/hot/search` 是 public，`36kr article` 是 intercept）。执行前用 `$OC <site> --help` 确认目标子命令标签。

## `[cookie]` 高风控登录站（流程二 opt-in 候选）

需 Chrome 扩展 + 主 Chrome 登录态。这些站**默认走 web-tier Tier 2**，OpenCLI cookie 命令仅作 opt-in 备选（用户点名 / web-access 失败兜底）：

| 站点 | opencli 适配器 | 实测状态 |
|---|---|---|
| zhihu | `zhihu hot/search/answer-detail/download` 等 13 条 | ✅ `zhihu hot` 实测直出结构化热榜 |
| weibo | `weibo hot/search/feed/comments` 等 | ⚠️ `weibo hot` 间歇卡死，用时必带 25s 护栏 |
| twitter/x | `twitter` 36 条（多为 cookie/ui） | 未实测 |
| xiaohongshu | `xiaohongshu search/feed/comments/creator-*` 等 | 未实测 |
| bilibili | `bilibili hot/feed/comments/download` 等 | 未实测 |
| douyin / reddit / jd / taobao / boss / linkedin | 均有 cookie 适配器 | 未实测 |

## 不适配的能力（opencli 补不上，仍走 web-tier 原方案）

- 未适配的任意站点深度交互 → web-access / web-tier helper.mjs
- 远程 SSH 场景 → opencli 死依赖本地 Chrome+扩展，走 web-tier（远程救回登录态属 Tier 3 应急复活场景，见 docs/tier3-rollback.md）
- 复杂多步新登录（SAML+MFA）→ opencli 只复用现成登录态
- 视频帧级分析 → 双方都没有
- `mp.weixin.qq.com` 公众号图文 → 仍走 fetch-rich（opencli `weixin` 偏列表/草稿）
- `localhost` 本地开发 → 仍走 webapp-testing
