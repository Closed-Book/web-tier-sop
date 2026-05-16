#!/usr/bin/env bash
#
# ~/.web-tier/health.sh
# 健康诊断：独立 Chrome 是否在跑 / 9223 是否可达 / launchd 服务状态。
# 失败时给出具体恢复命令，不自动重启（避免风暴）。

PORT=9223
PROFILE_DIR="$HOME/.web-tier-chrome-profile"
PLIST="$HOME/Library/LaunchAgents/com.user.web-tier-chrome.plist"
LABEL="com.user.web-tier-chrome"

ok() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; }
hint() { printf '    → %s\n' "$1" >&2; }

EXIT=0

echo "=== Web-Tier 健康诊断 ==="
echo ""

# 1. plist 文件是否存在
echo "[1/5] LaunchAgent plist"
if [[ -f "$PLIST" ]]; then
    ok "plist 存在: $PLIST"
else
    fail "plist 不存在"
    hint "重新生成或恢复 $PLIST"
    EXIT=1
fi

# 2. launchd 服务是否 load
echo ""
echo "[2/5] launchd 服务状态"
SERVICE_INFO=$(launchctl list 2>/dev/null | grep "$LABEL" || true)
if [[ -n "$SERVICE_INFO" ]]; then
    SERVICE_PID=$(echo "$SERVICE_INFO" | awk '{print $1}')
    SERVICE_EXIT=$(echo "$SERVICE_INFO" | awk '{print $2}')
    if [[ "$SERVICE_PID" == "-" ]]; then
        fail "服务已 load 但没在跑 (上次退出码: $SERVICE_EXIT)"
        hint "查看错误日志: tail ~/.web-tier/chrome.stderr.log"
        hint "重启: launchctl kickstart -k gui/\$(id -u)/$LABEL"
        EXIT=2
    else
        ok "服务已 load，PID: $SERVICE_PID"
    fi
else
    fail "服务未 load"
    hint "首次启动: launchctl load $PLIST"
    hint "（如果还没预热过，先跑 ~/.web-tier/launch.sh 在物理机前预热）"
    EXIT=3
fi

# 3. profile 目录是否存在
echo ""
echo "[3/5] profile 目录"
if [[ -d "$PROFILE_DIR" ]]; then
    ok "profile 目录: $PROFILE_DIR"
    if [[ -d "$PROFILE_DIR/Default" ]]; then
        COOKIES_BYTES=$(stat -f%z "$PROFILE_DIR/Default/Cookies" 2>/dev/null || echo 0)
        if [[ "$COOKIES_BYTES" -gt 1024 ]]; then
            ok "Cookies 文件: $COOKIES_BYTES bytes（应该有登录态）"
        else
            fail "Cookies 文件不存在或太小（$COOKIES_BYTES bytes）—— 可能没登过账号"
            hint "在物理机前跑 ~/.web-tier/launch.sh 然后登录 X"
            EXIT=4
        fi
    else
        fail "Default profile 子目录不存在 —— Chrome 没初始化过"
        hint "跑 ~/.web-tier/launch.sh 启动一次让 Chrome 初始化 profile"
        EXIT=5
    fi
else
    fail "profile 目录不存在: $PROFILE_DIR"
    hint "跑 ~/.web-tier/launch.sh 启动一次会自动创建"
    EXIT=6
fi

# 4. 9223 端口是否在监听
echo ""
echo "[4/5] 9223 端口"
PORT_PID=$(lsof -ti:$PORT 2>/dev/null | head -1 || true)
if [[ -n "$PORT_PID" ]]; then
    ok "9223 监听中，PID: $PORT_PID"
else
    fail "9223 端口未监听"
    hint "Chrome 进程可能崩了，跑: launchctl kickstart -k gui/\$(id -u)/$LABEL"
    EXIT=7
fi

# 5. /json/version 接口是否响应
echo ""
echo "[5/5] CDP /json/version"
VERSION_JSON=$(curl -s --max-time 3 "http://127.0.0.1:$PORT/json/version" 2>/dev/null || true)
if [[ -n "$VERSION_JSON" ]] && echo "$VERSION_JSON" | grep -q '"Browser"'; then
    BROWSER=$(echo "$VERSION_JSON" | grep -o '"Browser":"[^"]*"' | head -1)
    ok "CDP 响应: $BROWSER"
else
    fail "CDP /json/version 没响应或异常"
    hint "如果 9223 在监听但 CDP 没响应，Chrome 可能挂起。重启: launchctl kickstart -k gui/\$(id -u)/$LABEL"
    EXIT=8
fi

# 总结
echo ""
echo "=== 诊断结果 ==="
if [[ $EXIT -eq 0 ]]; then
    echo "✓ 全部检查通过"
    echo ""
    echo "可用命令："
    echo "  node ~/.claude/skills/web-tier/helper.mjs version"
    echo "  node ~/.claude/skills/web-tier/helper.mjs new https://x.com/AnthropicAI"
else
    echo "✗ 失败，退出码: $EXIT（按上面 → 提示恢复）"
fi

exit $EXIT
