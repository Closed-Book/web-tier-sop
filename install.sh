#!/usr/bin/env bash
#
# install.sh — 把 web-tier SOP（两层架构）安装到当前用户环境（macOS）。
#
# 2026-05-25 起架构从三层（Tier 1/2/3）合并为两层（Tier 1/2）：
#   - 默认安装：skill 软链 + opencli 依赖 + Tier 2 主 Chrome 9222 watchdog
#   - Tier 3 独立浏览器（Brave）改为 opt-in (--with-tier3)，作为应急复活资产
#
# 做的事：
#   1. 软链 skills/web-tier、skills/opencli-web 到 ~/.claude/skills/
#   2. npm ci 安装 opencli 依赖（锁定 @jackwener/opencli 1.7.22）
#   3. 拷 watchdog 脚本到 ~/.web-tier/ + 渲染 watchdog plist 到 ~/Library/LaunchAgents/
#   4. (opt-in) 拷 Tier 3 应急复活脚本 launch.sh / health.sh + 渲染 plist 为 .disabled
#
# 不做的事：不预热 Chrome / Brave、不 launchctl load —— 那几步必须在物理机前手动操作。

set -euo pipefail

WITH_TIER3=false
for arg in "$@"; do
  case "$arg" in
    --with-tier3) WITH_TIER3=true ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--with-tier3]

  默认: 仅安装两层架构（skill 软链 + opencli 依赖 + Tier 2 watchdog）
  --with-tier3: 额外安装 Tier 3 独立 Brave 应急复活资产（launch.sh / plist disabled）

详见 docs/tier3-rollback.md "复活流程"。
EOF
      exit 0
      ;;
  esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
WEB_TIER_DIR="$HOME/.web-tier"
WATCHDOG_LABEL="com.user.chrome-9222-watchdog"
TIER3_LABEL="com.user.web-tier-chrome"
BRAVE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"

echo "=== web-tier SOP 安装（两层架构）==="
echo "仓库: $REPO_DIR"
if [[ "$WITH_TIER3" == "true" ]]; then
  echo "模式: 两层 + Tier 3 应急复活资产（opt-in）"
else
  echo "模式: 仅两层（Tier 3 应急资产不部署，需要时重跑 --with-tier3）"
fi
echo

# 1. 前置检查
command -v node >/dev/null || { echo "ERROR: 需要 Node.js 22+（opencli 用）"; exit 1; }
command -v npm  >/dev/null || { echo "ERROR: 需要 npm"; exit 1; }
if [[ "$WITH_TIER3" == "true" && ! -x "$BRAVE" ]]; then
  echo "WARN: 未检测到 Brave Browser，Tier 3 复活需要它："
  echo "      brew install --cask brave-browser"
fi

# 1b. 迁移检测（老用户从三层架构升级到两层）
# 旧版 install.sh 会部署 com.user.web-tier-chrome.plist 立即 load 守护；
# 新版默认不部署该守护。如老 plist 仍在 load，本脚本不自动 bootout（避免
# 误杀用户在用的实例），仅提示并停止，等用户决策后手动迁移。
if launchctl print "gui/$(id -u)/$TIER3_LABEL" >/dev/null 2>&1; then
  cat <<MIGRATE

⚠️  迁移提示：检测到旧 Tier 3 守护 ($TIER3_LABEL) 仍在 load

  本机当前架构状态与新版 install.sh 默认两层架构不一致。
  本脚本【不会】自动 bootout 旧守护，避免误杀你正在用的实例。

  如确认要迁移到两层架构（推荐，详见 docs/tier3-rollback.md）：

    launchctl bootout gui/\$(id -u)/$TIER3_LABEL
    mv $LAUNCH_AGENTS/$TIER3_LABEL.plist \\
       $LAUNCH_AGENTS/$TIER3_LABEL.plist.disabled
    # 然后重跑本脚本: ./install.sh [--with-tier3]

  如想保留旧的三层架构（不推荐）：
    本脚本继续安装会幂等覆盖 watchdog 套件，不影响旧 Tier 3 守护运行。
    但 SKILL.md 已是两层架构语义，子 agent 路由会改变。

  本脚本暂停，请先决策后再继续 / 重跑。
MIGRATE
  exit 0
fi

# 2. 软链 skills 到 ~/.claude/skills
mkdir -p "$SKILLS_DIR"
for skill in web-tier opencli-web; do
  TARGET="$SKILLS_DIR/$skill"
  SRC="$REPO_DIR/skills/$skill"
  if [[ -e "$TARGET" && ! -L "$TARGET" ]]; then
    echo "WARN: $TARGET 已存在且非软链 —— 跳过。手动备份后删除再重跑本脚本。"
    continue
  fi
  ln -sfn "$SRC" "$TARGET"
  echo "  ✓ 软链 $skill -> $TARGET"
