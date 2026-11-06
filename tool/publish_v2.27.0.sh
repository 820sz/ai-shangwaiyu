#!/usr/bin/env bash
# 发布 v2.27.0（用户真机验收通过后才执行）
#
# 用法：bash tool/publish_v2.27.0.sh
#
# 前提：
#   - 本地桌面 APK 已构建并复制到 C:/Users/xi283/Desktop/ReadFlow-v2.27.0.apk
#   - 本地 commits 已就绪（ahead origin/master）
#   - GitHub 网络可能不稳定：本脚本对 push / gh release 都做了重试
set -u
cd "$(dirname "$0")/.." || exit 1

VERSION="v2.27.0"
APK="build/app/outputs/flutter-apk/app-release.apk"
SYMBOL_SHA="tool/symbols/2.27.0/sha256.txt"
LOCAL_SHA=$(sha256sum "$APK" | awk '{print $1}')
EXPECTED_SHA=$(awk '{print $1}' "$SYMBOL_SHA")

echo "== 0. 包校验 =="
echo "本地: $LOCAL_SHA"
echo "记录: $EXPECTED_SHA"
if [ "$LOCAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "❌ APK 与归档 sha256 不一致，停止发布"; exit 1
fi
echo "✅ 一致"

echo "== 1. push master（最多 5 次，强制 HTTP/1.1）=="
OK=0
for i in 1 2 3 4 5; do
  if git -c http.version=HTTP/1.1 push origin master; then OK=1; break; fi
  echo "第 $i 次 push 失败，10s 后重试…"; sleep 10
done
[ "$OK" = 1 ] || { echo "❌ push master 失败"; exit 1; }

echo "== 2. 打 tag 并 push（最多 5 次）=="
git tag -f "$VERSION"
OK=0
for i in 1 2 3 4 5; do
  if git -c http.version=HTTP/1.1 push -f origin "$VERSION"; then OK=1; break; fi
  echo "第 $i 次 push tag 失败，10s 后重试…"; sleep 10
done
[ "$OK" = 1 ] || { echo "❌ push tag 失败"; exit 1; }

echo "== 3. gh release（最多 5 次；已存在则改用 upload --clobber）=="
OK=0
for i in 1 2 3 4 5; do
  if gh release view "$VERSION" >/dev/null 2>&1; then
    if gh release upload "$VERSION" "$APK" --clobber; then OK=1; break; fi
  else
    if gh release create "$VERSION" "$APK" \
      --title "ReadFlow v2.27.0 · 四大板块升级（阅读器C/找材料A/助理我的B+A/输出A+来源修复）" \
      --notes-file docs/release-notes-v2.27.0.md; then OK=1; break; fi
  fi
  echo "第 $i 次 release 失败，20s 后重试…"; sleep 20
done
[ "$OK" = 1 ] || { echo "❌ gh release 失败"; exit 1; }

echo "== 4. 核对线上 digest 与本地 sha256 =="
gh release view "$VERSION" --json assets --jq '.assets[] | "\(.name) \(.size) \(.digest)"'
echo "本地 sha256: $LOCAL_SHA"
echo "✅ 发布完成；请把 release URL 记入 docs/ 与给用户"
