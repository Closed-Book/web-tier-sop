#!/usr/bin/env bash
#
# install.sh — 把 web-tier SOP 安装到当前用户环境（macOS）。
#
# 做的事：
#   1. 按宿主软链 skills 到 Claude Code / Codex 的用户级 skill 目录
#   2. npm ci 安装 opencli 依赖（锁定 @jackwener/opencli 1.7.22）
#   3. 拷 runtime 脚本到 ~/.web-tier/
#   4. 生成 ~/.web-tier/bin/ 下的 helper/opencli wrapper
#   5. 渲染 launchd plist（__HOME__ -> 实际 $HOME）到 ~/Library/LaunchAgents/
#
# 不做的事：不预热 Chrome、不 launchctl load —— 那几步必须在物理机前手动操作。

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="claude"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CODEX_SKILLS_DIR="$HOME/.agents/skills"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
WEB_TIER_DIR="$HOME/.web-tier"
WEB_TIER_BIN="$WEB_TIER_DIR/bin"
PLIST_LABEL="com.user.web-tier-chrome"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

usage() {
  cat <<EOF
Usage: ./install.sh [--host claude|codex|both]

默认等价于：
  ./install.sh --host claude

Host:
  claude  安装 web-tier/opencli-web 到 ~/.claude/skills/（默认，兼容旧行为）
  codex   安装 web-tier/opencli-web 到 ~/.agents/skills/
  both    同时安装到 Claude Code 与 Codex skill 目录
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      if [[ $# -lt 2 || "${2:-}" == --* ]]; then
        echo "ERROR: --host requires claude|codex|both"
        usage
        exit 1
      fi
      HOST="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1"
      usage
      exit 1
      ;;
  esac
done

case "$HOST" in
  claude|codex|both) ;;
  *)
    echo "ERROR: --host must be claude|codex|both"
    usage
    exit 1
    ;;
esac

echo "=== web-tier SOP 安装 ==="
echo "仓库: $REPO_DIR"
echo "宿主: $HOST"
echo

# 1. 前置检查
command -v node >/dev/null || { echo "ERROR: 需要 Node.js 22+（helper.mjs 用原生 WebSocket）"; exit 1; }
command -v npm  >/dev/null || { echo "ERROR: 需要 npm"; exit 1; }
[[ -x "$CHROME" ]] || echo "WARN: 未检测到 Google Chrome —— Tier 3 独立 Chrome 需要它。"

# 2. 按宿主软链 skills
install_skills_to() {
  local skills_dir="$1"
  shift

  mkdir -p "$skills_dir"

  for skill in "$@"; do
    local src="$REPO_DIR/skills/$skill"
    local target="$skills_dir/$skill"

    if [[ ! -d "$src" ]]; then
      echo "ERROR: skill 不存在：$src"
      exit 1
    fi

    if [[ -e "$target" && ! -L "$target" ]]; then
      echo "WARN: $target 已存在且非软链 —— 跳过。手动备份后删除再重跑本脚本。"
      continue
    fi

    ln -sfn "$src" "$target"
    echo "  ✓ 软链 $skill -> $target"
  done
}

case "$HOST" in
  claude)
    install_skills_to "$CLAUDE_SKILLS_DIR" web-tier opencli-web
    ;;
  codex)
    install_skills_to "$CODEX_SKILLS_DIR" web-tier opencli-web
    ;;
  both)
    install_skills_to "$CLAUDE_SKILLS_DIR" web-tier opencli-web
    install_skills_to "$CODEX_SKILLS_DIR" web-tier opencli-web
    ;;
esac

# 3. opencli-web 依赖（node_modules 不入库，从 lockfile 重建）
echo "  安装 opencli-web 依赖（npm ci）..."
( cd "$REPO_DIR/skills/opencli-web" && npm ci --silent --no-audit --no-fund )
echo "  ✓ opencli 1.7.22 就位"

# 4. runtime 脚本
mkdir -p "$WEB_TIER_DIR"
cp "$REPO_DIR/runtime/launch.sh" "$REPO_DIR/runtime/health.sh" "$WEB_TIER_DIR/"
chmod +x "$WEB_TIER_DIR/launch.sh" "$WEB_TIER_DIR/health.sh"
echo "  ✓ runtime 脚本 -> $WEB_TIER_DIR/"

# 5. wrapper：避免 skill 文档写死 Claude Code 专属路径
mkdir -p "$WEB_TIER_BIN"
cat > "$WEB_TIER_BIN/web-tier-helper" <<EOF
#!/usr/bin/env bash
exec node "$REPO_DIR/skills/web-tier/helper.mjs" "\$@"
EOF
chmod +x "$WEB_TIER_BIN/web-tier-helper"

cat > "$WEB_TIER_BIN/opencli-web" <<EOF
#!/usr/bin/env bash
exec "$REPO_DIR/skills/opencli-web/node_modules/.bin/opencli" "\$@"
EOF
chmod +x "$WEB_TIER_BIN/opencli-web"
echo "  ✓ wrapper -> $WEB_TIER_BIN/"

# 6. 渲染 launchd plist
mkdir -p "$LAUNCH_AGENTS"
sed "s|__HOME__|$HOME|g" \
  "$REPO_DIR/runtime/com.user.web-tier-chrome.plist.template" \
  > "$LAUNCH_AGENTS/$PLIST_LABEL.plist"
echo "  ✓ plist 渲染 -> $LAUNCH_AGENTS/$PLIST_LABEL.plist"

cat <<EOF

=== 安装完成 ===

Skill 安装位置：
  Claude Code: $CLAUDE_SKILLS_DIR
  Codex:       $CODEX_SKILLS_DIR

通用 wrapper：
  ~/.web-tier/bin/web-tier-helper
  ~/.web-tier/bin/opencli-web

后续步骤必须在【物理机前】手动操作（不能远程 SSH，预热会弹 GUI）：

  1. 预热独立 Chrome：   ~/.web-tier/launch.sh
  2. 弹出窗口里登录目标账号（X 等）、关所有扩展、关密码管理，Cmd+Q 退出
  3. 交给 launchd 守护：  launchctl load $LAUNCH_AGENTS/$PLIST_LABEL.plist
  4. 健康检查：          ~/.web-tier/health.sh
  5.（可选）飞书告警：   export WEB_TIER_ALERT_OPEN_ID=ou_xxxx

详细预热流程见 skills/web-tier/README.md。
Tier 2 的 web-access 插件是第三方依赖，需另装 —— 见本仓 README「前置依赖」。
EOF
