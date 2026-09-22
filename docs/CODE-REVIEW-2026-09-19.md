# ReadFlow / AI上外语 — 代码与工程质量审查报告

- **审查对象**：`D:\readflow` @ `6e3b3f6`（v1.8.0+48，线上 Release v1.8.0）
- **审查日期**：2026-09-19
- **审查方式**：
  1. **OCR 委派模式**（alibaba/open-code-review 1.9.9）确定审查范围与规则：`ocr delegate preview --from v1.4.4 --to HEAD` → 45 个可审文件 / 12 个排除文件 / merge_base `0da0316`；`ocr delegate rule` 确认**仓库无自定义审查规则**（全部走 system default），文件清单与规则命中见 §7 覆盖表。
  2. **五个维度的并行只读审计**：数据层、AI 调用层、界面状态/内存、安全/发布、测试/UX 一致性。每条 finding 都带 `文件:行号` + 逐字原文引用。
  3. **主审复核**：对全部 CRITICAL/HIGH 结论逐条重读代码验证；**剔除了 2 条不成立的结论、修正了 4 条机制/影响描述错误的结论**（含 1 条由审计方自查撤回、1 条我自己最初判错后复核纠正，见 §6 与 §7）。
  4. **动效面审查**：按 `improve-animations` 的框架做 recon + 八类审计（§5）。
- **审查纪律**：引不出代码行的不作为 finding；风格偏好不作为 finding；每条给出"为什么是问题 → 怎么改"。

---

## 0. 结论摘要

**这个项目的"功能层"是健康的，风险集中在"发布链路"和"失败路径"。**

三件必须马上处理的事：

| # | 问题 | 为什么是现在必须处理 |
|---|---|---|
| P0-1 | **Release APK 用 debug keystore 签名**（`android/app/build.gradle.kts:32`），且**自动更新从 6 个第三方镜像下载 APK、零完整性校验**（`lib/services/update_service.dart:114/178/200`） | debug keystore 口令全球公开（`androiddebugkey`/`android`），任何人可签出"同签名"APK；Android 升级校验只看"同包名+同签名" → 被投毒的镜像或任何能向该公开仓库发 Release 的人，都能让已装用户静默装上被系统认可的"合法升级"。且 debug 证书 365 天到期后，老用户无法原地升级（本地词库会丢） |
| P0-2 | **数据库迁移吞异常**（`lib/services/database.dart:153-310` 每步 `catch(debugPrint)` 不 rethrow） | sqflite 在 `onUpgrade` 正常返回后就写 `user_version=9`。任一步真失败（磁盘满/SQLITE_BUSY）→ 半迁移被永久固化：v7 的 `phonetic` 列缺失会让**生词本彻底不可用且无法自愈**，v8/v9 的表缺失让写译/推荐功能全废 |
| P0-3 | **DS 思考模式的修复没同步到第二个 API 服务**（`lib/services/deepseek_api.dart:69/108/182` 仍硬编码 `max_tokens`，无思考通道兜底） | 这正是用户 9 月抱怨的"思考一长就失败"的根因，v1.8.0 只在 `doubao_api.dart` 修了。用户把副槽位配成 DeepSeek 时，**文章生成 / 回译练习 / 学习建议**仍会踩同一个坑 |

**值得肯定的部分**（避免误导读者以为整体不可用）：
- 无硬编码密钥（`sk-`/`ark-`/`Bearer` 全库零命中）；权限清单最小（仅 INTERNET / ACCESS_NETWORK_STATE / REQUEST_INSTALL_PACKAGES）；未关闭 TLS 校验。
- release 已开 R8 + 资源压缩；minSdk 24 / targetSdk 36；线上 APK 与本地构建产物字节数一致（22,340,440）。
- 176 个测试覆盖了全部"容易错且已错过"的纯逻辑（思考档位、页码归一、书籍分组、写译解析、复习进度、截断清洗）。
- 数据层 schema 与 9 步迁移**逐列核对一致**，不存在"只在 onCreate 建表、升级漏建"的硬伤。

---

## 1. 必须修（P0 / P1）

> 每条：`[file:line]` 问题 — 后果 → 改法

### P0-1 发布链路：debug 签名 + 第三方镜像零校验 〔安全〕
- `android/app/build.gradle.kts:30-32`
  ```kotlin
  // TODO: Add your own signing config for the release build.
  // Signing with the debug keys for now, so `flutter run --release` works.
  signingConfig = signingConfigs.getByName("debug")
  ```
- `lib/services/update_service.dart:114` 只取 `browser_download_url`，**丢弃 GitHub 已提供的 `digest`(sha256) 与 `size`**；`:178-185` 六个第三方域名，`:200` 用它下载 APK。
- **后果**：见 §0 P0-1。这是唯一"能导致用户装到恶意软件"的路径。
- **改法（两步，顺序不能反）**：
  1. 生成 release keystore（RSA 4096 / 25 年），`android/key.properties` 存路径口令（`android/.gitignore:10-14` 已备好忽略规则），gradle 构造 `signingConfigs.release`。
  2. 更新链路：`_buildInfo` 记录 `digest`/`size` → 下载后本地算 sha256 与字节数比对 → 不一致删除文件且**不调** `installApk`；镜像仅用于"检查更新"，APK 直连 github.com；保留镜像时弹窗明示来源。

> ⚠️ **需要你决策**：换签名密钥会让**当前已装的应用无法原地升级**（Android 要求同签名才能覆盖安装），必须卸载重装 → 本机 SQLite 生词库与 Hive 配置会丢。三个选项：
> **A.** 先做一次"词库导出/备份"功能，再换 release 签名（最稳，多一步开发）
> **B.** 直接换 release 签名，你自己手动重装并接受数据丢失（最快）
> **C.** 暂不换签名，但**立刻**补 sha256 + 原生签名指纹校验 + 镜像只读元数据（把"投毒"风险降到"必须改仓库 Release"级别）

### P0-2 迁移失败被固化 〔数据完整性〕
- `lib/services/database.dart:156-158`（每步同构，共 9 步）
  ```dart
  try {
    await db.execute("ALTER TABLE vocabulary ADD COLUMN part_of_speech TEXT");
  } catch (e) { debugPrint('ReadFlow DB migration v2 part_of_speech: $e'); }
  ```
- **后果**：`onUpgrade` 不抛 → `user_version` 推到 9 → 失败的步骤永不重跑。缺 `phonetic` 列时 `Vocabulary.toMap/fromMap` 无条件读写该列 → 生词本每次读写都抛 `no such column: phonetic`，用户只能清数据。
- **改法**：迁移步骤改为幂等写法（`CREATE TABLE IF NOT EXISTS` + `PRAGMA table_info()` 判断列存在再 `ALTER`），并把每步放进单一事务；`catch` 只在 `duplicate column name` / `already exists` 时吞，其他 `rethrow`；配合启动时一次"完整性自检"（缺列/缺表就补建）兜底。

