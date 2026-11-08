#!/usr/bin/env bash
cd /d/readflow || exit 1
grep -n "没有线索" -A 20 test/find_material_ai_rewrite_test.dart | head -30
