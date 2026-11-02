# 阅读器翻译「永远没法用 / 进度永远是死的」根因侦查（C1-19）

> 边界：**只读不改源码**，未运行 `flutter build/run/analyze`。依据 = 当前工作区代码（git HEAD `eeea4b4`；`material_reader_screen.dart` / `deepseek_api.dart` / `base_api.dart` / `material_source.dart` / `material_import.dart` / `material_library.dart` 本轮均无未提交改动）。
> 侦查时间：2026-11-01 ｜ 对应任务：`TASK-BOARD-V3.md` C1-19（批 2 首要）
> 用户原话（2026-11-01）：「里面的文章阅读器的翻译功能永远没法用，翻译进度永远是死的。」

---

## 0. 结论先行（一句话）

**翻译的最小单元错了：阅读器把「2500 词的正文块」当成「一个段落」。**

- **「进度永远是死的」**：典型文章 = 1 块 → 进度分母恒为 **1**；且最后一段完成时 `_runTotal` 在渲染前先被清零 → 进度条**从出现到消失只能是 0%**（`material_reader_screen.dart:404-409`）。即使公版书有几十块，每块也要几十秒~3 分钟，分子按「块」走，观感仍是死条。
- **「永远没法用」**：一次请求 = 整篇文章/整章原文（不是一段）。模型按空行把它翻成 N 段返回，而调用方只传了「1 段」→ 段数对不上 → **只抢救第 1 段译文并静默显示**（`deepseek_api.dart:298-307` + `material_reader_screen.dart:428-434`）；长块还会被输出上限截断 / 180s 首字节超时 → 整块失败。失败段不会自动重试、译文只存内存不落库 → 每次进阅读器都从头再失败一次，这就是「永远」。
- **前几轮为什么修不好**：v2.9 / v2.10 / v2.12.2 三次重做都在修**进度记账、取消、分批、提示词**，从来没有质疑「一块 = 一段」这个前提；v2.10 的「maxTokens 自适应 1200~8192」修复在**副槽位 DeepSeek 官方**这条路上根本不生效（`base_api.dart:77-87` 对官方端点省略 max_tokens）——所以用户配了 DeepSeek 副槽位时，那次修复等于没做。

---

## 1. 链路全貌

### 1.1 入口清单：翻译有 6 个入口，全部汇到**同一个** `_translateOne`

| # | 用户在界面上的动作 | 方法（`lib/screens/input/material_reader_screen.dart`） | 选哪些「段」 | 最终调用 |
|---|---|---|---|---|
| 0 | 底部动作栏「翻译」chip（唯一主开关） | `ReaderActionBar` chip → `_toggleTranslation`（:272-290） | `_enqueueVisible(limit: 5)` = 当前可见块，最多 5 | `_translateOne` |
| 1 | **打开即翻当前屏** | 同上，toggle 打开后立刻 `_enqueueVisible`（:287-289） | 可见块 ≤5 | 同上 |
| 2 | **随读随翻**（滚动停下 450ms） | `_onScroll`（:968-982）→ `_scheduleVisibleTranslation`（:808-816）→ `_enqueueVisible`（:818-825） | 可见块 ≤5 | 同上 |
| 3 | 「继续翻后文」 | `_translateNext`（:709-749） | 当前屏没翻完 → 可见块；都翻好 → 从可见末块往后 3 块 | 同上 |
| 4 | 「整章」 | `_translateChapter`（:755-784） | 当前位置往后 **20 块** | 同上 |
| 5 | **逐段重试** | 段末「重试」`_retryChunk`（:683-691）／控制条「重试失败段」`_retryFailedChunks`（:787-800，一次最多 6）／译文菜单「重翻这段」`_retranslateChunk`（:695-703） | 指定块 | 同上 |
| 6 | 取消 | 控制条「取消」`_cancelAllTranslation`（:502-505）／段内「取消这段」`_cancelChunkTranslation`（:509-537） | — | `CancelToken.cancel` |
| — | **自选范围** | **v2.12.2 已删除**。旧四档「当前段/前后各3段/当前章/整篇」只剩死代码 `blocks.TranslateScope` / `planTranslation`（`material_blocks.dart:834-913`），阅读器已不引用，只有 `test/material_blocks_test.dart:292-437` 还在测它 | — | — |