### P0-3 第二个 API 服务未同步 DS 修复 〔正确性〕
- `lib/services/deepseek_api.dart:69`、`:108`、`:182` 硬编码 `'max_tokens': 4096/4096/1024`；`:68/107/181` 仍给 DeepSeek 发 `temperature`；`:75/114/188` 无"从思考通道取结果"兜底；`:202` `jsonDecode` 无 try/catch。
- **后果**：副槽位为 DeepSeek 时，文章生成/回译练习/学习建议在思考档位下正文被思考吃光 → `_parseJsonResponse` 抛 `FormatException` → `article_provider.dart:82` 把英文异常原文当提示（`生成失败：FormatException: ...`）。
- **改法**：把 `deepseek_api.dart` 的请求构造统一到 `DoubaoApiService` 的规则（DS 省略 `max_tokens`/`temperature`；content 空则 `extractJsonBlock(reasoning)` 兜底；解析走统一 parser）。**更彻底**：合并两个 API 服务（见 P1-1）。

### P1-1 两套并行的 API 层 = 同类 bug 必须修两遍 〔架构〕
- `lib/services/doubao_api.dart`（42KB，5 个请求构造点）与 `lib/services/deepseek_api.dart`（204 行）各自维护：请求参数、JSON 解析、错误处理。
- **后果**：本次审查直接实证——`max_tokens` 的根因修复只落在一侧；`parseResponse` / `parseWordInfo` / `parseWritingReview` 三份围栏剥离逻辑互不一致（`substring(start,end)` vs `substring(start+1,end)`）。
- **改法**：`deepseek_api` 的 3 个方法改为复用 `DoubaoApiService`（它已支持槽位参数）；围栏剥离统一走 `extractJsonBlock`。

### P1-2 SSE 逐块 `utf8.decode` 会把中文解坏 〔正确性，影响所有流式功能〕
- `lib/services/doubao_api.dart:369-370`
  ```dart
  await for (final bytes in rawStream) {
    buffer += utf8.decode(bytes, allowMalformed: true);
  ```
- **后果**：一个中文字符 3 字节被 TCP 包边界切开时，该块解出 `U+FFFD`，`allowMalformed: true` 不抛异常也不保留半字节 → **丢失不可恢复**。JSON 里含替换字符一般仍合法 → 坏数据静默入库；若吃到引号则 `jsonDecode` 抛错被 `_parseDataLine` 的 catch 吞掉（`:360-362` 只 debugPrint）→ 整帧正文静默丢失，表现为"AI 未识别到标记的单词"。识图/追问/材料生成共用此解析器。
- **改法**：改流式解码器 `buffer += await utf8.decoder.bind(rawStream)`；`_parseDataLine` 的失败要计数并在流结束时上报，不能静默。

### P1-3 流式 body 没有超时保护 → 前台永久转圈 〔体验/健壮性〕
- `lib/services/base_api.dart:24-26` 注释称 `receiveTimeout: 180s` 是"接收空闲超时"，但 dio 的 `receiveTimeout` 只覆盖"等响应头"阶段；`lib/screens/input/process_chat.dart:379` 的首字节计时器在**收到第一个 chunk 后就被 cancel**，回调还有 `_phase == connecting` 闸门。
- **后果**：第二个字之后卡住（网关半开连接/CDN 断流/服务端思考完不吐 content）→ `_phase` 卡在 streaming，前台无任何看门狗，只能杀进程。
- **改法**：加"流内空闲看门狗"——每个 chunk 重置 `Timer(60s)`，到点 cancel 订阅并切错误态；或对生成器套 `.timeout(60s, onTimeout: (s) => s.close())`。

### P1-4 重试栈会重复上传整份图片并重复计费 〔成本/体验〕
- 三层重试互不知情：`base_api.dart:78-101`（参数降级最多 3 次）× `doubao_api.dart:726-746`（带图被拒后重发一次）× `process_chat.dart:334-360`（回前台按**错误文案子串**`超时/连接/网络/Socket` 自动重试）。
- **后果**：一次追问/识图失败可能把同一份 base64 图片重传 2-4 次（每次数百 KB~数 MB），并按次计费；`_imageRejected`（`doubao_api.dart:776-789`）把**任何**含 `image` 字样的 400（包括 `request body too large`）都判成"模型不支持图片"而触发重发。
- **改法**：收敛成一个 `RetryPolicy`：最多 1 次重试；只在错误类型明确（415/422，或 400 且 body 命中原生"不支持图片"字样且不含 `too large|rate|length`）时降级；重试前必须真正换掉不兼容参数（现 Step 1 只删 `reasoning_effort`、仍留 `thinking: enabled`，对不认该字段的端点等于原样再发一次）；错误分类用枚举而非文案子串。

### P1-5 复习进度没存"已标记"，续看会重复计数 〔正确性（用户已抱怨过的同类问题）〕
- `lib/screens/review/review_screen.dart:47` `final Map<int, int> _marks = {};` 仅内存；`lib/utils/review_deck.dart:49-57` 的 `ReviewProgress` 没持久化它。
- **后果**：退出再续看后（v1.7.0 新功能），卡片上的"已标记：X"消失，**且对同一张卡再点标记会再计一次数** → 统计数 > 实际卡片数，与用户 9 月反馈的"一个词能一直点认识刷进度"是同一类缺陷的残留口子。
- **改法**：`ReviewProgress` 增加 `marks: Map<int,int>`（随进度一起存取），恢复时回填 `_marks`；`restoreDeck` 的下标夹取改为按 `lastId` 定位（`review_deck.dart:127-130` 现在会硬夹到 `deck.length-1`，删词后续看会跳到"最后一张"而不是断点）。

### P1-6 新流式功能丢弃思考通道 → 思考档位下推荐/精读直接失败 〔正确性（v1.8.0 回归）〕
- `lib/screens/input/ai_material_search.dart:112` `if (chunk.isReasoning) return;`；`lib/screens/input/material_recommendation_detail_screen.dart:105` 同。
- **后果**：DeepSeek 思考模型把答案整段写在思考通道时（用户正是把档位开到"极致/高"，且我们刚把这条链路修通），这两处 buffer 为空 → `:141` / `:119` 抛"AI 未返回可解析的推荐清单 / AI 未返回内容"。对照 `follow_up_drawer.dart:192` 已有兜底 —— 同一类 bug 在新页面上复发。
- **改法**：与 `FollowUpController` 一致——分别累积 reasoning 与 content，收尾时 content 为空则用 reasoning 兜底。

### P1-7 书籍/材料重命名与批量写路径无事务、无失效兜底 〔数据一致性〕
- `lib/services/database.dart:499-511` `renameBookPath` 只按 `material_path = ?` 精确匹配（子路径不管），无事务；`:516-534` `updateSourcePageByIds` 的 `IN (?,…)` 占位符数量 = 选中词数（上千词触发 `too many SQL variables`），调用处 `my_materials_section.dart:283` 无 try/catch。
- `lib/screens/profile/vocab_list.dart:86-88` / `:101-106` 用 `Future.wait` 扇出 N 路并发删除/移动，而 `VocabProvider.deleteVocabulary`（`vocab_provider.dart:139-149`）每次都 `await _refresh()`（4 次全表查询 + notify）→ N 路竞态刷新，低序号结果可能把已删数据写回列表。
- **改法**：DB 层加 `deleteVocabularies(ids)` / `updateVocabulariesCategory(ids,…)` / `replaceRecommendations(category, items)`（单事务 `IN` 子句 + 分片 ≤500）；VocabProvider 加 `_loadGen` 守卫；`renameBookPath` 用 `LIKE` 前缀事务更新并断言影响行数。

