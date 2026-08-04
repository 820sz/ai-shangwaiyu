# AI上外语

AI 英语阅读学习助手 —— 拍照取词、生词归档、AI 文章生成、回译练习。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

- 📷 拍照取词 → 豆包视觉识别(单词/短语/句子,支持圈画标记与全文翻译)
- 📚 生词按 教材/书籍/外刊/碎片文章 分类归档,支持每日学习统计
- ✍️ AI 生成英文文章 + 回译练习 + 结构化纠错(DeepSeek)
- 🔄 内置自动更新(国内镜像并发竞速,公开仓库可用)

## 开源说明

本项目以 **AGPL-3.0** 协议开源 —— 致敬 DeepSeek 的开源精神：模型开源，API 服务收费；
本项目同样开源客户端代码，未来核心能力将逐步服务端化。

- 任何人可自由使用、修改、分发本代码，但**衍生作品必须同样开源**（AGPL 传染性）
- 商业合作 / 闭源授权请通过 GitHub Issues 联系作者
- 本项目仅为客户端壳，各 AI 能力依赖用户自行配置的 API Key（火山方舟 / DeepSeek）

## 技术栈

Flutter · Provider · SQLite(sqflite) · Hive · Dio

## 发布流程

```bash
# 只打 arm64(主流手机全覆盖),APK 56MB → 20MB
flutter build apk --release --target-platform android-arm64
gh release create vX.Y.Z build/app/outputs/flutter-apk/app-release.apk --notes "更新说明"
```