> 另有**一条独立链路**（不是本 bug 的现场，但可作对照）：AI 找材料详情页 `material_recommendation_detail_screen.dart:75-115` 是**按空行拆真段落**、每批 8 段、串行 `translateParagraphs` —— 同一产品里「真段落翻译」的写法是存在的，阅读器却没用。

### 1.2 关键事实：阅读器里的「段」（`_chunks`）不是段落，是**正文块**

```
材料入库（所有材料中心通道）
  MaterialSourceService.chunkByWords(text, wordsPerChunk: 2500)   ← 每块 ≈2500 词
  │  material_import.dart:113 (文件导入) / :146 (图片提取)
  │  material_source.dart:752 (外链) / :1354 (外媒文章页)
  │  material_source.dart:859 + :938-983 (Gutenberg：按章切，≤6000 词一章 = 1 块；否则每 4000 词一块)
  │  material_library.dart:295-298 (粘贴材料：**整篇 1 块**，不切)
  ▼
material_content 表 chunk_index 0..N（database.dart:1894-1907 getMaterialChunks）
  ▼
MaterialReaderScreen._load(): _chunks = chunks   ← material_reader_screen.dart:1152,1169-1171
  ▼
ListView.builder(itemBuilder: _buildChunk)        ← 一个块 = 一个列表项 = 一个 TappablePassage
```

佐证「块 = 段」这个口径贯穿全项目：
- `material_import_flow.dart:183-186` 打开材料的过程文案直接写「**抓到正文:${doc.chunks.length} 段**」——一篇文章会显示「1 段」；
- v2.10 发布说明原话「**67 段要 23 次往返**」「公版书必报错：maxTokens 写死 4096，**长段**翻译被截断」（`docs/release-notes-v2.10.0.md:12-14`）——67 段就是 67 章/块，不是 67 个自然段；
- 阅读器自己的注释假设是「手机一屏通常 **3~5 段**」（`material_reader_screen.dart:148-150`）——按 2500 词/块算，一屏根本放不下 1 块。

### 1.3 一次「点翻译」的完整时序

```
用户点 chip
  └ _toggleTranslation (reader:272)
      ├ setState(_showTranslation=true, _autoTranslate=true)
      └ _enqueueVisible(limit:5) (reader:818)
          ├ _visibleChunkIndices(limit:5)  (reader:305-325，用 RenderBox 求交，兜底 _fallbackVisible)
          └ _enqueueTranslation(indices)   (reader:359-377)
              ├ _pendingChunks.add / _queue.add / _chunkJobEpoch[i]=++epoch
              ├ _runTotal += fresh.length    ← 进度分母（= 块数！）
              └ _pumpTranslationQueue()      (reader:381-410)
                  └ while 在途 < 2:
                      _translateOne(index, epoch)  (reader:416-455)
                        └ DeepseekApiService().translateParagraphsRich(
                              ['${_chunks[index]['text']}'])   ← ★ 整块原文当「1 段」发出去
                            (deepseek_api.dart:252-309 → base_api.postWithReasoningFallback → Dio)
                        └ 成功后 setState(_translations[index]=first)
                    whenComplete: _runDone++ ; 若队列/在途都空 → _runTotal=_runDone=0（reader:404-408）
```

翻译 API 侧：`translateParagraphsRich` 的 system prompt 明确要求 `{"translations":[...]}`、**「段数必须与输入完全一致」**（`deepseek_api.dart:263-271`），输出预算 `(700 + chars*2).clamp(1200, 8192)`（:272-274），失败兜底「只保留前 k 段」（:298-307）。

