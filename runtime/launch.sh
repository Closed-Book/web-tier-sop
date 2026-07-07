#!/usr/bin/env bash
#
# ~/.web-tier/launch.sh
# 手动启动 Tier 3 独立 Brave Browser（首次预热用，不通过 launchd）。
# 平时启动应由 launchd 守护（com.user.web-tier-chrome，label 保留旧名兼容历史文档）。
#
# 2026-05-25 起 Tier 3 浏览器从 Google Chrome 切换为 Brave Browser：
#   - 图标和主 Chrome 区分（橙色狮子 vs 多彩），不会再混淆
#   - 独立 Developer ID 签名，brew cask 自动更新
#   - profile 独立（~/.web-tier-brave-profile/），主 Chrome 退出不影响

set -euo pipefail

PROFILE_DIR="$HOME/.web-tier-brave-profile"
PORT=9223
BROWSER="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"

# 检查 Brave 二进制
if [[ ! -x "$BROWSER" ]]; then
    echo "ERROR: Brave Browser 没找到在 $BROWSER" >&2
    echo "装一下: brew install --cask brave-browser" >&2
    exit 1
fi

# 检查 9223 端口是否已被占用
if lsof -ti:$PORT >/dev/null 2>&1; then
    OCCUPYING_PID=$(lsof -ti:$PORT | head -1)
    echo "ERROR: 9223 端口已被 PID $OCCUPYING_PID 占用。" >&2
    echo "如果是独立 Brave 已在跑（launchd 守护），不要重复启动。" >&2
    echo "如果是异常进程，先 kill: kill $OCCUPYING_PID" >&2
    exit 2
fi

# 检查独立 profile 锁文件（避免覆盖运行中的 profile）
if [[ -f "$PROFILE_DIR/SingletonLock" ]]; then
    LOCK_TARGET=$(readlink "$PROFILE_DIR/SingletonLock" 2>/dev/null || echo "unknown")
    echo "WARN: profile lock 存在 → $LOCK_TARGET" >&2
    echo "如果 Brave 已退出但 lock 残留，删了再启：rm '$PROFILE_DIR/SingletonLock'" >&2
    exit 3
fi

mkdir -p "$PROFILE_DIR"
mkdir -p "$HOME/.web-tier"

echo "启动独立 Brave Browser（headful，可见窗口）..."
echo "  Profile: $PROFILE_DIR"
echo "  Port:    $PORT"
echo ""
echo "首次启动可能弹 Keychain 授权对话框，请点【始终允许】。"
echo "Brave 窗口出来后，依次访问需要登录的站点（如 https://x.com/login）登一次。"
echo "登好后 Cmd+Q 退出 Brave，然后跑："
echo "  launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.user.web-tier-chrome.plist"
echo ""

# 后台启动，stdout/stderr 重定向到日志
nohup "$BROWSER" \
    --user-data-dir="$PROFILE_DIR" \
    --remote-debugging-port=$PORT \
    --no-first-run \
    --no-default-browser-check \
    --disable-extensions \
    --disable-component-update \
    --disable-default-apps \
    --disable-features=Translate,InterestFeedContentSuggestions \
    --disable-background-networking \
    >"$HOME/.web-tier/chrome.stdout.log" \
    2>"$HOME/.web-tier/chrome.stderr.log" &

BROWSER_PID=$!
echo "Brave PID: $BROWSER_PID"

# 等待 9223 端口就绪（最多 15 秒，Brave 首次启动稍慢）
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    sleep 1
    if curl -s "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
        echo "✓ 9223 端口就绪。"
        echo ""
        echo "下一步：在弹出的 Brave 窗口里:"
        echo "  1. 跳过 Brave 引导（不导入 Chrome 数据 / 不设默认浏览器 / 不开 Rewards）"
        echo "  2. 访问 https://x.com/login 登录 X 主号"
        echo "  3. （可选）登 weibo / xiaohongshu 等其他高风控站"
        echo "  4. Cmd+Q 退出 Brave"
        echo "  5. 跑: launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.user.web-tier-chrome.plist"
        exit 0
    fi
    echo "  等待 9223 端口... ($i/15)"
done

echo "ERROR: 等了 15 秒 9223 还没就绪。检查 ~/.web-tier/chrome.stderr.log 看错误。" >&2
exit 4
