#!/usr/bin/env bash
cd /d/readflow || exit 1
python - <<'PY'
p='lib/screens/input/free_search_screen.dart'
s=open(p,encoding='utf-8').read()
s=s.replace("import '../../models/learner_model.dart';\n",'',1)
open(p,'w',encoding='utf-8',newline='\n').write(s)
print('import cleaned')
PY
bash tool/lockrun.sh analyze --no-pub lib 2>&1 | grep -E "error|warning" | head -8
echo "---analyze done---"
bash tool/lockrun.sh test test/find_material_free_search_test.dart test/find_material_ai_rewrite_test.dart --no-pub --timeout 120s 2>&1 | tail -6
