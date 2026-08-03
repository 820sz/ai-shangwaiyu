# AI上外语

AI 英语阅读学习助手 —— 拍照取词、生词归档、AI 文章生成、回译练习。

- 📷 拍照取词 → 豆包视觉识别(单词/短语/句子,支持圈画标记与全文翻译)
- 📚 生词按 教材/书籍/外刊/碎片文章 分类归档,支持每日学习统计
- ✍️ AI 生成英文文章 + 回译练习 + 结构化纠错(DeepSeek)
- 🔄 内置自动更新(检查 GitHub Release)

## 技术栈

Flutter · Provider · SQLite(sqflite) · Hive · Dio

## 发布流程

```bash
# 只打 arm64(主流手机全覆盖),APK 56MB → 20MB
flutter build apk --release --target-platform android-arm64
gh release create vX.Y.Z build/app/outputs/flutter-apk/app-release.apk --notes "更新说明"
```
