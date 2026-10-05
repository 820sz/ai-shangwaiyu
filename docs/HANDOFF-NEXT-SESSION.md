# 交接文档 · 给下一个对话(2026-10-04 写)

> 这份是**给人看的一页纸**。更细的历史在 `PLAN.md` / `docs/HANDOFF-2.5.md` / 任务板里,
> 本文只写"接手时你必须知道的事",不重复那些。

---

## 0. 一句话现状

**AI上外语(ReadFlow)= 用户 10/4 提的 8 条全部交付、v2.10.0 已发布、远端已同步、工作区干净。
现在唯一悬着的是我写的一个测试文件整体跑会挂住(App 功能不受影响),以及用户在真机上的复测结果。**

| 项 | 值 |
|---|---|
| 版本 | `pubspec.yaml` → **2.10.0+67** |
| Release | **v2.10.0 = Latest**(APK sha256 `0068a9d5…1667`,与 GitHub release asset digest **逐字一致**) |
| 提交 | 本地 HEAD `aa8d608`,tree `a9f4265a…` = **远端 master tree 完全一致** |
| 绿灯 | `flutter analyze` **0 error / 0 warning**(11 条存量 info);`flutter test` **961 passed + 1 skip** |
| 数据库 | **dbVersion 17** |
| 依赖 | **零新增依赖**(书架、封面、等待动画全部自绘/自写) |

---

## 1. 事实源(别重复造,先读这些)

| 文件 | 管什么 |
|---|---|
| `PLAN.md` 顶部三行 | **版本号 / 阶段的唯一事实源**(每次发版必须同步改) |
| `docs/HANDOFF-2.5.md` | 交接主文档:命令、坑、提交地图、§8 复测清单 |
| `docs/TASK-BOARD-2026-10-04.md` | **本轮(8 条)的用户原话 + 根因表 + 逐条交付** |
| `docs/release-notes-v2.10.0.md` | 给用户看的更新说明(也是发给他的口径) |
| `docs/SPEC-material-discovery-2026-10-01.md` | 材料中心对标调研(8 款 App 实测) |
| `C:\Users\xi283\.dsh\memory\readflow-dev-session.md` | 跨会话记忆(v2.10 五条教训写在里面) |

---

## 2. 铁律(用户明确要求过,违反会被骂)

1. **只做他列的事** —— 不顺手改别的功能。
2. **核心功能出问题:先把现有实现摊开 + 根因分析,再动手**。他最反感"不回答问题直接改代码"。
3. **涉及全 App 视觉/交互的大改,先给 2~4 个方案让他选**(原话:"不确定的就给我推荐几个方案,让我来选,不要自己瞎搞")。
4. **每批做完报一次**;不要完成一小个就停,也不要闷头不吭声。
   **先回话,再干活** —— 他催进度时如果还在跑命令/等后台任务,会被视为"卡死"。
5. **禁止自杀式操作**:不要 taskkill / 杀 node / 杀 3080(那是他 DSH 服务本体)。
6. **禁止用 PowerShell 文本命令改源码**(`Set-Content` / `Get-Content|Out-File` / `-replace`),
   只用编辑器工具(read/write/edit)。中文必须 UTF-8。(曾把整个文件写成 mojibake,不可逆)
7. **发版前必须 bump 版本号**;发布后核对 APK 的 sha256 与 release asset digest 一致。
8. **不要新增 pub 依赖**(`file_picker` 那次教训:analyze/test 全绿但 APK 构建不过)。
9. **界面里不许出现 `CircularProgressIndicator`**(全 App 已改成
   `lib/widgets/waiting.dart` 的 `AiWaitingTimeline` / `SkeletonLines` / `ProgressStageBar`;
   唯一例外是音频缓冲条)。
10. **一排按钮必须能换行** —— 用 `Wrap` + 紧凑样式,不要无约束的 `Row`
    (他截图骂过"按钮被裁成'原'字";同类问题也发生在 `Expanded` 里塞长徽标把单词挤断行)。
11. 注释写中文,并写清"为什么"(他会在意"你当时怎么想的")。

---

## 3. 命令(PowerShell 5.1,**没有 pwsh 命令**,所有命令在 `D:\readflow` 下跑)

```powershell
$env:FLUTTER_ALREADY_LOCKED = 'true'     # 每个新 shell 都要,否则 flutter 卡锁
flutter analyze --no-fatal-infos        # 期望 11 条存量 info、0 error / 0 warning
flutter test                            # 全量:961 passed + 1 skip;一次十几分钟,别反复跑
flutter test test/xxx_test.dart         # 改完先跑相关文件(重要:全量只留到发版前跑一次)
flutter build apk --release --target-platform android-arm64
# 校验 APK:
& 'C:\Users\xi283\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt.exe' dump badging build\app\outputs\flutter-apk\app-release.apk | Select-String versionName
# 发版(gh CLI 已登录 820sz):
gh release create vX.Y.Z build\app\outputs\flutter-apk\app-release.apk --title "..." --notes-file docs\release-notes-vX.Y.Z.md
gh api repos/820sz/ai-shangwaiyu/releases/tags/vX.Y.Z --jq '.assets[0].digest'   # 与本地 sha256 比对
# 同步远端(不是 git push!):
Set-ExecutionPolicy -Scope Process Bypass -Force
$env:RF_DIFF_BASE = '<tree 与远端一致的本地提交>'   # 比对 git rev-parse 'HEAD^{tree}' 与远端 tree.sha 找它
& .\tool\push_via_api.ps1                            # 打印 PUSH_VIA_API_DONE 才算成功
```