### P1-8 一行坏数据能毁掉整页 〔健壮性〕
- `lib/models/article.dart:31-47`、`lib/models/exercise.dart:38-55` 的 `fromMap` 全是硬转（`as String` / `as int` / `DateTime.parse`），且 `lib/providers/article_provider.dart:24-40` 的 `loadArticles` **没有 try/catch**，`_loading` 失败即永久 true。
- **后果**：任意一条坏行 → 文章/练习页永久转圈，且无任何错误提示。
- **改法**：与 `WritingLog` 对齐（`(map['x'] as String?) ?? ''`、`DateTime.tryParse(...) ?? …`）；`loadArticles` 用 try/finally 保证 loading 复位并写 `_error`。

### P1-9 索引缺失 + 外键未开 〔性能/数据卫生〕
- 全库无 `CREATE INDEX`；`openDatabase` 未设 `PRAGMA foreign_keys = ON`（`database.dart:24-29`）。
- **后果**：`GROUP BY category` / `DISTINCT source_book` / `ORDER BY created_at` 全表扫描 + 临时排序；`deleteArticle`（`:555-557`）删文章后 `exercises` 成孤儿行并被 `getTotalExerciseCount` 计入"已完成练习"。
- **改法**：dbVersion 10 迁移里补 8 个索引（vocabulary.created_at / source_book / category+created_at / category+material_path、exercises.article_id+created_at、bookmarks.created_at、writing_logs.created_at、recommendations.category+created_at）；开外键并清一次孤儿。

---

## 2. 建议修（P2）

