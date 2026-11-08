#!/usr/bin/env bash
cd /d/readflow || exit 1
APK=build/app/outputs/flutter-apk/app-release.apk
AAPT="/c/Users/xi283/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe"
"$AAPT" dump badging "$APK" 2>/dev/null | head -1
sha256sum "$APK" | tee /tmp/sha2292.txt
mkdir -p tool/symbols/2.29.2 && cp -f build/app/outputs/mapping/release/mapping.txt tool/symbols/2.29.2/mapping.txt && cp -f /tmp/sha2292.txt tool/symbols/2.29.2/sha256.txt
cp -f "$APK" "C:/Users/xi283/Desktop/ReadFlow-v2.29.2.apk"
git add -A
git -c user.name="lead" -c user.email="lead@local" commit -q -m "fix(v2.29.2): AI改写改为作者口吻重写原作(禁止书评/元叙述,按原作结构完整展开,篇幅随内容);自由搜二次改用官方搜索不再空转Gutenberg"
git log --oneline -1
git tag -f v2.29.2 >/dev/null 2>&1
OK=0; for i in 1 2 3 4 5; do if git -c http.version=HTTP/1.1 push origin master; then OK=1; break; fi; sleep 8; done; echo "master=$OK"
OK2=0; for i in 1 2 3 4 5; do if git -c http.version=HTTP/1.1 push -f origin v2.29.2; then OK2=1; break; fi; sleep 8; done; echo "tag=$OK2"
OK3=0; if gh release view v2.29.2 >/dev/null 2>&1; then gh release upload v2.29.2 "$APK" --clobber && OK3=1; else for i in 1 2 3 4 5; do if gh release create v2.29.2 "$APK" --title "ReadFlow v2.29.2 · AI 改写作者口吻重写原作" --notes-file docs/release-notes-v2.29.2.md; then OK3=1; break; fi; sleep 15; done; fi; echo "release=$OK3"
gh release view v2.29.2 --json url,isPrerelease,assets --jq '.url,"pre=\(.isPrerelease)",(.assets[]|"\(.name) \(.size) \(.digest)")' 2>/dev/null | head -5