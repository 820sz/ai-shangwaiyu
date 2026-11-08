cd /d/readflow || exit 1
PYTHONUTF8=1 python tool/_bump.py
bash tool/lockrun.sh build apk --release --target-platform android-arm64 --no-pub 2>&1 | tail -3