| # | 位置 | 问题 | 后果 → 改法 |
|---|---|---|---|
| P2-1 | `database.dart:446-455` | `SELECT COALESCE(category,'其他')` 但 `GROUP BY category` | NULL 与 '其他' 分组两次、Map 覆盖 → 分类计数静默少算（与用户 9 月"数量对不上"同类）→ `GROUP BY COALESCE(...)` |
| P2-2 | `ai_material_search.dart:143-148` | `clearRecommendations` 后逐条 insert，无事务 | AI 半路失败即清空历史推荐（含已生成的学习正文）→ DB 层 `replaceRecommendations` 单事务 |
| P2-3 | `exercise.dart:69-76` + `database.dart:568-580` | 用户答案用 `'|||'` 拼串冒充 JSON | 答案含 `|||` 即错位、空串与未作答不可区分 → 改 `jsonEncode/jsonDecode`（需一次性数据迁移） |
| P2-4 | `process_chat.dart:2311` / `my_materials_section.dart:352` | 结果区/材料列表用 `ListView(children:)` 一次性构建 | 流式期间每个 token 重建全部卡片；251+ 词列表一次性建 5000 上限 → 改 `ListView.builder`；流式文本用独立 `ValueListenableBuilder` 局部重建 |
| P2-5 | `process_chat.dart:2774-2780` | 每行 `context.watch<BookmarkProvider>()` + `any()` 线性扫描 | N 行 N 次依赖注册与扫描 → build 里一次性取 `Set<content>`，逐行 O(1) |
| P2-6 | `crash_logger.dart:45-57` + `profile_home.dart:249-253` | 崩溃日志无大小上限、同步 flush 写；掩码泄露 Key 前 6 位 + 精确长度；日志不脱敏 | 循环错误时文件无界增长 + 卡 UI；截图上报会泄露 Token 片段与用户内容 → 加轮转（256KB）+ redaction（`sk-…`/`Bearer …`）+ 掩码只留长度 |
| P2-7 | `AndroidManifest.xml:10` | `usesCleartextTraffic="true"` | 代码侧已把 http 全量改写为 https，这个开关收益为零、只扩大明文面 → 删除（内网场景改 `networkSecurityConfig` 白名单） |
| P2-8 | `AndroidManifest.xml:8-12` | 未声明 `allowBackup`（默认 true） | API Key 明文 Hive + 学习数据随系统备份上云 → `allowBackup="false"` + `dataExtractionRules`；Key 迁 `flutter_secure_storage` |
| P2-9 | `update_service.dart:157-174` | `_parseVersion` 丢弃 `+build` 号 | "只升 build 号"的热修用户永远收不到 → 解析四段比较 versionCode；README 写明发布须递增 |
| P2-10 | 6 处 `addPostFrameCallback` 中 5 处无 `mounted` 保护（`stats_page.dart:17`、`profile_home.dart:35`、`vocab_list.dart:38`、`ai_article_section.dart:23`、`ai_material_search.dart:47`、`material_recommendation_detail_screen.dart:61`） | 进页立刻返回 → 回调里 `context.read` 打在 deactivated element 上 | 抛错并被 CrashLogger 记成"崩溃"，污染你赖以排查的诊断日志 → 统一加 `if (!mounted) return;`（`input_home.dart:50` 是正确样板），或抽 `postFrameGuarded` 小工具 |
| P2-11 | `follow_up_drawer.dart:169-201` + `:214-232` | `_stream` 在 `await imageDataUrisFor()` 期间若页面被销毁/列表被 `editMessage`/`clear` 改写，闭包仍按旧的 `aiMsgIndex` 写回 | 流式文字可能落到错误气泡或已 dispose 的 ValueNotifier → 消息加不可变 id、按 id 定位；`_stream` 首行 `if (_disposed) return;`，`dispose()` 置位 |
| P2-12 | `ai_material_search.dart:109-122` / `material_recommendation_detail_screen.dart:102-115` | `Completer` 在 `dispose()` 后永不完成 | 泄漏一个挂起的 Future 与其闭包 → `dispose` 里 `if (!done.isCompleted) done.completeError(_Cancelled())` |
| P2-13 | `vocab_list.dart:23` | `_searchCtrl` 无 `dispose()`（该类全文件无 dispose 覆写） | 反复进出"生词本"累积泄漏 → 补 `dispose()` |
| P2-14 | `process_chat.dart:2451-2476` | `_saveSingleItem(index)` 的 index 跨两次 await 使用 | 期间列表被删/被替换 → 保存错词或 RangeError；且无 in-flight 守卫可叠多个弹窗 → 按词快照或 word 查找、加入口守卫 |
| P2-15 | `deepseek_api.dart:202` / `doubao_api.dart:817-821` | 解析失败时把**完整 content** 拼进异常消息，再上屏并进会话快照 | 屏上出现模型引用的用户材料原文；错误气泡不可读 → 异常只带长度，原文进 `debugPrint`，UI 只显示前 200 字；`friendlyError` 对非 DioException 也套 `_truncate` |
| P2-16 | `doubao_api.dart:931-942` | `cleanTruncatedWord` 不看 `wordType`：`etc...` 这类合法词条被替换成整句 | 词与释义错配入库 → 仅 `sentence/phrase` 替换；`word` 型要求"去掉省略号后是原句前缀且长度差 ≥5" |
| P2-17 | `doubao_api.dart:589-597` | `parseWritingReview` 仅在 content 以围栏开头时剥壳 | 思考模型输出"好的，我来批改：\`\`\`json…"→ 整轮批改白花钱 → 统一 `extractJsonBlock`；`score` 正则取数字并 0-100 截断 |
| P2-18 | `doubao_api.dart:257/518/566` | 豆包侧仍硬编码 `max_tokens`（转写仅 2048） | 多页手写稿 + 思考档 → content 截断/为空 → 转写提到 8192、批改 8192，或统一省略 |
| P2-19 | `doubao_api.dart:228/263/428/715` | `isDs` 只按模型名判断 | "方舟端点 + deepseek 模型名"会发错整套参数（Ark 不认 `stream_options`、DS 不认 `minimal`）→ 改为 `baseUrl.contains('deepseek.com') && model.contains('deepseek')` 双条件 |
| P2-20 | `page_label.dart:30-69` + `database.dart:281` | 归一化会 `nums.sort()` 并剥掉所有字母（`Chapter 5` → `p5`），且 v9 已对**全量历史数据**执行 | 页码语义被改写且不可回溯 → 不排序、含字母的 token 原样保留、只在"全部纯数字且严格连续"时压区间；迁移前保留 `source_page_raw` |
| P2-21 | `review_screen.dart:47` + `review_deck.dart:127-130` | 见 P1-5 | 同上 |
| P2-22 | `README.md:25-31` | 发布流程缺 build 号纪律、mapping 归档、aapt 校验；功能列表停留在 v1.4 时代 | 新人/未来的你会漏步骤 → 补发布 checklist 与当前功能清单 |
| P2-23 | `pubspec.yaml:25` | `permission_handler` 声明未用（全库零调用） | 白带原生库与注册代码进包 → 删除 |
| P2-24 | `update_service.dart` + `file_paths.xml:4-7` | FileProvider 暴露 cache/files/外部存储整根 | 授权面过大 → 收窄到 `updates/` 子目录 |
| P2-25 | 无 CI | 每次发版靠人肉跑 `analyze/test/build/aapt` | 本次审查发现的问题里，P1-2/P1-4/P0-2 都能被"单测 + 静态检查"提前拦住 → 加一个最小 GitHub Actions：`flutter analyze` + `flutter test` + `aapt` 校验 versionName 与 tag 一致 |
| P2-26 | `PLAN.md:4` | 项目状态行仍写「当前版本：**v1.4.4** … 等用户真机复测 / DONE_WITH_CONCERNS」，而 `pubspec.yaml:4` 已是 `1.8.0+48`；v1.8.0 正文被追加在历史小节之后 | PLAN.md 被声明为项目状态的唯一事实源，现在会把接手的任何人（或 agent）带回 4 个版本前 → 状态区改为发布时强制更新（或由脚本生成），历史小节按版本倒序 |
| P2-27 | `write_review_screen.dart:269-301`（`build` 无 `PopScope`）对照 `process_chat.dart:1013-1014`（有完整退出三选） | 写译页手写最多 9 张图、原文可敲几百字，按返回键**草稿直接丢**，且不进 `writing_logs`（练习统计少记） | 高价值产物被静默放弃 → 加 `PopScope(canPop:false)`：文本非空或已出结果时弹「保存为写译记录 / 直接离开 / 取消」；结果页补一个常驻「保存记录」按钮（现在一次性弹窗点了"暂不保存"就再也回不来） |
| P2-28 | `follow_up_drawer.dart:695`（`savedConversations.clear()` + `:702` '清空全部'）、`bookmarks_screen.dart:123`（删除图标直连 `remove()`）、`ai_material_search.dart:351-360`（删推荐无确认、无反馈） | 三处**永久删除**单击即生效、无确认、无撤销、无 SnackBar；而同仓库另外三处（生词批量删除、文章删除、选中词删除）都有确认弹窗，四种形态并存 | 用户无法建立"要不要确认"的预期，且推荐条目的 `content` 是付费生成的精读内容 → 抽 `confirmDestructive()` 统一确认（红底 + "删除后不可恢复"），删除后给 SnackBar + 撤销；`重新推荐` 改文案为「清空并重新推荐」并先确认 |
| P2-29 | `review_screen.dart:590-616`（不认识/模糊/认识）vs `review_screen.dart:340/439` + `vocabulary.dart:194-203` + `vocab_detail.dart:134-150`（新词/学习中/已掌握） | 同一个 `masteryLevel` 字段在复习页用动作词、在词库页用状态词 | 用户点完「不认识」，回词库看到的是「新词」——**无法验证操作是否生效**（而这个 App 的核心动作就是标掌握度）→ 标签集中到 `AppConstants` 一处，两页共用（建议动作侧保留「不认识/模糊/认识」，状态侧显示对应词） |
| P2-30 | `stats_provider.dart:19-37`（无 try/catch）、`stats_page.dart:27-32`（只有 loading 分支）、`bookmark_provider.dart:15-23`（catch 只 debugPrint、`_loaded` 保持 false）、`bookmarks_screen.dart:21-23` | DB 读失败 → `_loading`/`_loaded` 永远停在中间态 | 统计页/收藏夹**永久转圈**；`ai_article_section` 的空态不区分"加载失败"与"还没有文章" → provider 补 `error` 字段 + `finally` 复位；页面显式三态并给「重试」；抽 `ErrorState/EmptyState` 两个组件统一替换裸 `Text` |
| P2-31 | `process_chat.dart:2211`、`:2598` | `Colors.grey[350]` = **`0xFFD6D6D6`**（Flutter `colors.dart:1830`，确实存在这个非标准档），压在白色卡片上对比度约 **1.45:1**（WCAG AA 正文要求 4.5:1） | 唯一的新手引导「点击询问 AI 详解 · 长按选中」和「翻译释义由 … 生成 · 仅供参考」几乎看不见 → 换 `theme.colorScheme.onSurfaceVariant`；全库 38 处 `grey[400]/[500]` 正文色（1.9–2.8:1）一并按语义色收敛 |
| P2-32 | `test/word_row_wrap_test.dart:5-21` | **空测试**：该用例自己 `pumpWidget` 一个 `Text(long, maxLines: null)` 再断言它的 `maxLines` 是 null —— 没有 import 任何 `readflow/` 组件，生产代码（`word_list_tile.dart:88-97`）改回 `maxLines: 2` 它照样绿 | 这条恰是用户实测回归 3 次的痛点（词条被拆行），守护测试实际为零 → 改为 pump 真组件后断言 `find.text(长句)` 的 `maxLines`，并加 `textScaleFactor: 2.0` 不溢出断言 |
| P2-33 | `profile_home.dart:60`（`masteredVocab: 0, // TODO: 从 vocab 统计掌握数`）、`:54`（`if (stats.totalVocab < 5) return;`）、`:66-68`（catch 静默） | 传给 AI 的「已掌握」恒为 0（付费调用基于错误画像）；词库 < 5 词或接口失败时「AI 学习建议」整块消失 | 用户无法区分"暂时没有"和"坏了" → `masteredVocab` 从 `vocabularies.where((v) => v.masteryLevel == 2).length` 计算；< 5 词时显示一行说明而非整块消失；失败给「重新生成」 |
| P2-34 | `ai_material_search.dart:91-122` | 推荐生成只 `await done.future`，无总超时、无 CancelToken、`_generating` 期间按钮 `onPressed: null` 且无「取消」按钮 | 模型持续吐字但永不结束时页面永久卡在「AI 正在推荐…」（`receiveTimeout` 只管"无数据"）→ 加总预算 `timeout` + 「取消生成」，取消后保留已生成片段并提示（与识图页/详情页对齐） |