---

## 2. 根因假设（按概率排序）

### H1（≈85%，主因）：翻译单元 = 2500 词的块，而 UI/提示词/进度全按「段」设计

**证据链（全部已读代码，非推测）**

1. 切块粒度：`material_source.dart:996-1041` `chunkByWords`，调用方 `wordsPerChunk: 2500`（`material_import.dart:113,146`；`material_source.dart:752,1354`），Gutenberg 是 4000 词/块且「一章 ≤6000 词 = 1 块」（`material_source.dart:226-229,938-983`）；粘贴材料干脆整篇 1 块（`material_library.dart:295-298`）。
   → **典型外刊文章 = 1 块；公版书 = 每章 1 块（3000~6000 词）。**
2. 阅读器直接把这些块当 `_chunks`，并当成「段」：`_chunks = chunks`（:1171）、注释「段索引 → 中文译文」（:93-95）、`'第 ${at+1}/${_chunks.length} 段'`（:221）、`'已翻 x/${_chunks.length} 段'`（:547）。
3. 一次请求发整个块：`_translateOne` 里 `translateParagraphsRich(['${_chunks[index]['text']}'])`（:422-424）——入参是「1 段」，但这段最长 2500 词（≈15K 字符）/ Gutenberg 章可达 6000 词（≈35K 字符）。

**对应到用户的两个症状**

- 「进度永远是死的」：一篇文章 1 块 → `_runTotal = 1` → 进度条永远显示 **0/1（0%）**；请求跑完时 `_runTotal` 先被清零再 `setState`（:404-409），**100% 这一帧永远渲染不出来** → 条从 0% 直接消失。书有 67 块，但每块请求要几十秒到几分钟，分子一次 +1，用户几分钟看不到一次变化 → 同样是「死」。
- 「永远没法用」：模型对一整篇多段文本会按空行返回 N 段译文；调用方只声明 1 段 → N≠1 → 「抢救」只留第 1 段（`deepseek_api.dart:298-307`）→ 阅读器只取 `.first`（:428-434），而 `outcome.note` 被**丢弃**（非空时不显示）→ 用户看到的是「只有第一段被翻成中文，其余没动」，且没有任何提示。
- 长块（公版书章）另叠加 H3 的截断/超时。

**验证方法**：见 §4-V1/V2/V4。最快的一条：打开任意「今日推荐」文章，点翻译后看控制条文案——若显示「已完成 **0/1** 段」且文中只出现第一段的中文，即 H1 实锤。

---

### H2（≈75%，与 H1 叠加）：进度条 100% 永远不渲染 + 分母是块数 → 字面意义的「死」

- `material_reader_screen.dart:404-409`
  ```dart
  if (_activeJobs.isEmpty && _queue.isEmpty && _runTotal > 0) {
    _runTotal = 0; _runDone = 0; _runStartedAt = null;
  }
  setState(() {});
  ```
  最后一块完成的 `whenComplete`（:389-401）先 `_runDone++`，紧接着 `_pumpTranslationQueue()` 走进上面这段清零，再 `setState` —— **`done/total = 1/1` 从未被 build 过**。
- `_buildTranslationProgress` 只在 `_runTotal > 0` 时返回（:544-558），所以清零后进度条直接消失，回到状态行（:583-592）。
- 分母 = 本轮入队的**块数**（:374），与用户认知的「段」相差 1~2 个数量级；同时 detail 行用 `_translations.length / _chunks.length`（:547），和 `done/_runTotal` 是两套口径。
- `ProgressStageBar`（`widgets/waiting.dart:282-408`）本身没问题：value 变了会重绘、`startedAt` 有每秒 tick。问题只在喂给它的 done/total 永远只有 0 或不可见。

**这不是单纯观感问题**：用户能用来判断「是否在干活」的唯一信号就是这条 0% 的条。它不动，用户就点取消/退出 → 请求被 cancel → 永远看不到结果。

