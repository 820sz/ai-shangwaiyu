cd /d/readflow || exit 1
PYTHONUTF8=1 python tool/_fix_search.py
bash tool/lockrun.sh analyze --no-pub lib 2>&1 | grep -E "error|warning" | head -8
echo "---analyze done---"
bash tool/lockrun.sh test test/find_material_free_search_test.dart test/find_material_ai_rewrite_test.dart --no-pub --timeout 120s 2>&1 | tail -6