---

## 3. 锦上添花（P3）

- `follow_up_drawer.dart:441-459` 在 builder 内注册 postFrameCallback（流式期间同帧多次注册）→ 改 `ScrollController` 监听 + 标志位。
- `input_home.dart:176-180`、`:737` 的 `Image.file` 未给 `cacheWidth` → 10 张 12MP 图约 480MB RGBA，低端机易 OOM → 缩略图 `cacheWidth: 200`。
- `flutter_markdown`（`pubspec.yaml:33`）上游已 discontinued（指向 `flutter_markdown_plus`），且渲染的是**模型返回的不可信 Markdown** → 迁移或自研最小渲染。
- `hive`/`hive_flutter` 停更却承载全部配置 → 逐步迁到 `sqflite`（已有 DB v9），消灭双持久化。
- `fl_chart 0.69.2` 落后一个大版本（最新 1.2.0）→ 单独排一次升级，别和功能混版。
- `mapping.txt` 未归档 → 发布脚本按版本存 `tool/symbols/<version>/`，否则 R8 混淆后的线上堆栈无法还原。
- 仓库卫生：根目录 0 字节的 `flutter` 文件（已跟踪，会干扰 `.\flutter` 调用）、`tool/` 的入库策略不明确、`.gitignore` 未覆盖审查工具产物 `/_ocr_*.json` 与脚本临时文件 `/_tmp_*`。
- 全库 **6 处 `addPostFrameCallback` 只有 1 处写了 mounted 保护**（系统性缺口，靠人记必然重犯）→ 抽辅助函数或加 lint。
- 交互重复：模型/思考档位菜单抄了 3 份（`input_home.dart:330-401`、`follow_up_drawer.dart` 的 `CompactModelPicker`、`process_chat.dart` 旧实现残留），筛选 chip 两份逐字节相同（`learner_profile_screen.dart:188-218` vs `review_screen.dart:384-417`）→ 抽公共组件后再谈其他重构。

---

## 4. 结构性结论：该拆什么、按什么顺序

1. **`lib/screens/input/process_chat.dart`（3058 行 / 115KB）是唯一的最大热点**，也是本次会话反复出问题的地方。它同时承担：流式状态机（连接/重试/降级/校准）、结果分组渲染、编辑/删除/添加弹窗、保存链路、追问上下文构建。建议按职责切三刀：
   - `process_chat_stream.dart`：状态机 + 重试 + 超时守卫（现 366-800 行）
   - `process_chat_results.dart`：结果列表/分组/编辑/删除/添加（现 2040-3058 行）
   - `process_chat.dart`：只留 State 骨架与 `build`
2. **`follow_up_drawer.dart`（916 行）第二刀**：`FollowUpController`（非 UI，1-317 行）与 UI 分文件；Controller 补 `_disposed` 语义（P2-11/P2-12 是同一根因，两处复发）。
3. **删除死代码**（约 200 行）：`_supplementMode` 整条链路（`process_chat.dart:132/400/576/688`，v1.8.0 合并"校准/补漏"后再无一处赋 true，含 `utils/supplement_merge.dart` 与其测试）、`services/material_search_service.dart` 与 `widgets/material_search_result_card.dart`（已被 v1.8.0 重写取代，仅剩自引用）、`DoubaoApiService.extractVocabulary` + `VocabProvider.extractFromPhoto`（无调用者）、`process_chat.dart` 尾部悬空注释。
4. **统一 API 层**（P1-1）：消灭"同一类 bug 修两遍"的土壤。

---

## 5. 动效与手感审查（improve-animations 框架）

**Recon**：Flutter 原生隐式动画 + `AnimatedSwitcher`/`AnimatedContainer`/`TweenAnimationBuilder`；无 `AnimationController`、无 `Hero`；`Curves.easeOut` 9 处；路由过渡 2 处；`Scrollable.ensureVisible` 3 处。性格：效率型学习工具（非娱乐 App），高频操作 = 卡片点击/长按选中/滚动跳转。

| # | 严重度 | 位置 | 问题 | 修法摘要 |
|---|---|---|---|---|
| A1 | MEDIUM | `review_screen.dart:533-534` | 「翻面」用 `AnimatedSwitcher` 纯淡入淡出 200ms + key=`"$_index,$_flipped"` | 卡片切换**没有方向语意**：翻面与换卡视觉上无法区分。改 `AnimatedSwitcher` + 水平位移（翻面：`Offset(0, ±0.04)` 纵向微移；换卡：按 `_index` 增减做 ±0.15 水平位移），或对翻面用 Y 轴旋转（`Transform(..rotateY)` 0→π）。时长：换卡 220ms `Curves.easeOutCubic`，翻面 260ms |
| A2 | MEDIUM | `word_list_tile.dart:55-56`、`process_chat.dart:2063-2064` | 选中态 `AnimatedContainer` 180ms，只动颜色/边框 | 长按选中是**高频**操作，180ms 只改底色会有"迟钝感"；加 1.0→1.01 的极轻缩放 + 100ms 内的左侧色条宽度动画，让"选中"有物理回应 |
| A3 | MEDIUM | 全库 | **无 `MediaQuery.disableAnimations` / `accessibleNavigation` 处理**（唯一相关用法是 `example_sentence.dart:55` 的 `textScaler`） | 系统开启"移除动画"后仍全量播放 → 在 `ScrollToTopButton`、卡片切换、流式滚动处读取 `MediaQuery.of(context).disableAnimations`，为真时把时长降为 0/改用瞬时跳转 |
| A4 | LOW | `process_chat.dart:1915-1917` | 思考进度条 `TweenAnimationBuilder` 600ms | 长任务进度用 600ms 缓动会显得"拖沓"；改 300ms `Curves.easeOut`，或改成不确定态（indeterminate）以匹配"未知时长"的语义 |
| A5 | LOW | `scroll_buttons.dart:130-131`、`process_chat.dart:823-848` | 多处 300ms `easeOut` 滚动 | 保留（滚动跳转 250-300ms 是合理区间）；仅建议把"回顶/回底"统一成 260ms 以免不同入口手感不一 |

**Missed opportunities（该动没动，属增量）**：
1. 识别结果**逐条入场**：现在整组一次性出现；按 `index*30ms` 做 ≤8 条的错峰淡入（stagger），能让"AI 正在识别出东西"这件事被感知。
2. 复习卡片的**掌握度标记**目前只有计数变化；在 `_markButton` 上做一次 120ms 的"按下去再弹回"（scale 0.96→1.0），并让顶部统计数字滚动更新（`AnimatedSwitcher` 数字位）。
3. 写译批改从"生成中"到"出结果"是硬切；给分数圆环一次 600ms 的 `TweenAnimationBuilder` 填充（`0 → score`）——这是全 App 唯一的"成就时刻"，值得一次动效。

---

## 5.5 测试质量与缺口（主审自查）