**验证方法**：1 块材料点翻译，观察条从 0% 到消失之间是否出现过任何 >0% 的帧；`flutter run` 下 `debugPrint('total=$_runTotal done=$_runDone')` 临时断点即可（本轮不允许改代码，留待修复时验证）。

---

### H3（≈65%，长材料必现）：单请求 = 整篇/整章 → 输出截断 / 180s 首字节超时 / 失败不可见

- 输出预算上限被写死 8192（`deepseek_api.dart:272-274`），而**副槽位走 DeepSeek 官方时，`buildChatBody` 会省略 `max_tokens`**（`base_api.dart:77-87`：`if (!official) 'max_tokens': maxTokens`）→ 请求预算由服务端默认决定，客户端完全失去控制。v2.10 那次「自适应 maxTokens」修复对用户最常见的配置（副槽位 = DeepSeek，`docs/research/input-ai.md:90-91`）**等于没修**。
- `BaseApiService.extractContentWithReasoning`（`base_api.dart:115-134`）**不看 `finish_reason`**：被 `length` 截断时它照样返回 content，随后 `_parseJsonResponse` 解析失败返回 `{}`（`deepseek_api.dart:369-383`，只 `debugPrint`），最终以「AI 没返回译文(可能被截断)」呈现（:296）。
- Dio 超时：`connect 60s / receive 180s`（`base_api.dart:21-31`）。非流式请求的首字节 = 整段翻译算完才发 → 一个 3000~6000 词的章翻译很容易 >180s → `DioException [receive timeout]`；阅读器只把它 `_humanError` 截断成 120 字符的**英文原始异常**（`material_reader_screen.dart:465-469`），没有走 `BaseApiService.friendlyError`（`base_api.dart:202-250`）。
- 提示词还要求「严谨 > 流畅」的长翻译纪律（`translation_policy.dart:22-44`）→ 单段输出更长、更容易触顶/超时。

**验证方法**：V2 观察错误文案；V3 看 logcat 的 `ReadFlow deepseek parse: 未找到 JSON(共 N 字)`（这是**现成的**可观测点，`deepseek_api.dart:372`）；V4 用短材料对照。

---

### H4（≈60%）：段数对不上时「静默抢救」——只显示第一段，用户以为功能坏了

- `deepseek_api.dart:298-307`：`list.length > paragraphs.length` 时 `sublist(0,1)`，返回 `note: '只翻好了前 1/1 段(可能被截断)'`。
- `material_reader_screen.dart:428-434`：只要 `translations` 非空就写 `_translations[index]` 并清错误，**never 展示 note**。
- 结果：整篇文章的列表项下面只出现第一段的中文，没有「还有内容没翻」的提示，也没有重试入口（该块被标记为成功，`_canTranslate` 不再排它，:344-351）→ 用户无法自救。
- 这条与 H1 同一个根（块≠段），但即使 H1 只做「拆段」不做「note 展示」，AI 少给一段时仍会静默错位——S 修法必须同时改。

**验证方法**：V2 里数「文中出现的中文段落数 vs 原文段落数」。

---

### H5（≈40%，解释「永远」而不是「这次」）：失败不自动重试 + 译文不落库 + 每次重来

- 译文只存内存：`_translations` 是 State 里的 `Map`，注释明说「译文只存内存…下次打开重翻即可」（`material_reader_screen.dart:93-95`）。退出阅读器再进 → 全清空。
- 失败块不会被「随读随翻」自动重试：`_canTranslate` 显式排除 `_chunkErrors`（:344-351，注释说怕烧额度）。对 1 块的文章 = 唯一那一块失败后，整个功能在本次会话里彻底废掉。
- 重新打开翻译（toggle 关掉再开）会 `_stopTranslation` 清队列，已失败块仍是失败态；用户点「重试」= 再发一次同样巨大的请求 → 同样失败。
- 于是「每次进来都失败 → 每次都要从 0 开始 → 永远没法用」。

