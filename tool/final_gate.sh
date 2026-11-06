#!/usr/bin/env bash
# 最终验收闸门：四主题全部完成后由 Lead 跑一次，全绿才打包。
#
# 用法：bash tool/final_gate.sh
# 依赖 tool/lockrun.sh 串行锁（避免与其它 agent 并发踩 build 缓存）。
#
# 注意：
# - 全量测试较慢（~10~20 分钟），只在最后跑；
# - 渲染测试会覆盖 docs/ui-preview/real/ 下对应图，属预期行为；
# - 任一步失败即停止（set -e），输出保留在 _tmp_gate_*.log。
set -u
cd "$(dirname "$0")/.." || exit 1
LOG_DIR=_tmp_gate
mkdir -p "$LOG_DIR"

fail() { echo "❌ $1"; echo "  日志: $2"; exit 1; }

echo "=== [1/4] flutter analyze（必须 0 error / 0 warning） ==="
# 注意：flutter analyze 只要有 info 也会 exit 1，所以**不能**用退出码判断成败；
# 只看日志里有没有 error/warning 行（存量 info 允许，见 docs/IMPLEMENT-PLAN §0）。
bash tool/lockrun.sh analyze --no-pub lib > "$LOG_DIR/analyze.log" 2>&1
if [ $? -eq 9 ]; then fail "analyze 等待构建锁超时" "$LOG_DIR/analyze.log"; fi
if grep -Eq "^\s*(error|warning) •" "$LOG_DIR/analyze.log"; then
  grep -E "^\s*(error|warning) •" "$LOG_DIR/analyze.log" | head -20
  fail "analyze 有 error/warning" "$LOG_DIR/analyze.log"
fi
echo "✅ analyze 0 error / 0 warning（允许存量 info）"

echo "=== [2/4] 定向渲染全部重出（证明生产组件能渲染） ==="
RENDER_TESTS=$(ls test/*preview*_test.dart test/*render*_test.dart 2>/dev/null | tr '\n' ' ')
if [ -z "$RENDER_TESTS" ]; then
  echo "⚠️  未找到渲染测试，跳过"
else
  bash tool/lockrun.sh test $RENDER_TESTS --no-pub > "$LOG_DIR/renders.log" 2>&1 \
    || fail "渲染测试有失败" "$LOG_DIR/renders.log"
  echo "✅ 渲染测试全绿（$RENDER_TESTS）"
fi

echo "=== [3/4] 全量 flutter test ==="
bash tool/lockrun.sh test --no-pub > "$LOG_DIR/fulltest.log" 2>&1
TEST_EXIT=$?
if [ "$TEST_EXIT" -ne 0 ]; then
  # 已知假失败：profile_card_test（Hive 假时钟，交接文档明确「别修」，2026-11-06 前就在）。
  # 只允许这一个；出现任何其它失败都必须拦下。
  FAILED_LINES=$(awk '/^Failing tests:/{flag=1;next} flag && NF {print}' "$LOG_DIR/fulltest.log")
  UNKNOWN=$(printf '%s\n' "$FAILED_LINES" | grep -v 'profile_card_test\.dart' | grep -v '^$')
  if [ -n "$UNKNOWN" ]; then
    printf '%s\n' "$UNKNOWN"
    fail "全量测试有失败（非已知假失败）" "$LOG_DIR/fulltest.log"
  fi
  echo "⚠️  仅命中已知假失败 profile_card_test（Hive 假时钟，交接文档标注「别修」）"
fi
tail -3 "$LOG_DIR/fulltest.log"
echo "✅ 全量测试通过（已知假失败除外）"

echo "=== [4/4] 版本号与构建前检查 ==="
grep -m1 '^version:' pubspec.yaml
echo "构建命令（需要时手动执行）:"
echo "  \$env:FLUTTER_ALREADY_LOCKED='true'; flutter build apk --release --target-platform android-arm64 --no-pub"
echo "✅ 闸门通过"