---

## 4. 已知的坑(踩过的,别再踩)

1. **中文文件名会让同步脚本断掉** —— `push_via_api.ps1` 里 `git rev-parse "HEAD:<文件>"`
   遇到中文路径会被 PowerShell 编码搞坏(`SPEC-材料中心发现页…` 那次)。**新文件一律用 ASCII 名**。
2. **`edit` 工具的 `old_string` 带尾换行会静默吞掉一行**(`\n` 被当成行连接)——
   改完一定回读确认。
3. **`flutter test` 全量一次十几分钟** —— 改完先跑相关文件;发版前跑一次就够。
   反复跑全量 = 用户以为你卡死(这就是这次被骂的原因)。
4. **`pumpAndSettle()` 在某些 widget 测试里不收敛** → 整文件挂住(见 §5)。
5. **长按/点击入口类改动,必须自己确认"点得到"** ——
   用户两次说"名片无法编辑",第一次是因为根本没有昵称字段、入口只是角落一个小铅笔。
6. **`ImportedMaterialsSection` 那类"列表串数据"的 bug**,根因通常是拉了全表而没按来源过滤。

---

## 5. 唯一未完成事项(优先级最高)

**`test/profile_card_test.dart` 整文件跑会卡住** —— 2026-10-04 已排查到可复现的结论:

| 现象 | 结论 |
|---|---|
| 5 个 widget 用例**每个跑满 10 分钟**才失败(日志时间戳 `10:01 / 20:01 / 30:01 / 40:01`) | **`tester.pumpAndSettle()` 在这个页面永不收敛** —— 它默认等满 10 分钟才抛错,5 个用例 = 50 分钟(用户看到的"卡半小时"就是这个) |
| `tearDownAll` 从 `40:01` 挂到 `82:13` | **不要在 widget 测试里调 `Hive.close()`** —— 它要 flush 异步写,而测试用假时钟,flush 永远等不到 |
| `点卡片空白处` 报 ambiguous | 测试 bug:`find.text('我')` 同时命中头像占位与昵称(两个"我"),不是产品问题 |

**已经改掉的两处**(本次提交):
1. 文件顶部新增 `settle(tester)`(`pump()` + 有界 `pump(400ms)`),**全文件替换掉 `pumpAndSettle()`**;
2. `tearDownAll` 不再调 `Hive.close()`,只尽力删临时目录;
3. `点卡片空白处` 改成按**卡片矩形**取点(`rect.left + 4`),不再用文字 finder。

**改完后的实测**:前 22 个用例(含全部纯函数用例与 4 个界面用例)**全部通过**,耗时从
"每个 10 分钟"降到 **~1 秒**;但仍会在 `没有自选背景图时不显示四个图片调整项` 这一步挂住
(第 23 个用例之后)。**不影响 App 功能**,也**不影响其它测试文件**。

**建议的下一步**:把那 3 个仍会挂的界面用例逐个用
`flutter test test/profile_card_test.dart --plain-name '<用例名>'` 跑一遍(单独跑都是秒过),
再决定是给每个用例加超时(`testWidgets(..., timeout: Timeout(Duration(seconds: 10)))`),
还是把它们拆到单独文件。**改完只跑这一个文件验证,别跑全量。**

---

## 6. 下一步该做什么(按优先级)

1. **等用户真机复测 v2.10.0**,按 `docs/HANDOFF-2.5.md` §8 的清单问/看:
   翻译(先弹范围 → 进度条动不动 → **取消是否立刻停**)、书架、封面、名片大小形状、
   收藏夹有没有 AI 符号残留、内容类型是否影响检索、材料导入是否只剩自己导入的、移动材料。
2. 修掉 §5 的测试挂起。
3. **两个等用户拍板的事**(他还没回):
   ① 材料配图:程序化封面(已做)/ **AI 生图**(≈0.1 元/篇)/ 自购插画库;
   ② AI 阅读形式(表格·导图等)是否要加"每天最多 N 次"的额度上限(现在是点了才生成)。
4. 反馈回来后的规矩照旧:**只做他列的事 → 先摊开分析 → 每批报一次 → bump → 发版 → 同步 → 文档+记忆**。

---

## 7. 最近三版做了什么(便于回答"这功能什么时候加的")

| 版本 | 用户提的 | 主要内容 |
|---|---|---|
| **v2.10.0**(10/4) | 8 条 | 翻译五处真 bug 修复 / 标题中文化**落库** / 打开材料真流式 / 内容层面分类 10 类 / 今日推荐可点开 / 封面重做 / 材料导入只收自己导入的 / **书架**(自绘真书架 + 退出三选一)/ 名片大小形状与背景调节 / 收藏夹阅读界面去 AI 符号 / 移动材料从已有分类选 / 拍照相册合并入口 |
| **v2.9.0**(10/2) | 5 条 | 练习系统重做(目标多选·三模式·进度追踪)/ 阅读器翻译进度与自选范围 / AI 阅读形式(表格·导图·时间线·要点·自测)/ 阅读进度留存 + 统计页「最近在读」/ 材料导入与我的词汇本拆分 / 全 App 转圈换骨架屏·时间线·进度条 |
| **v2.8.0**(10/1) | 10 条 | 识图追加图片闪退修复 / 中文批注合并(DB annotation)/ 询问 AI 过渡 / 复习卡住与单词截断 / 学习助理重做(四方向 + 给选项的访谈 + 对话管理)/ 材料中心图文卡片与流式检索 / 输出拼写与翻译练习 / 追问配色 / 我的名片 / 收藏夹四分类 |
