cd /d/readflow || exit 1
PYTHONUTF8=1 python tool/_fix_tests.py
bash tool/lockrun.sh test test/find_material_ai_rewrite_test.dart test/find_material_free_search_test.dart --no-pub --timeout 120s 2>&1 | tail -6