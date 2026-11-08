cd /d/readflow || exit 1
APK=build/app/outputs/flutter-apk/app-release.apk
AAPT="/c/Users/xi283/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe"
"$AAPT" dump badging "$APK" 2>/dev/null | head -1
sha256sum "$APK" | tee /tmp/sha2300.txt
mkdir -p tool/symbols/2.30.0 && cp -f build/app/outputs/mapping/release/mapping.txt tool/symbols/2.30.0/mapping.txt && cp -f /tmp/sha2300.txt tool/symbols/2.30.0/sha256.txt
cp -f "$APK" "C:/Users/xi283/Desktop/ReadFlow-v2.30.0.apk"
git add -A
git -c user.name="lead" -c user.email="lead@local" commit -q -m "feat(v2.30.0): AI思考强度可调(修复非法output档静默禁用)+阅读器追问读正文/删常置功能/丰富形式保位/回顶回底+全App灰字文案瘦身"
git log --oneline -1
git tag -f v2.30.0 >/dev/null 2>&1
OK=0; for i in 1 2 3 4 5; do if git -c http.version=HTTP/1.1 push origin master; then OK=1; break; fi; sleep 8; done; echo "master=$OK"
OK2=0; for i in 1 2 3 4 5; do if git -c http.version=HTTP/1.1 push -f origin v2.30.0; then OK2=1; break; fi; sleep 8; done; echo "tag=$OK2"
OK3=0; if gh release view v2.30.0 >/dev/null 2>&1; then gh release upload v2.30.0 "$APK" --clobber && OK3=1; else for i in 1 2 3 4 5; do if gh release create v2.30.0 "$APK" --title "ReadFlow v2.30.0 · 思考强度可调 + 文案瘦身 + 阅读器修复" --notes-file docs/release-notes-v2.30.0.md; then OK3=1; break; fi; sleep 15; done; fi; echo "release=$OK3"
gh release view v2.30.0 --json url,isPrerelease,assets --jq '.url,"pre=\(.isPrerelease)",(.assets[]|"\(.name) \(.size) \(.digest)")' 2>/dev/null | head -5