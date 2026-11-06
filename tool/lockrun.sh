#!/usr/bin/env bash
# ReadFlow · 多 agent 串行跑 flutter 命令（避免 build/native_assets 锁互相踩）
#
# 为什么需要：多个 agent 同时 `flutter test/analyze/build` 会抢
# `build/native_assets/windows/sqlite3.dll`，后到的进程静默失败（输出
# "Flutter failed to delete file ..." 然后没有别的信息）。用 mkdir 的原子性
# 做一把全局锁，谁拿到谁跑，跑完自动释放。
#
# 用法：
#   bash tool/lockrun.sh test test/material_channel_test.dart --no-pub
#   bash tool/lockrun.sh analyze --no-pub lib
#   bash tool/lockrun.sh build apk --release --target-platform android-arm64 --no-pub
#
# 说明：
# - 锁目录 .buildlock 在仓库根；进程异常退出时可能残留，超过 20 分钟视为陈旧锁自动清掉。
# - 最多等 20 分钟；超时退出码 9（说明有别的 agent 在跑长任务，等一会儿再来）。
set -u
cd "$(dirname "$0")/.." || exit 1
LOCK=.buildlock

for i in $(seq 1 240); do
  if mkdir "$LOCK" 2>/dev/null; then
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM
    echo "[lock] acquired (try $i)"
    flutter "$@"
    exit $?
  fi
  # 陈旧锁检测：超过 20 分钟没释放就强制清掉
  if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +20 2>/dev/null)" ]; then
    echo "[lock] stale lock (>20min), removing" >&2
    rmdir "$LOCK" 2>/dev/null
    continue
  fi
  sleep 5
done

echo "[lock] timeout: another flutter command is still running in this repo" >&2
exit 9