**验证方法**：V5——短材料能翻、长材料永远失败时，H5 与 H3 同时成立。

---

### H6（≈30%，配置/UI 误导，非主因但要一起修）：翻译固定走副槽位，但阅读器的「模型」菜单改的是主槽位

- 翻译用 `DeepseekApiService`，槽位策略：**副槽位已配置 → 用副（DeepSeek）；未配置 → 回落主槽位（豆包/方舟）**（`deepseek_api.dart:29-36`；`api_endpoint.dart:59-68`）；`isConfigured` 只判「Key 是否非空」（`api_endpoint.dart:150`），**不校验模型/端点是否匹配**。
- 阅读器底部「模型」菜单写入的是 `keyDoubaoModel` / `keyDoubaoThinking`（`reader_action_bar.dart:402-409`，读的是 `ReaderActionBar.currentModel`）→ **用户在那儿换模型/思考档对翻译完全不生效**，但 UI 上没有任何提示 → 用户以为「试过很多次模型」其实没换。
- 若用户只配了主槽位：翻译走主槽位模型（默认 `doubao-seed-2-1-turbo-260628`，`constants.dart:9`）——能通，但同样受 H1/H3 的粒度问题拖累。
- 若用户把 DeepSeek key 填在**主槽位**且没填模型：`baseUrl` 会自动配成 `api.deepseek.com`（`api_endpoint.dart:107-121`）而 model 仍是豆包默认名 → 400/404 稳定失败（**未证实**，需 V6 验证）。
- 思考档位默认 `disabled`（`api_settings.dart:28,34`；`api_endpoint.dart:135-148`）：只是关闭推理（更快、更省），**不是**本次故障的原因；但它会随请求发送 `{'thinking': {'type': 'disabled'}}`（`api_endpoint.dart:218-220` → `buildChatBody:83-84`），若端点为 DeepSeek 官方且不认该字段，会走降级重试（`base_api.dart:95-109,140-170`）——降级判据只匹配错误文本里的 `1830102` / `invalid`+`parameter`（:173-197），**不匹配就一次都不重试**（未证实，列入 V6）。

---

### H7（≈10%，已排除为主因）：状态机 / mounted / 生命周期导致更新被丢弃

静态审查逐条排除：

- `mounted` 守卫（:382, :426, :457, :494）都是「已销毁就不写」，不会在页面存活时丢更新；
- epoch 机制（:114-122, :385-400）只在取消/重翻时丢弃旧结果，正常路径 `_runDone` 一定 +1；
- `Future.wait` 不存在；并发是自建队列 + `_translateConcurrency=2`（:119, :381-410），没有串行死锁可能；
- 状态变量都在 `State` 字段里，重建不会归零（只有 `_translations` 不落库，属 H5）；
- 唯一真 bug 是 H2 的「100% 帧被清零」和 H1 的分母口径，不是「更新丢失」。

唯一遗留疑点：如果 Dio 请求真的一直不返回（服务端不支持非流式长请求、连接黑洞），180s 后会超时，不会永久挂起——所以「永久」只能由 H1+H5 的组合解释。

---

## 3. 修复方案

### 3.1 最小改动（约 1 天，先让用户能「看见东西、能用」）

目标：**翻译单元 = 真段落**，其余架构不动。

1. **新增纯函数 `lib/services/reader_units.dart`**
   ```dart
   class ReaderUnit { final int chunkIndex, paraIndex; final String text; }
   List<ReaderUnit> splitUnits(List<Map<String,Object?>> chunks, {int maxChars = 600});
   // 按 \n\s*\n 拆段；单段 > maxChars 时按句号/空格二次切；丢弃空段；顺序保持
   ```
   在 `_load` 里生成 `_units`，并给每个 unit 挂 `GlobalKey`（复用现有 `_chunkKey` 思路）。
