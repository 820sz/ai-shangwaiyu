#!/usr/bin/env bash
cd /d/readflow || exit 1
APK=build/app/outputs/flutter-apk/app-release.apk
AAPT="/c/Users/xi283/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe"
"$AAPT" dump badging "$APK" 2>/dev/null | head -1
sha256sum "$APK" | tee /tmp/sha2291.txt
mkdir -p tool/symbols/2.29.1 && cp -f build/app/outputs/mapping/release/mapping.txt tool/symbols/2.29.1/mapping.txt && cp -f /tmp/sha2291.txt tool/symbols/2.29.1/sha256.txt
cp -f "$APK" "C:/Users/xi283/Desktop/ReadFlow-v2.29.1.apk"
git add -A
git -c user.name="lead" -c user.email="lead@local" commit -q -m "fix(v2.29.1): 原版缺失时用官方搜索补搜二手解读;AI改写允许0线索但给定作品/主题时按模型知识体系改写;卡片文案更新"
git log --oneline -1
git tag -f v2.29.1 >/dev/null 2>&1
OK=0; for i in 1 2 3 4 5; do if git -c http.version=HTTP/1.1 push origin master; then OK=1; break; fi; sleep 8; done; echo "master=$OK"
OK2=0; for i in 1 2 3 4 5; do if git -c http.version=HTTP/1.1 push -f origin v2.29.1; then OK2=1; break; fi; sleep 8; done; echo "tag=$OK2"
OK3=0; if gh release view v2.29.1 >/dev/null 2>&1; then gh release upload v2.29.1 "$APK" --clobber && OK3=1; else for i in 1 2 3 4 5; do if gh release create v2.29.1 "$APK" --title "ReadFlow v2.29.1 · 搜不到原版时的正确兜底" --notes-file docs/release-notes-v2.29.1.md; then OK3=1; break; fi; sleep 15; done; fi; echo "release=$OK3"
gh release view v2.29.1 --json url,isPrerelease,assets --jq '.url,"pre=\(.isPrerelease)",(.assets[]|"\(.name) \(.size) \(.digest)")' 2>/dev/null | head -5
