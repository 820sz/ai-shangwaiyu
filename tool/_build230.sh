cd /d/readflow || exit 1
PYTHONUTF8=1 python tool/_bump230.py
bash tool/lockrun.sh analyze --no-pub lib 2>&1 | grep -E "error|warning" | head -6
echo "--- analyze done ---"
bash tool/lockrun.sh build apk --release --target-platform android-arm64 --no-pub 2>&1 | tail -3