2. **改渲染**：`_buildChunk`（:2284-2328）从「整块一个 `TappablePassage`」改成「块内逐段 `TappablePassage` + 段下 `_buildTranslationArea(unitIndex)`」。这一步是用户能真正「逐段英中对照」的前提（也是 v2.6 起一直宣称但从未做到的功能）。
3. **改翻译目标与进度**：`_queue/_translations/_pendingChunks/_chunkErrors/_canceledChunks/_chunkJobEpoch` 的 key 从 chunk index 换成 **unit index**；`_runTotal` = 本轮 unit 数（典型文章 6~10，不再恒为 1）。`_translateNext/_translateChapter/_retryFailedChunks` 的目标选择函数同步换成 unit。`_visibleChunkIndices` 改成对 unit 的 RenderBox 求交（或先取可见 chunk 再展开成 unit —— 更省事）。
4. **请求**：`_translateOne` 一次只发 1 个 unit（≤600 字符）；`translateParagraphsRich` 的段数校验从「1」变成真实段数。
5. **进度不再被吞**：`_pumpTranslationQueue` 完成时先把 `_runDone = _runTotal` 渲染一帧（或保留 `_runFinished` 状态 2 秒再清），让用户看到 100%；建议把这套状态机抽成 `TranslationRunState`（见 §5）。
6. **失败必须可见**：`_translateOne` 里 `outcome.note` 非空时写入 `_chunkErrors[unit]` 或段下提示（例如「只翻出前半段，可重试后续」），不要静默取 `.first`。
7. **错误人话化**：`_humanError` 改调 `BaseApiService.friendlyError(e)`（顺手把「网络超时/鉴权失败/429」翻成中文）。
8. **加单请求超时**：`translateParagraphsRich` 传 `Options(receiveTimeout: 45s)`（或在 `postWithReasoningFallback` 增加 `timeout` 参数），超时立即标该段失败，而不是让用户干等 180s。

> 这一版做完，用户应该看到：一篇文章被拆成 6~10 段，进度条 0/8 → 1/8 → … → 100%，每段下面陆续出现中文，某段失败有「重试」。

### 3.2 根治（2~3 天）

1. **数据层纠正语义**：入库时按**自然段**落 `material_content`（或新增 `paragraphs` 表），chunk 仅作为「章/页」分组。这样翻译、阅读进度（`_lastChunkIndex`）、追问「第 N 段」、阅读位置、`chapters` 字段的语义全部对齐；材料中心「抓到正文 N 段」的文案也才对。
2. **翻译 API 改造**：① 显式传 `max_tokens`（含 DeepSeek 官方端点，或改用 JSON Output / `response_format` 参数——DS V4.1 支持）；② 检查 `finish_reason == 'length'` 并返回明确的「被截断」错误；③ 优先流式（SSE）逐段回填，进度=真实段数；④ 请求粒度 ≤2 段，杜绝整章一次发。
3. **译文落库**（可选但强烈建议）：`material_translations(material_id, unit_index, text, model, created_at)`；失败/重翻覆盖。这样「翻过一次就永久在」，也符合项目既有「标题译名落库」的教训（v2.10 发布说明第 2 条）。
4. **翻译诊断面板**：在「我的 → 诊断信息」里显示「翻译当前槽位/模型/baseUrl 主机/单段耗时/最近 3 条失败原因/finish_reason」，以后排障不用猜（本项目已有该页，`HANDOFF-2.5.md:300`）。
5. **翻译控制条显式标注走哪个槽位**（如「翻译使用：副槽位 · deepseek-flash」），并把阅读器「模型」菜单的语义改成「仅识图/追问」，消除 H6 的误导。
6. **复用而不是重写**：`material_blocks.dart` 的 `TranslateScope/planTranslation/estimateTranslationSeconds` 是上一轮留下的「范围+进度」纯函数，阅读器现在完全没用（只剩测试在测死代码）。新实现要么复用它（统一语义），要么连测试一起删——不要留「测试覆盖了、界面没用」的假象。

### 3.3 不建议重复的做法（前几轮已证明无效）

