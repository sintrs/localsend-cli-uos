#!/usr/bin/env bash
# 一次性初始化：建 localsend-cli-uos 仓库、推送、放开工件写权限。
#
#   bash setup.sh              # 建仓库 + 推送
#   bash setup.sh --verify     # 再顺手触发一次构建验证
#
# 不需要 PAT / 任何 secret —— 全链路只用仓库自带的 GITHUB_TOKEN。
# 不要用 sudo：root 下拿不到 gh 的 keyring token。
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-localsend-cli-uos}"
WORK="${WORK_DIR:-$HOME/$REPO}"
VERIFY=0
for a in "$@"; do [ "$a" = "--verify" ] && VERIFY=1; done

say() { printf '%s\n' "$*"; }
die() { printf '\n错误：%s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "找不到 gh CLI"
gh auth status >/dev/null 2>&1 || die "gh 未登录，先跑 gh auth login（不要用 sudo）"
if [ "$(id -u)" -eq 0 ] && [ "${ALLOW_ROOT:-0}" != 1 ]; then
    die "请不要用 sudo/root 运行：root 下拿不到 gh 的 keyring token，
  而且会在 \$HOME 留下一堆 root 属主的文件。
  确实要在 root 下跑（容器等场景）：ALLOW_ROOT=1 WORK_DIR=/tmp/xxx bash setup.sh"
fi

OWNER="$(gh api user --jq .login)"
FULL="$OWNER/$REPO"
say "账号    : $OWNER"
say "新仓库  : $FULL（public，非 fork）"
say "工作副本: $WORK"
echo

# ── 1. 复制文件 ────────────────────────────────────────────────────────
for f in .github/workflows/release.yml .github/workflows/build-linux.yml \
         .github/workflows/build-windows.yml .github/workflows/keepalive.yml README.md; do
    [ -f "$SRC/$f" ] || die "找不到 $SRC/$f"
done
mkdir -p "$WORK/.github/workflows"
cp "$SRC/.github/workflows/"*.yml "$WORK/.github/workflows/"
cp "$SRC/README.md" "$WORK/"
say "== 1/4 文件已就位 =="

# ── 2. 建仓库 ──────────────────────────────────────────────────────────
if gh api "repos/$FULL" >/dev/null 2>&1; then
    say "  仓库已存在，跳过创建"
else
    gh repo create "$FULL" --public --disable-wiki \
        --description "LocalSend CLI builds: linux/uos20 (glibc 2.28) + windows x64, auto-tracked from upstream" >/dev/null
    say "  已创建 $FULL"
fi

# ── 3. 推送 ────────────────────────────────────────────────────────────
cd "$WORK"
[ -d .git ] || git init -q -b main

# commit 要归到你名下，而不是运行脚本的那个人（比如 root）
UID_GH="$(gh api user --jq .id)"
git config user.name  "$OWNER"
git config user.email "${UID_GH}+${OWNER}@users.noreply.github.com"

git add -A
git diff --cached --quiet || git commit -q -m "chore: 初始化 localsend CLI 构建仓"
git remote get-url origin >/dev/null 2>&1 \
    || git remote add origin "https://github.com/$FULL.git"
gh auth setup-git >/dev/null 2>&1 || true
git push -u origin main 2>&1 | tail -3
say "== 2/4 已推送 =="

# ── 4. 放开工件写权限 ──────────────────────────────────────────────────
# 新仓库默认的 GITHUB_TOKEN 是只读的，不发 release 会 403。
# workflow 里虽然声明了 contents: write，但只能在仓库允许的范围内生效。
gh api -X PUT "repos/$FULL/actions/permissions/workflow" \
    -f default_workflow_permissions=write >/dev/null
say "== 3/4 已将 Workflow permissions 设为 read and write =="

say "== 4/4 完成 =="
echo
say "仓库: https://github.com/$FULL"
say "定时: 每天 UTC 20:00（北京 04:00）检查上游 cli/Cargo.toml 版本，有变化就重建发布"
say "保活: 每月 1 号自动 commit 一次，防 60 天无活动导致 cron 被禁用"

if [ "$VERIFY" = 1 ]; then
    echo
    say "触发一次构建验证（会真的编译 + 发 release，约 10-20 分钟）..."
    sleep 3
    gh workflow run release.yml -R "$FULL" -f force=true
    sleep 8
    gh run list -R "$FULL" --limit 3 2>/dev/null || true
    say "跟进: gh run watch -R $FULL"
else
    echo
    say "建议立刻跑一次验证："
    say "  gh workflow run release.yml -R $FULL -f force=true"
    say "  gh run watch -R $FULL"
fi