**总体：这套测试是"资产"而不是"装饰"** —— 21 个文件 / 176 例，全部是行为级断言（全文只有 2 处 `isNotNull()`/`isNotEmpty()` 这类弱断言），并且历史上真的拦下过回归（`test/restore_session_test.dart` 的 widget 测试抓住了"Hive 在 build 里写入 → 无限重建"这个挂死 10 分钟的缺陷）。密度分布也合理：思考档位 16 例、页码/分组/解析各 9-16 例。

但有三个具体缺口和一个"反向"问题：

1. **【反向】测试把缺陷固化成期望值** —— `test/update_service_test.dart:12`
   ```dart
   expect(UpdateService.compareVersions('1.2.20+30', '1.2.20+29'), 0);
   ```
   它断言"build 号不同也算相等"，正是 §2 P2-9（`_parseVersion` 丢弃 `+build`）这个缺陷本身。用例名还叫"带 v 前缀和 build 号"，说明作者以为覆盖了 build 号语义。**修 P2-9 必须同时改这条断言**（改成 `greaterThan(0)`），否则缺陷被测试保护起来、后人不敢修。
2. **【缺口】SSE 解析零测试** —— `doubao_api.dart:368-399`（`_parseSseStream`/`_parseDataLine`）是本次审查发现缺陷最密集的组件（P1-2 中文跨包、P1-4 分帧/多行 data/finish_reason），却没有任何测试。它目前是私有方法；建议提取为 `static Stream<SseChunk> parseSseStream(Stream<List<int>>)`（可见性仅为测试），用例至少覆盖：**中文被切在两个 chunk 之间**、CRLF 分帧、一个事件多条 `data:`、`[DONE]`、`reasoning_content` 与 `content` 分流、空事件/心跳。
3. **【缺口】请求体构造零测试** —— `_buildRequestBody`（`doubao_api.dart:157-236`）决定 DS 与方舟两套参数（P0-3/P2-18/P2-19 全在这里）。建议提取纯函数 `buildChatBody({model, baseUrl, messages, …})` 并按"DS 官方 / 方舟 / 未知网关"三档做矩阵断言（是否带 `max_tokens`、`temperature`、`stream_options`、`reasoning_effort` 取值）。
4. **【缺口】DB 迁移零测试** —— 9 步迁移（P0-2）是"一旦错就不可自愈"的代码。`sqflite_common_ffi` 可以在纯 Dart 测试里跑真 SQLite，建议补一条"从 v1 库升到 v10，逐列/逐索引核对 + 断点续跑（模拟某步失败）"的测试。
5. **【缺口】Provider 批量路径零测试** —— `vocab_list.dart:86-106` 的 `Future.wait` 扇出（P1-7）没有测试覆盖；provider 的竞态守卫（P1-7 的 `_loadGen`）修好后应补一条"并发 load 后以最后一次为准"的测试。
6. **轻微**：4 处测试依赖真实时间/随机（`follow_up_slot_test.dart:42`、`restore_session_test.dart:42/80`、`review_deck_test.dart:21`），跨零点运行时 `days: 1`（"今天"）这类断言理论上会闪；建议注入固定 `now`（`filterReviewItems` 已支持 `now:` 参数，测试没用）。另有测试间污染：`thinking_params_test.dart:118-120` 靠"把模型名写回空串"来隔离（`// 恢复默认豆包模型,避免影响其他测试`），Box 从不 `clear()`；`thinking_params_test.dart:67-72` 的 `expect(p, isNotNull)` 对 Map 恒真、等于没断言。
7. **【覆盖假象】一条被跳过的关键测试** —— `test/follow_up_slot_test.dart:77-79` 的 `skip: true`（文件头注明"FakeAsync + bottom sheet 挂起，待排查根因"）意味着**追问抽屉这个全应用最复杂的交互面（916 行）在单测层零覆盖**，而它历史上出过"第二问 400""头像不跟随槽位"两个真机 bug。建议别再死磕 FakeAsync + `DraggableScrollableSheet`：把 `CompactModelPicker` 的模型清单组装、`FollowUpController` 的槽位切换与 historyKey 选择抽成纯函数单测，widget 层只留"打开抽屉不抛异常"的冒烟测。
8. **【配置噪声】** `analysis_options.yaml:10-25` 的 `rules:` 下全是注释（零条自定义规则），而 PLAN.md 用"存量 info 零新增"（`:131` 21 条 / `:449` 24 条）来管理噪声 —— 告警会被淹没。建议只加 3 条真有产出的（`prefer_single_quotes`、`require_trailing_commas`、`always_declare_return_types`），并把 info 收敛纳入 §2 P2-25 的 CI gate。

**结论**：测试策略应从"纯函数覆盖"扩到"最易错的 I/O 边界"（SSE 解析、请求体、迁移）——这三处恰好是本次审查中 P0/P1 缺陷的来源，也是"修一次、下次自动不再犯"的最大杠杆。配合 §2 P2-25 的最小 CI（analyze + test），可以把本轮 60% 的问题变成"提交即拦截"。

## 6. 复核修正（子代理报告中被剔除或改写的内容）

审查纪律要求主审复核每条结论，以下是**没有原样采纳**的部分：

1. **剔除（不成立）**：`my_materials_section.dart:291` 的 `_items!` 强解包被列为 high 崩溃风险 —— 实际 `_grouped()` 只在 `_items != null && !isEmpty` 分支里被调用（`build()` 的三元判断在前），不构成空解包路径。
2. **改写（机制错误）**：`follow_up_drawer.dart` 的 `cancelOnError: false` 被描述为"订阅在 onError 后继续存在，一次提问可上传 4 份图片"。Dart 中 `cancel()` 会停止事件投递，"已入队回调仍执行"不成立；真实机制是**三层重试互相叠加**（参数降级 ≤3 × 带图被拒重发 1）+ `_stream` 在 `await imageDataUrisFor()` 期间存在"未被 `_disposed` 保护"的窗口。
3. **改写（事实错误）**：`_imageToDataUri` 被描述为"追加识别路径用全分辨率图、压缩策略失效"。实际 `doubao_api.dart:115-121` 对 >2048px 的图会缩到 2048 并转 JPEG；真实问题是"追加图未限制 `maxWidth`，body 可达数 MB，且被重试栈成倍放大"。
4. **降级（严重度）**：6 处缺少 `mounted` 保护的 `postFrameCallback` 被列为 critical。真实后果是 postFrame 回调抛错被 `FlutterError` 捕获并写进 crash_log（不崩 App），影响面是"诊断日志被污染"而非用户可见崩溃 → 调整为 P2-10。
5. **修正（影响面）**：`ai_material_search` 的 `Completer` 挂起被描述为"按钮永久禁用/一直转圈"；实际页面已 pop，影响是泄漏一个挂起 Future → 调整为 P2-12。
6. **剔除（不成立）**：`deepseek_api.dart:193-203` 被描述为"畸形 JSON 会无限递归到栈溢出"。实测该文件**连一个 `catch` 都没有**（`grep 'catch|_parseJsonResponse'` 只命中定义与两处调用），`_parseJsonResponse` 是直线代码，`jsonDecode` 失败只抛一次 `FormatException`，由 `article_provider.dart:81-86` 的 `try/catch` 接住 → 不存在自递归、更不会 StackOverflow。真实的缺陷只是"抛裸异常 + 英文原文当提示"（已并入 P0-3 / P2-15）。
7. **剔除（不成立）**：`review_deck.dart:37-41` 被描述为"「今天」用滚动 24h 窗口会筛掉当天存的词"。实测 `days == 1` 走的是 `DateTime(ref.year, ref.month, ref.day)`（**当天 00:00**，不是 `now-24h`），与注释一致，当天 09:00 存的词在下午仍会命中。仅 `days > 1` 是滚动窗口，而注释原文就写着"最近 N*24 小时(含今天)"——这是有意的产品取舍而非缺陷。**唯一可讨论点**（降为 LOW，需你拍板）：用户对"近3天"的直觉可能是自然日（第 1/2/3 天）而非"过去 72 小时"，若要改，`isAfter` 建议同时换成 `!isBefore`，并把测试改成注入固定 `now`。
8. **【自更正】对方自己撤回了原 A8**（"继续上次会话按钮点不动"标题与证据不符），替换为"推荐条目删除无确认、无撤销、无反馈"——该替换项已并入 P2-28。

