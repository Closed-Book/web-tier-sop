#!/usr/bin/env bash
#
# ~/.web-tier/watchdog-9222.sh
# launchd 周期调度（每 60s）：检查主 Chrome 9222 端口监听状态。
# 静默模式：UP/DOWN 状态变化只写 log；持续 DOWN ≥ 5 分钟才告警一次。
# 不自动拉起 Chrome（避免和用户日常 Cmd+Q 冲突）。
#
# 与 Tier 3 Brave 独立浏览器配合使用：AI 日报等高频任务走 Brave 9223，不依赖 9222 状态。
# 主 Chrome 9222 只承担 Tier 2 偶发任务，所以静默告警对"无感"诉求最友好。

set -uo pipefail

LARK_CLI="/Users/macbookpro/.nvm/versions/node/v24.13.1/bin/lark-cli"
LSOF="/usr/sbin/lsof"
DATE="/bin/date"
ALERT_OPEN_ID="ou_8a406a72e061313e431a6f7b2a931b47"
ALERT_THRESHOLD_SEC=300   # 持续 DOWN ≥ 5 分钟才告警

STATE_FILE="$HOME/.web-tier/9222-watchdog.state"
LOG_FILE="$HOME/.web-tier/9222-watchdog.log"

mkdir -p "$HOME/.web-tier"

# 判定当前状态
if "$LSOF" -ti:9222 >/dev/null 2>&1; then
    CURRENT="UP"
else
    CURRENT="DOWN"
fi

# state 文件格式: "<status> <down_since_epoch> <alerted_0or1>"，兼容旧单字段格式
LAST_LINE=$(cat "$STATE_FILE" 2>/dev/null || echo "UNKNOWN 0 0")
LAST=$(echo "$LAST_LINE" | awk '{print $1}')
DOWN_SINCE=$(echo "$LAST_LINE" | awk '{print $2+0}')   # +0 强制数值化兼容旧格式
ALERTED=$(echo "$LAST_LINE" | awk '{print $3+0}')

NOW=$("$DATE" '+%F %T')
NOW_EPOCH=$("$DATE" +%s)

if [[ "$CURRENT" == "DOWN" ]]; then
    # 进入或维持 DOWN
    if [[ "$LAST" != "DOWN" ]]; then
        DOWN_SINCE=$NOW_EPOCH
        ALERTED=0
        echo "$NOW  $LAST -> DOWN (开始计时)" >> "$LOG_FILE"
    fi
    # 持续 DOWN 超阈值且未告警 → 告警一次
    DURATION=$((NOW_EPOCH - DOWN_SINCE))
    if [[ "$ALERTED" -eq 0 && "$DURATION" -ge "$ALERT_THRESHOLD_SEC" ]]; then
        DOWN_SINCE_HUMAN=$("$DATE" -r "$DOWN_SINCE" '+%F %T')
        MSG="主 Chrome 9222 端口已持续失联超过 5 分钟（自 ${DOWN_SINCE_HUMAN} 起）。Tier 2 临时 web 任务受影响；AI 日报等高频任务走独立 Brave 不受影响。处置: 手动启动 Chrome 即可，启动后首次访问需点 Allow remote debugging 黄条。"
        if "$LARK_CLI" im +messages-send --user-id "$ALERT_OPEN_ID" --text "$MSG" --as bot >> "$LOG_FILE" 2>&1; then
            ALERTED=1
            echo "$NOW  发送 DOWN 告警 (持续 ${DURATION}s)" >> "$LOG_FILE"
        else
            echo "$NOW  飞书 DOWN 告警失败" >> "$LOG_FILE"
        fi
    fi
else
    # UP 状态
    if [[ "$LAST" == "DOWN" ]]; then
        DURATION=$((NOW_EPOCH - DOWN_SINCE))
        if [[ "$ALERTED" -eq 1 ]]; then
            MSG="主 Chrome 9222 端口已恢复 ${NOW}（DOWN 持续 ${DURATION}s）。Tier 2 临时 web 任务可用。"
            "$LARK_CLI" im +messages-send --user-id "$ALERT_OPEN_ID" --text "$MSG" --as bot >> "$LOG_FILE" 2>&1 || echo "$NOW  飞书恢复告警失败" >> "$LOG_FILE"
            echo "$NOW  DOWN -> UP 已发恢复告警 (DOWN 持续 ${DURATION}s)" >> "$LOG_FILE"
        else
            echo "$NOW  DOWN -> UP 静默恢复 (DOWN 持续 ${DURATION}s, 未达告警阈值)" >> "$LOG_FILE"
        fi
    elif [[ "$LAST" == "UNKNOWN" ]]; then
        echo "$NOW  UNKNOWN -> UP" >> "$LOG_FILE"
    fi
    DOWN_SINCE=0
    ALERTED=0
fi

echo "$CURRENT $DOWN_SINCE $ALERTED" > "$STATE_FILE"