done

# 3. opencli-web 依赖（node_modules 不入库，从 lockfile 重建）
echo "  安装 opencli-web 依赖（npm ci）..."
( cd "$REPO_DIR/skills/opencli-web" && npm ci --silent --no-audit --no-fund )
echo "  ✓ opencli 1.7.22 就位"

# 4. runtime 脚本
mkdir -p "$WEB_TIER_DIR"

# 4a. watchdog（始终装，两层架构唯一链路监控）
#     渲染注入告警 open_id：从环境变量 WEB_TIER_ALERT_OPEN_ID 取值（未设留空，告警会静默失败到 log）
sed "s|__OPEN_ID__|${WEB_TIER_ALERT_OPEN_ID:-}|g" \
  "$REPO_DIR/runtime/watchdog-9222.sh" > "$WEB_TIER_DIR/watchdog-9222.sh"
chmod +x "$WEB_TIER_DIR/watchdog-9222.sh"
echo "  ✓ watchdog-9222.sh -> $WEB_TIER_DIR/"
if [[ -z "${WEB_TIER_ALERT_OPEN_ID:-}" ]]; then
  echo "  WARN: 未设 WEB_TIER_ALERT_OPEN_ID，watchdog 告警将无接收人。设置后重跑："
  echo "        export WEB_TIER_ALERT_OPEN_ID=ou_xxxx && ./install.sh"
fi

# 4b. Tier 3 应急复活脚本（opt-in）
if [[ "$WITH_TIER3" == "true" ]]; then
  cp "$REPO_DIR/runtime/launch.sh" "$REPO_DIR/runtime/health.sh" "$WEB_TIER_DIR/"
  chmod +x "$WEB_TIER_DIR/launch.sh" "$WEB_TIER_DIR/health.sh"
  echo "  ✓ Tier 3 launch.sh / health.sh -> $WEB_TIER_DIR/"
fi

# 5. 渲染 launchd plist
mkdir -p "$LAUNCH_AGENTS"

# 5a. watchdog plist（始终装）
sed "s|__HOME__|$HOME|g" \
  "$REPO_DIR/runtime/com.user.chrome-9222-watchdog.plist.template" \
  > "$LAUNCH_AGENTS/$WATCHDOG_LABEL.plist"
echo "  ✓ watchdog plist -> $WATCHDOG_LABEL.plist"

# 5b. Tier 3 plist（opt-in，渲染到 .plist.disabled 防默认 load）
if [[ "$WITH_TIER3" == "true" ]]; then
  sed "s|__HOME__|$HOME|g" \
    "$REPO_DIR/runtime/com.user.web-tier-chrome.plist.template" \
    > "$LAUNCH_AGENTS/$TIER3_LABEL.plist.disabled"
  echo "  ✓ Tier 3 plist 渲染（默认 .disabled 防开机自启，应急时 rename + bootstrap）"
fi

echo
echo "=== 安装完成 ==="
echo
echo "下一步【物理机前】手动操作："
echo
echo "  1. 启动 Tier 2 watchdog 健康监控："
echo "     launchctl bootstrap gui/\$(id -u) $LAUNCH_AGENTS/$WATCHDOG_LABEL.plist"
echo
echo "  2. 确认主 Chrome 启动时带 --remote-debugging-port=9222（已登 X / 微博等账号）"
echo "     watchdog 持续 DOWN ≥ 5min 才飞书告警，不自动拉起 Chrome"
echo

if [[ "$WITH_TIER3" == "true" ]]; then
  echo "  3. (Opt-in) Tier 3 应急复活（平时不用，仅当 Tier 2 抓 X 连续失败 ≥ 3 次）："
  echo "     mv $LAUNCH_AGENTS/$TIER3_LABEL.plist.disabled \\"
  echo "        $LAUNCH_AGENTS/$TIER3_LABEL.plist"
  echo "     ~/.web-tier/launch.sh    # 预热 Brave，登 X，Cmd+Q 退"
  echo "     launchctl bootstrap gui/\$(id -u) $LAUNCH_AGENTS/$TIER3_LABEL.plist"
  echo "     详细应急流程见 docs/tier3-rollback.md"
  echo
fi

echo "Tier 2 的 web-access 插件是第三方依赖，需另装 —— 见本仓 README「前置依赖」。"
echo "完整 SOP 见 skills/web-tier/SKILL.md（两层架构）。"
