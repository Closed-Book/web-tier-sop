#!/usr/bin/env bash
#
# install.sh — 把 web-tier SOP 安装到当前用户环境（macOS）。
#
# 做的事：
#   1. 软链 skills/web-tier、skills/opencli-web 到 ~/.claude/skills/
#   2. npm ci 安装 opencli 依赖（锁定 @jackwener/opencli 1.7.22）
#   3. 拷 runtime 脚本到 ~/.web-tier/
#   4. 渲染 launchd plist（__HOME__ -> 实际 $HOME）到 ~/Library/LaunchAgents/
#
# 不做的事：不预热 Chrome、不 launchctl load —— 那几步必须在物理机前手动操作。

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
WEB_TIER_DIR="$HOME/.web-tier"
PLIST_LABEL="com.user.web-tier-chrome"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

echo "=== web-tier SOP 安装 ==="
echo "仓库: $REPO_DIR"
echo

# 1. 前置检查
command -v node >/dev/null || { echo "ERROR: 需要 Node.js 22+（helper.mjs 用原生 WebSocket）"; exit 1; }
command -v npm  >/dev/null || { echo "ERROR: 需要 npm"; exit 1; }
[[ -x "$CHROME" ]] || echo "WARN: 未检测到 Google Chrome —— Tier 3 独立 Chrome 需要它。"

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
cp "$REPO_DIR/runtime/launch.sh" "$REPO_DIR/runtime/health.sh" "$WEB_TIER_DIR/"
chmod +x "$WEB_TIER_DIR/launch.sh" "$WEB_TIER_DIR/health.sh"
echo "  ✓ runtime 脚本 -> $WEB_TIER_DIR/"

# 5. 渲染 launchd plist
mkdir -p "$LAUNCH_AGENTS"
sed "s|__HOME__|$HOME|g" \
  "$REPO_DIR/runtime/com.user.web-tier-chrome.plist.template" \
  > "$LAUNCH_AGENTS/$PLIST_LABEL.plist"
echo "  ✓ plist 渲染 -> $LAUNCH_AGENTS/$PLIST_LABEL.plist"

cat <<EOF

=== 安装完成 ===

后续步骤必须在【物理机前】手动操作（不能远程 SSH，预热会弹 GUI）：

  1. 预热独立 Chrome：   ~/.web-tier/launch.sh
  2. 弹出窗口里登录目标账号（X 等）、关所有扩展、关密码管理，Cmd+Q 退出
  3. 交给 launchd 守护：  launchctl load $LAUNCH_AGENTS/$PLIST_LABEL.plist
  4. 健康检查：          ~/.web-tier/health.sh
  5.（可选）飞书告警：   export WEB_TIER_ALERT_OPEN_ID=ou_xxxx

详细预热流程见 skills/web-tier/README.md。
Tier 2 的 web-access 插件是第三方依赖，需另装 —— 见本仓 README「前置依赖」。
EOF
