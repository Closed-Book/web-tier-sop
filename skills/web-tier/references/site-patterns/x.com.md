# x.com (Twitter) 抓取模板

## URL 模式

- 用户主页：`https://x.com/<username>`
- 推文详情：`https://x.com/<username>/status/<tweet_id>`
- 登录页：`https://x.com/login`

AI 日报 4 大账号：
- https://x.com/AnthropicAI
- https://x.com/OpenAI
- https://x.com/GoogleDeepMind
- https://x.com/AIatMeta

## DOM 选择器（截至 2026 年 5 月）

- 推文容器：`article[data-testid="tweet"]`
- 推文正文：`article div[data-testid="tweetText"]`
- 推文时间：`article time` 的 `datetime` 属性（ISO 8601）
- 转发标记：`article div[data-testid="socialContext"]`（包含"已转推" / "Reposted" 则是 RT）
- 登录态检测：`a[href="/login"]` 存在 = 未登录；`a[data-testid="SideNav_NewTweet_Button"]` 存在 = 已登录

## 抓取流程（helper.mjs 调用方）

```bash
TID=$(node ~/.claude/skills/web-tier/helper.mjs new "https://x.com/AnthropicAI")

# X SPA：用 wait-for 等推文 hydrate，不要用 wait（loadEventFired 触发太早 DOM 还空）
node ~/.claude/skills/web-tier/helper.mjs wait-for "$TID" \
  'document.querySelectorAll("article[data-testid=\"tweet\"]").length >= 3' \
  15000 500

# 检测登录态
LOGIN=$(node ~/.claude/skills/web-tier/helper.mjs check-login "$TID" x)
if ! echo "$LOGIN" | jq -e '.logged_in == true' >/dev/null; then
  node ~/.claude/skills/web-tier/helper.mjs alert "X 登录态失效"
  node ~/.claude/skills/web-tier/helper.mjs close "$TID"
  echo "[X 登录态失效，下次物理机前补]"
  exit 0  # 降级 D：飞书告警 + 跳过不中断
fi

# 抓推文（取最近 10 条）
node ~/.claude/skills/web-tier/helper.mjs eval "$TID" "Array.from(document.querySelectorAll('article[data-testid=\"tweet\"]')).slice(0,10).map(a => ({
  text: a.querySelector('[data-testid=\"tweetText\"]')?.innerText || '',
  time: a.querySelector('time')?.getAttribute('datetime') || '',
  isRetweet: !!a.querySelector('[data-testid=\"socialContext\"]')
}))"

node ~/.claude/skills/web-tier/helper.mjs close "$TID"
```

**关键经验**：X 是 SPA，`wait` 命令的 `Page.loadEventFired` 会在 DOM 真有 article 之前就触发（实测延迟 ~2 秒）。一定要用 `wait-for` polling 等真实 selector 出现。

## 风控提示

- 单账号每天访问几个主页是安全的
- 不要 1 分钟刷 20 个主页（容易触发 challenge / "Something went wrong"）
- 建议每次 wait 完后 sleep 1-3 秒模拟人节奏：`sleep $((RANDOM % 3 + 1))`
- 如果 `wait` 后 HTML 出现 "Something went wrong"，先 sleep 30s 再重试一次；连续两次失败就走策略 D
- 独立 profile 默认用主号（不养小号）。X 看到的是"同账号在两个 Chrome 实例"，理论有微小风控风险，实测无影响

## 调试技巧

- 抓不到推文先 `html` 出来 grep `data-testid` 看 X 是不是又改了选择器名
- `check-login` 误判时手动跑 `eval $TID 'document.querySelector("a[href=\"/login\"]") !== null'` 看探针真值
- tab 堆积了用 `list` 看，逐个 `close`
