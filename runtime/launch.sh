#!/usr/bin/env bash
#
# ~/.web-tier/launch.sh
# 手动启动独立 Chrome（首次预热用，不通过 launchd）。
# 平时启动应由 launchd 守护（com.user.web-tier-chrome），不要用这个脚本。

set -euo pipefail

PROFILE_DIR="$HOME/.web-tier-chrome-profile"
PORT=9223
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 检查 Chrome 二进制
if [[ ! -x "$CHROME" ]]; then
    echo "ERROR: Google Chrome 没找到在 $CHROME" >&2
    exit 1
fi

# 检查 9223 端口是否已被占用
if lsof -ti:$PORT >/dev/null 2>&1; then
    OCCUPYING_PID=$(lsof -ti:$PORT | head -1)
    echo "ERROR: 9223 端口已被 PID $OCCUPYING_PID 占用。" >&2
    echo "如果是独立 Chrome 已在跑（launchd 守护），不要重复启动。" >&2
    echo "如果是异常进程，先 kill: kill $OCCUPYING_PID" >&2
    exit 2
fi

# 检查独立 profile 锁文件（避免覆盖运行中的 profile）
if [[ -f "$PROFILE_DIR/SingletonLock" ]]; then
    LOCK_TARGET=$(readlink "$PROFILE_DIR/SingletonLock" 2>/dev/null || echo "unknown")
    echo "WARN: profile lock 存在 → $LOCK_TARGET" >&2
    echo "如果 Chrome 已退出但 lock 残留，删了再启：rm '$PROFILE_DIR/SingletonLock'" >&2
    exit 3
fi

mkdir -p "$PROFILE_DIR"
mkdir -p "$HOME/.web-tier"

echo "启动独立 Chrome（headful，可见窗口）..."
echo "  Profile: $PROFILE_DIR"
echo "  Port:    $PORT"
echo ""
echo "首次启动可能弹 Keychain 授权对话框，请点【始终允许】。"
echo "Chrome 窗口出来后，依次访问需要登录的站点（如 https://x.com/login）登一次。"
echo "登好后 Cmd+Q 退出，然后跑：launchctl load ~/Library/LaunchAgents/com.user.web-tier-chrome.plist"
echo ""

# 后台启动，stdout/stderr 重定向到日志
nohup "$CHROME" \
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

CHROME_PID=$!
echo "Chrome PID: $CHROME_PID"

# 等待 9223 端口就绪（最多 10 秒）
for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if curl -s "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
        echo "✓ 9223 端口就绪。"
        echo ""
        echo "下一步：在弹出的 Chrome 窗口里登录账号、关扩展、然后 Cmd+Q 退出。"
        echo "退出后跑：launchctl load ~/Library/LaunchAgents/com.user.web-tier-chrome.plist"
        exit 0
    fi
    echo "  等待 9223 端口... ($i/10)"
done

echo "ERROR: 等了 10 秒 9223 还没就绪。检查 ~/.web-tier/chrome.stderr.log 看错误。" >&2
exit 4