- 不要再只调「进度条文案/分母公式/分批大小/取消 token」——v2.9/v2.10/v2.12.2 都做过，用户实测仍「死」（`docs/TASK-BOARD-2026-10-04.md:27`、`docs/release-notes-v2.10.0.md:9-15`）。
- 不要再把「一本书 = 几十次请求」当性能问题（v2.8 的结论，`docs/release-notes-v2.8.0.md:97-99`）——真正的问题是**每次请求太大**，不是次数太多。
- 不要指望「换模型/开思考」能解决（H6：翻译链路根本不吃阅读器的模型菜单）。

---

## 4. 需要真机验证的点

> 按优先级排；每条写清「看什么 / 怎么拿」。

| # | 验证什么 | 具体做法 | 预期（若 H1/H2 成立） |
|---|---|---|---|
| V1 | 材料到底几块 | 打开任一「今日推荐」文章 / 一本公版书，记下打开过程时间线里的「**抓到正文:N 段**」（`material_import_flow.dart:183-186`）；或修复时临时 `debugPrint(_chunks.length)` | 文章 **N=1**；书 N=章数（几十） |
| V2 | 点翻译后的真实表现 | 观察：① 控制条文案是不是「**已完成 0/1 段**」；② 条有没有出现过 >0%；③ 文中出现了几段中文（原文几段）；④ 是否出现「这段没翻出来 / 最近一次:…」；⑤ 从 0% 到消失用了多久 | ① 0/1；② 从未；③ 1 段；④ 长材料有；⑤ 30s~180s |
| V3 | 是不是 JSON 被截断/非法 | `adb logcat -s flutter | findstr "deepseek parse"`，看 `ReadFlow deepseek parse: 未找到 JSON(共 N 字)`（`deepseek_api.dart:372`）；N 是模型返回长度 | 长材料反复出现该行 → H3 实锤 |
| V4 | 用短材料做对照 | 粘贴 2~3 个自然段的短文本 → 入库 → 阅读器点翻译 | 若短材料也「只翻第一段/进度 0/1」→ H1 与 API 无关；若短材料正常 → 更偏 H3 |
| V5 | 「永远」是不是因为每次重来 | 翻完/失败后退出阅读器再进，点翻译：是否要从 0 重来、失败段是否还是失败 | 是 → H5（无持久化+不自动重试） |
| V6 | 槽位/配置是否也在拖后腿 | 「我的 → 诊断信息」截图（Key 厂商与长度打码、baseUrl、模型）；分别试「只配主槽位 / 只配副槽位 / 都配」三组点翻译 | 若某组必 400/401 → H6；若三组都同样卡 → H1/H3 主因 |
| V7 | 是不是 180s 超时 | 长材料失败时看错误文案：`receive timeout` / `connectionError` / `API 返回错误` | timeout → H3 |

**给用户的最小信息请求**（也用于 Lead 转述）：
1. 最常复现的是哪类材料：今日精读（公版书）/ 今日推荐（外媒文章）/ 粘贴/导入的文件？
2. 点翻译后底部控制条的原话（是不是「已完成 0/1 段」）；
3. 有没有出现「这段没翻出来」以及「最近一次:」后面的原文；
4. 「我的 → 诊断信息」一页的截图（Key 只显示厂商+长度，可安全发）；
5. 如果方便：`adb logcat -s flutter` 里含 `deepseek parse` 的行。

---

## 5. 可测点与现有测试缺口

### 5.1 应抽成纯函数、可单测的落脚点

