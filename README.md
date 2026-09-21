# AI上外语

AI 英语阅读学习助手 —— 拍照取词、生词归档、复习抽认卡、AI 文章生成、写译批改。

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

## 功能清单

拍照与输入

- 📷 拍照取词：豆包视觉识别，支持单词/短语/句子、圈画标记、全文翻译、追加图片、重新识别
- ✍️ 写译批改：手写稿转写 + 结构化批改（得分/错误定位/改写建议），最多 9 张图
- 🧩 AI 生词定制文章：用你的生词表生成英文文章，可选回译练习

词汇与复习

- 📚 生词归档：按 教材/书籍/外刊/碎片文章 分类，支持书籍/材料重命名、页码分组、批量删除与移动
- 🗂 掌握度管理：新词 / 学习中 / 已掌握，词条详情可改
- 🔁 复习抽认卡：按「今天 / 近 3 天 / 近 7 天 / 全部」取词，翻面看释义，标记不认识/模糊/认识，支持续看
- 🔈 音标 + 系统 TTS：离线发音（v1.5.0 起）

AI 与学习闭环

- 🧭 AI 材料推荐：基于学习画像（水平/目的/偏好 + 真实词汇指纹）流式推荐清单，点开可生成精读内容
- 🧠 AI 学习建议：按真实词汇量/掌握数/连续天数生成（「我的」页）
- 📝 写译记录与写译练习日志：批改结果可留存，练习计入统计
- 📊 学习统计：学习曲线、热力图、分类计数、连续天数

工程

- 🔄 内置自动更新：GitHub Release + 国内镜像并发竞速（公开仓库可用）
- 🩺 诊断信息页：崩溃日志 + 当前 API 配置摘要（Key 只显示厂商与长度）

## 安装与使用

### 1. 安装