---

## 7. 覆盖表（OCR 范围 v1.4.4 → HEAD）

- **可审文件 45**：全部完成审阅（5 个维度审计 + 主审复核 + OCR 规则核对）。
- **排除 12**：`ocr delegate preview` 判定为不可审（二进制/生成物/资源），例如 mipmap PNG、`pubspec.lock`、`assets/`。
- **规则命中**：42 个 Dart/MD/PS1 文件落入 **system default 规则组**；`**/*.swift`、`**/*.{yaml,yml}`、`**/*.{cpp,cc,cxx,hpp,hxx}` 各 1 个文件 —— **仓库没有自定义审查规则**。
  → 建议：把本项目的硬约束写成 `.ocr/rule.json`（或 `--rule`），至少三条：①DB 迁移必须幂等且失败可重试 ②DS 请求不得发送 `max_tokens`/`temperature` ③新页面必须在 `postFrameCallback` 里判 `mounted`。这样下次审查能自动回归这三条。
- **未覆盖/未验证**（诚实声明）：真机行为类结论（P1-3 的 mid-stream 卡死、P2-31 的对比度实际观感、HEIC 图片路径、`_addMoreImages` 的实际 body 大小）需要真机复现或抓包确认；本轮为纯静态审查，未运行 `flutter analyze`/`test`（避免在审查中改动工程状态）。
- **已完成的两项外部核验（非代码）**：
  - 线上 Release v1.8.0 的 asset `digest` = `sha256:2d2f0d04f700599b7d31310b18ef6eb717b16ae41a530c16ffaecf52d98f7d94`、`size` = 22340440，与本地 `build/app/outputs/flutter-apk/app-release.apk` 的 SHA256 **完全一致** → 证明本地构建产物就是线上件，也证明 GitHub **已经提供 `digest`/`size`**（P0-1 的校验料是现成的，不需要额外发 `.sha256`）。
  - `Colors.grey[350]` 在 Flutter SDK 里**确实存在**（`colors.dart:1830`，`0xFFD6D6D6`，仅 grey 有 350 档），所以 P2-31 的 1.45:1 对比度结论成立（这一条我最初凭印象判为"非法档位返回 null"，复核后确认是自己错了）。

---

## 8. 建议的修复批次

| 批次 | 内容 | 为什么这个顺序 | 预估 |
|---|---|---|---|
| **B1 阻断项** | P0-1（签名 + 校验，含你的 A/B/C 决策）、P0-2（迁移幂等）、P0-3（第二个 API 服务） | P0-1 是唯一"用户会装到恶意软件"的路径；P0-2 一旦触发就是不可自愈的数据故障；P0-3 是用户已经抱怨过的问题在新页面复发 | 0.5-1 天 |
| **B2 正确性回归** | P1-2（SSE 解码）、P1-6（思考通道兜底）、P1-5（复习进度存 marks）、P1-3（流内看门狗）、P1-4（重试收敛） | 都直接影响"AI 能不能用"，且都有明确的最小改法 | 1 天 |
| **B3 数据一致性** | P1-7（事务 + 批量接口）、P1-8（解析兜底）、P1-9（索引 + 外键）、P2-1/P2-2/P2-3 | 需要一次 dbVersion 10 迁移，合并成一次改动成本最低 | 0.5-1 天 |
| **B4 隐私与整洁** | P2-6/P2-7/P2-8、P2-23、仓库卫生（0 字节 `flutter`、`_ocr_*`/`_tmp_*` 忽略、死代码删除） | 工作量小、收益立竿见影 | 0.5 天 |
| **B5 体验与结构** | §5 动效三项 + P2-4/P2-5 性能 + §4 的 process_chat 拆分 + 交互组件抽取 | 拆分应在 bug 修完之后做，否则 diff 冲突成本高 | 1-2 天 |
| **B6 工程化** | P2-25（CI）、P2-22（README）、P0-1 的 map 归档、依赖治理（flutter_markdown/hive/fl_chart/permission_handler） | 让"下次不再靠人肉记住这些" | 0.5 天 |

---

## 9. 测试清单（修复后逐条验证）

**功能**
- [ ] 识别/追问/写译批改/材料推荐四条流式链路，在 DeepSeek「极致」档位下都能出结果（P0-3、P1-6）
- [ ] 断网/限速/中途断流：60s 内出现明确错误，不再永久转圈（P1-3）
- [ ] 复习：标记 → 退出 → 重进续看 → 统计数仍等于卡片数（P1-5）
- [ ] 书籍重命名/页码修改/批量删除/批量移动：数据与界面一致，失败有提示（P1-7）

**数据**
- [ ] 从 v1.7.0 库升级到 v10：列/表/索引齐全，旧页码被归一（P0-2、P1-9、P2-20）
- [ ] 人为造坏行（`created_at` 非法、`exercises` 缺字段）→ 文章页仍可打开并提示（P1-8）

**边界**
- [ ] 0 条生词、1000+ 条生词、超长手写稿（>8 张图）、特殊字符书名（含 `%`/`_`）
- [ ] 图片：HEIC、4000×3000、10 张连续上传（P2-18、P3 图片内存）

**发布**
- [ ] `flutter analyze` 0 error / 0 warning；`flutter test` 全绿（当前基线 176 +1 skip）
- [ ] `aapt dump badging` 校验 versionCode/versionName；sha256 与 Release asset `digest` 一致（P0-1）
- [ ] 用 `apksigner verify --print-certs` 确认发布签名指纹与文档记录一致（P0-1）
- [ ] 下载走镜像时的提示、取消、失败重试路径各走一遍（P0-1 第二步、P2-34）

**一致性（新增，对应 P2-27…P2-29）**
- [ ] 写译页：输入几百字 / 传 9 张图后按返回键 → 弹「保存为写译记录 / 直接离开 / 取消」，选保存后能在「写译记录」看到
- [ ] 危险操作四处（收藏删除、追问「清空全部」、推荐删除、重新推荐）→ 都有确认，删除后有「已删除 + 撤销」
- [ ] 复习页标「不认识」→ 回生词本/详情页，两处标签语义一致、能对应上

---

## 10. 修复落地记录（v1.9.0，2026-09-21）

按 §8 的批次全部执行完毕。下面只记**结论**与**偏离**，逐条改法见对应条目。