| 建议函数/类 | 现状 | 测什么（用例） |
|---|---|---|
| `splitUnits(chunks, {maxChars})` | 不存在；切段逻辑根本没有 | 2500 词块 → 真段数；无损 join 还原原文；超长段二次切不丢字；空段丢弃；chunk 映射正确 |
| `TranslationRunState`（enqueue / start / complete / fail / cancel → progress） | 现在散在 `_enqueueTranslation`+`_pumpTranslationQueue`+`_translateOne` 的 Flutter State 里，**不可测** | 1 个单元时进度必须经历 0→1（100% 可见）；N 个单元单调递增；取消后不再 +1；epoch 旧结果被丢弃；分母永远等于本轮单元数 |
| `parseTranslationJson(content, expectedCount)` | 私有在 `deepseek_api._parseJsonResponse` + 内联段数判断（:289-307） | 正常 / 围栏 / 前后说明文字 / 少 1 段 / 多 1 段 / 无闭合截断 / 空 → 各自的 `(translations, note)` |
| `nextTargets(currentVisible, translated, failed, cancelled, batch, chapterEnd)` | 内联在 `_translateNext`/`_translateChapter`/`_retryFailedChunks` | 当前屏翻完→取后 3；失败段不自动排；取消段不排；末尾边界；整章 20 段窗口 |
| `translationBudget(chars, cfg)` | 内联 `deepseek_api.dart:272-274` | clamp 1200/8192；**DeepSeek 官方也要给出预算（现在缺失）** |
| `friendlyErrorMessage(DioException)` | 已有 `BaseApiService.friendlyError`，阅读器没用（:465-469） | 直接用现成单测风格补 401/429/timeout 用例 |
| `estimateTranslationSeconds(unitCount)` | `material_blocks.dart:434-441`（按 ~2s/段 估，且阅读器不用） | 按真段落重估；与「约 X 分钟」文案一致 |

### 5.2 现有测试覆盖（grep 结果）

- **阅读器翻译：0 覆盖**。`grep test/ MaterialReaderScreen` 无命中；`test/` 里没有任何 `translateParagraphsRich` / 进度 / 取消的用例。
- `test/material_blocks_test.dart:292-437` 测的 `TranslateScope` / `planTranslation` / `translatePlanHint` / `bulkTranslateWarning` 是 **阅读器已不引用的死代码**（v2.12.2 删了自选范围）。「有测试」给了虚假安全感。
- `test/translation_policy_test.dart` 只测提示词常量（:15-59）；不测解析、不测进度。
- 例外：`test/doubao_parse_test.dart:57`、`test/follow_up_context_test.dart:68-109` 测的是识图全文翻译与追问上下文，与阅读器链路无关。

### 5.3 建议的最小测试集（与 3.1 一起交付）

1. `reader_units_test.dart`：`splitUnits` 6 个用例（对齐「无损/顺序/超长段/空段/映射」）。
2. `translation_run_state_test.dart`：进度可见性、取消、epoch、单单元 100%。
3. `translation_parse_test.dart`：`parseTranslationJson` 的 7 种返回形态。
4. 1 个 widget test：注入 fake `TranslationApi`，`MaterialReaderScreen` 用 1 块 3 段的假材料 → 点翻译 → pump → 断言出现 3 段中文、进度到达 100%。目前 `DeepseekApiService()` 在 `_translateOne` 里直接 new（:422），**不可注入**——修复时顺手改成构造函数注入接口。

---

## 附：本轮读过但未发现问题的环节（省下一轮重复排查）

- `ProgressStageBar`（`widgets/waiting.dart:282-408`）值/计时刷新正常，不是「死条」的原因；
- `_pumpTranslationQueue` 的并发/收尾逻辑没有死锁，`whenComplete` 一定触发；
- CancelToken 真的会中断请求（`base_api.dart:140-170` 透传 cancelToken），取消链条成立；
- `mounted`/epoch 守卫没有在页面存活时丢更新的路径；
- 阅读器 `dispose`（:945-966）会 cancel 在途请求，不会泄漏；
- 失败信息在 UI 上有位置（段末 + 控制条「最近一次」），但内容是**英文原始异常**且字号很小（:662-676），诊断性差。

*未证实项已单独标注（H6 的两个 400 场景、服务端默认 max_tokens 数值）；其余结论均可由列出的 file:line 直接复核。*
