cd /d/readflow || exit 1
PYTHONUTF8=1 python tool/_rewrite_prompt.py
bash tool/lockrun.sh analyze --no-pub lib 2>&1 | grep -E "error|warning" | head -8
echo "---done---"