**B1 阻断项（3/3）**
- P0-1 **部分**：`UpdateService` 现在校验 sha256 + 字节数（料取自 GitHub Release asset 的 `digest`/`size`），直连优先、镜像兜底并提示；`verifyApk` 二者皆无时**拒绝安装**。**签名未升级**——仍为 debug keystore 签名（审查给的 A/B/C 三条路各有权衡，需产品决策，本轮先按 C 走：把校验做扎实）。`apksigner verify --print-certs` 已跑通，指纹记录在 v1.9.0 Release 说明里。
- P0-2 迁移全部改幂等（`_ensureColumn`/`_ensureTable`）+ 单事务 + 真实错误`rethrow`，`_onOpen` 增加一次自检修复；**顺手补上审查自己漏掉的坑**：`_onCreate` 建表语缺少 `phonetic` 列 → 全新安装必崩（§5.5 之外的增量发现）。
- P0-3 `deepseek_api` 三个方法全部走 `buildChatBody`（DS 省略 `max_tokens`/`temperature` + `stream_options.include_usage`）+ 思考通道兜底 + 不再抛裸异常。

**B2 正确性（5/5）**
- P1-2 SSE 改为 `utf8.decoder` + `LineSplitter` 流式解码（中文跨包不再损坏），解析失败计数并在流结束时抛出可诊断错误；新增 6 条解析测试。
- P1-3 流内空闲看门狗（60s）落在识图/追问/材料推荐三条链路；P1-4 重试收敛（降级 ≤1 次、`degradeOnce` 同时摘掉 `reasoning_effort` 与 `thinking`）；P1-5 复习进度存 `marks` + 按 `lastId` 续看；P1-6 两处 reasoning 兜底。

**B3 数据（6/6）**
- dbVersion 10：9 索引 + 外键 + 孤儿练习清理 + 页码归一（P2-20：不再排序、含字母 token 原样保留）。批量接口 `deleteVocabularies`/`updateVocabulariesCategory`/`replaceRecommendations` 均单事务分片；`fromMap` 全部容错化；`VocabProvider._loadGen` 竞态守卫。

**B4 隐私与整洁（5/5）**
- `allowBackup="false"`、删 `usesCleartextTraffic`、Key 掩码只留厂商+长度、崩溃日志脱敏+256KB 轮转、`file_paths.xml` 收窄到 `updates/`（P2-24，APK 下载目录同步改为 `cache/updates/`，已核对 `path_provider` 的 `getApplicationCacheDirectory()` = `getCacheDir()`）、`permission_handler` 删除、3 个死文件删除、0 字节 `flutter` 文件移除、`.gitignore` 补 `/_ocr_*.json` `/_tmp_*`。
- P2-8 的**后半段（Key 迁 `flutter_secure_storage`）未做**：需要引入新的原生加密依赖 + 迁移存量 Hive 值，属"换存储"级改动，风险高于本轮其余修复，留待单独一版。

**B5 体验与结构（部分）**
- 完成：写译页 `PopScope` 三选 + 常驻保存按钮（P2-27）、四处危险操作统一确认+撤销（P2-28）、标签语义统一（P2-29）、统计/收藏/文章三态（P2-30）、正文灰阶 AA（P2-31）、词表惰性构建（P2-4 一半）、书签帧缓存（P2-5）、动效 A1–A5 全部落地。
- **未做（明确留到下个版本）**：`process_chat.dart` 三分拆（§4.1）与 `follow_up_drawer` 控制器分文件（§4.2）、交互组件抽取（模型/档位菜单 3 份、筛选 chip 2 份）、§5 的 3 条"该动没动"增量（结果错峰入场、标记按钮回弹、分数环填充）、`process_chat` 结果区的 Sliver 惰性化（该处卡片数受识别输出限制，收益低于拆分后的重构成本）。

**B6 工程化（4/4 + 1 部分）**
- CI（analyze + test）已加；README 重写（发布 checklist 含 build 号纪律、mapping 归档、aapt 校验）；`PLAN.md` 状态区恢复为唯一事实源；mapping 归档已在本版发布时执行（`tool/symbols/1.9.0/`）。
- **注意（v1.9.0 发布时的一次性卡点）**：`.github/workflows/ci.yml` 这类 workflow 文件需要 gh token 具备 **`workflow` scope**，当前 token（`gho_`，scope: repo/gist/read:org/delete_repo）没有 → 经 git-data API 推送含该文件的 commit 会被 GitHub 拒绝（返回 404 Not Found，不是权限提示，很容易误判）。本版先同步了**不含** CI 文件的内容，CI 文件留在本地待 `gh auth refresh -s workflow` 后补推。
- 依赖治理：`permission_handler` 删除；`flutter_markdown`（discontinued）/`hive`/`fl_chart` 升级**未做**——三者都需要独立版本验证，不与本次 bug 修复混版（与审查 §3 的建议一致）。

**补充（子代理中断后由主审收尾）**
- **P1-2 的修复在真机上翻过车（v1.9.1 已修）**：SSE 改流式解码时写了 `rawStream.transform(utf8.decoder)`，而 dio 的流运行时是 `Stream<Uint8List>` → 真机抛 `type 'Utf8Decoder' is not a subtype of type 'StreamTransformer<Uint8List, String>'`，识图/追问/文章/推荐全线失效。单测用 `Stream<List<int>>` 造流所以没拦住。修法 `cast<List<int>>()`，并把 SSE 全部用例改用 `Stream<Uint8List>` 造流 + 新增 2 条回归用例（修复前逐字复现真机报错）。**结论：审查给的"改法"本身没错，但"流式解码"这类改动的验证必须用与生产一致的运行时类型，否则测试会给出虚假的安全感。**- P2-31 的灰度收敛补齐：`process_chat`、`my_materials_section`、`vocab_list`、`writing_logs_screen` 等文件的**正文**灰阶统一提到 `grey[600]`；图标/边框/分隔线/背景有意保留原灰阶（不是正文，改了只会改变视觉层次）。
- P2-32 的"2× 字号不溢出"断言**真的抓到一处缺陷**：`WordListTile` 的词性标签没有弹性约束，2× 系统字号下 `Row overflowed by 25 pixels` → 标签改为 `Flexible`（超宽时省略，长词条优先完整），已随测试一起修掉。
- P3 收尾：`Image.file` 缩略图与大图预览按显示宽度解码（`cacheWidth`，12MP 原图不再整张进内存）；追问抽屉"滚到底"的 `postFrameCallback` 改为每帧至多注册一次（原来流式期间每个 chunk 都注册一次）。

**验证**：`flutter analyze --no-fatal-infos` = 0 error / 0 warning（24 infos，与修复前同量级）；`flutter test` = **192 例全绿 + 1 skip**（修复前 176 +1）。新增 `test/v19_fixes_test.dart` 19 例：SSE 解码 5、降级策略 2、请求体矩阵 2、写译批改解析 2、识别解析 2、截断清洗 2、复习进度 2、练习答案编码 2；页码归一由 v18 测试守护，dbVersion/索引由 `widget_test` 断言。`test/word_row_wrap_test.dart` 从"自造 Text 的假测试"改为真正 pump `WordListTile` 并断言其内部 `Text`（含 2× 字号不溢出）。