从 [Releases](https://github.com/820sz/ai-shangwaiyu/releases) 下载最新 `app-release.apk`（arm64），在手机上允许"安装未知来源应用"后安装。

### 2. 自备 API Key（必须）

App **不含任何内置 Key**，所有 AI 能力都用你自己的 Key 调用，费用也记在你自己的账号上。两种任选：

| 厂商 | Key 前缀 | 能做什么 |
|---|---|---|
| 火山方舟（豆包） | `ark-` | 拍照取词、写译批改、文章生成（视觉能力在这里） |
| DeepSeek 官方 | `sk-` | 追问、材料推荐、学习建议等纯文本能力 |

打开 App → 「我的」→「API 设置」，粘进 Key 即可；Base URL 留空会按 Key 前缀自动配对端点（`ark-` → 方舟，`sk-` → `api.deepseek.com`）。填错家会在识别时报 4xx，诊断信息页能看到当前生效的端点。

### 3. 权限说明

| 权限 | 为什么需要 |
|---|---|
| `INTERNET` / `ACCESS_NETWORK_STATE` | 调 AI 接口、检查更新 |
| `REQUEST_INSTALL_PACKAGES` | App 内自动更新要拉起系统安装器（缺它安装会静默失败） |
| 相册 / 相机 | 由系统图片选择器与裁剪器在使用时申请，未声明额外运行时权限 |

App **未开启明文 HTTP**（全站强制 https），也**关闭了系统备份**（`allowBackup=false`）。

### 4. 数据存在哪 / 怎么备份

- 生词、文章、练习、收藏、写译记录、推荐缓存：本机 SQLite（应用私有目录，`databases/readflow.db`）
- API Key、模型、思考档位、学习画像、暂存会话、复习进度：本机 Hive（应用私有目录）
- 崩溃日志：应用文档目录 `crash_log.txt`（诊断页可读、可清空）

没有账号、没有云同步，**数据只在这台手机上**；系统备份已关闭，换机/卸载即丢失。当前版本的备份方式是：`诊断信息` 页可查看配置摘要，生词本可用系统截图/复制留存；未来会加导出功能。

## 发布流程 checklist

> 每一步都对应一次真实踩过的坑，别跳步。

1. **bump 版本**：改 `pubspec.yaml` 的 `version: X.Y.Z+NN`。v1.9.0 起 `UpdateService.compareVersions` 已比较四段（含 `+build`），**只升 build 号也会被判为新版本**；但为便于用户辨认，功能修复仍建议升 `X.Y.Z`。
2. **静态检查与测试**：`flutter analyze --no-fatal-infos`（0 error / 0 warning）+ `flutter test`（当前基线 193 例全绿 + 1 skip）。
3. **构建**：`flutter build apk --release --target-platform android-arm64`（只打 arm64，56MB → 20MB）。
4. **包内校验**：`aapt dump badging build/app/outputs/flutter-apk/app-release.apk | findstr version`，确认 `versionName`/`versionCode` 与 `pubspec.yaml` 一致（搞错版本号会让"检查更新"永远判无更新）。
5. **完整性比对**：`sha256sum app-release.apk`（PowerShell `Get-FileHash -Algorithm SHA256`）与 Release asset 的 `digest` 字段逐字比对，字节数也要一致 —— 证明线上件就是本地件。
6. **发 Release**：`gh release create vX.Y.Z build/app/outputs/flutter-apk/app-release.apk --notes "更新说明"`（tag 必须与 `pubspec.yaml` 的版本一致）。
7. **归档混淆映射**：把 `build/app/outputs/mapping/release/mapping.txt` 存到 `tool/symbols/<version>/`（R8 混淆后，线上堆栈只能靠它还原）。
8. **同步项目状态**：更新 `PLAN.md` 的状态区（版本/阶段/协议），历史小节按版本倒序追加。

## FAQ

**识别不准怎么调？**
① 换更清晰、光线均匀、文字尽量占满画面的照片；② 识图档位保持「不思考」或「低·约3s」——思考档在识图上更慢且对准确率帮助有限（中/高已在 2026-08-08 砍掉）；③ 用「重新识别」（逐行扫描 + 高清 + 自检）重跑一遍，它会保留你手动补充的词；④ 追问「这个词在原文里什么意思」比重新拍照更省。

**思考档位怎么选？**
- 识图：只留「不思考 / 低·约3s」。日常用不思考，字小、排版乱、手写体时开低档。
- 追问：豆包系「不思考/低/中/高」，DeepSeek 系「不思考/低/高/极致」（DS 官方没有 medium）。
- 长文本生成（文章、批改、推荐）：档位越高越慢，DS 的「极致」在长输出下更容易把预算花在思考上；赶时间就选低档。
- 换模型/换厂商后档位会按模型族重取，DS 下选到不支持的档会被打回「不思考」。

**数据在哪？**
本机应用私有目录：SQLite 在 `databases/readflow.db`，配置在 Hive（`settings` box）。没 root 看不到，也不需要看——「我的」页的统计与生词本就是这些数据的视图。

**如何备份？**
当前版本**没有自动备份**（系统备份已刻意关闭，防止明文 Key 上云）。发版前/换机前的做法：截图或复制关键生词与配置；`诊断信息` 页可保存 `crash_log.txt` 内容用于排查。后续会补一个真正的导出功能。

**为什么装不上新版本 / 更新没反应？**
先确认已授予"安装未知来源应用"权限（否则系统会静默拒绝安装）；再确认 Release 里的 APK 与本机架构一致（本项目只发 arm64）。

## 技术栈

Flutter · Provider · SQLite(sqflite) · Hive · Dio

## 开源说明

本项目以 **AGPL-3.0** 协议开源 —— 致敬 DeepSeek 的开源精神：模型开源，API 服务收费；
本项目同样开源客户端代码，未来核心能力将逐步服务端化。

- 任何人可自由使用、修改、分发本代码，但**衍生作品必须同样开源**（AGPL 传染性）
- 商业合作 / 闭源授权请通过 GitHub Issues 联系作者
- 本项目仅为客户端壳，各 AI 能力依赖用户自行配置的 API Key（火山方舟 / DeepSeek）
