# 「输入」模块 AI 能力侦察报告

- 侦察时间：2026-11-01（北京时间）
- 对象：ReadFlow v2.13.0+71，`D:\readflow`
- 边界：**只读不改代码**。本文件是唯一新增文件。
- 侦察员：ai-scout（AI 能力侦察）
- 外部信息源：DeepSeek 官方 API 文档（api-docs.deepseek.com），逐条给了链接；查不到的明确标注「未证实」。

---

## 0. 一句话判断（先给结论）

**现状**：输入模块的 AI 是「单轮文本生成 + 图片 OCR」，**没有工具调用、没有联网搜索、没有结构化输出**；"AI 找材料"实际是 **固定 7 个公开源 + 分类写死源列表 + 关键词检索**，AI 只负责把中文需求翻成英文检索词（且 3 条 query 只用了第 1 条），材料难度要抓回正文后本地算，检索阶段卡片上的 Lv 是按源类型猜的。

**最大的新杠杆**：DeepSeek 于 **2026-10-17 开放了官方 Search / Fetch 两个 REST API**（`/v1/tools/search`、`/v1/tools/fetch`，5 元/千次成功请求），并且 `deepseek-flash`（=V4.1-Flash-1017）支持 Tool Calls、JSON Output、1M 上下文、原生图像理解——**这四件事 App 现在一件都没用**。

**最该改的 3 处**：
1. `material_source.dart` + `original_search.dart`：从「固定源 + 分类硬编码」升级为「**检索计划器 → 多源并发 → 抓取后立即难度打分 → 结构化材料卡**」，并接入官方 Search/Fetch 作为"长尾源"兜底。
2. `deepseek_api.dart planMaterialSearch`：从「一次性吐 JSON 文本、只取 queries.first」升级为「**Tool Calls 闭环（search→fetch→打分）+ JSON Output 强制结构化**」，把画像/偏好从"一句话 hint"升级为结构化入参。
3. `learner_model.dart` + `material_prefs.dart`：补齐**考试目标/期限/语法薄弱点/单篇时长/形态偏好**，并把公开源检索结果也纳入黑名单过滤，让"个性化"从"用户填表"变成"检索→阅读→反馈"闭环。

---

## 1. 外部调研结论（DeepSeek 官方，2026-11-01）

> 所有规格均来自官方文档页面；带「未证实」的是本次没查到官方原文的推断。

### 1.1 模型阵容：有 "v4.1 / flash / 1017"

| 项 | 结论 | 出处 |
|---|---|---|
| 当前 API 模型名 | **`deepseek-flash`** = DeepSeek-**V4.1-Flash-1017**（2026-10-17 上线）；**`deepseek-v4-pro`** = DeepSeek-V4-Pro-0813（仍可调用） | [模型 & 价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/) |
| 旧名兼容 | `deepseek-v4-flash`、`deepseek-v4-flash-vision-exp` 仍可调用但已路由到 V4.1-Flash（按 Flash 价计费） | 同上 |
| 更早旧名 | `deepseek-chat` / `deepseek-reasoner` 已于 2026-07-24 停止 | [Change Log 2026-04-24](https://api-docs.deepseek.com/updates) |
| 上下文长度 | **1M** | 模型 & 价格页 |
| 最大输出 | **384K** | 模型 & 价格页 |
| 并发限制 | flash 2500，pro 500 | 模型 & 价格页 |
| 价格（元/百万 token，空闲/高峰） | flash：缓存命中 0.02/0.04；未命中输入 1/2；输出 4/8。pro：0.15/0.30；4.5/9；13.5/27 | 模型 & 价格页 |
| 高峰时段 | 北京时间周一至周五 9:00-12:00、14:00-18:00（中国法定节假日除外），其余为空闲 | 模型 & 价格页 |
| 思考档位 | 支持「思考模式开关」：`{"thinking":{"type":"enabled/disabled"}}`；支持强度 `reasoning_effort: low/high/max`（默认开思考、默认 effort=high）。对外枚举映射：minimal→low、medium→high、xhigh→high、ultra→max | [思考模式](https://api-docs.deepseek.com/zh-cn/guides/thinking_mode) |
| 思考模式限制 | 不支持 `temperature`/`presence_penalty`/`frequency_penalty`（传了不报错但不生效）；flash 的 `top_p` 仅在思考模式下生效且取值 0.95–1.0 | 同上 |
| 多模态 | flash **支持图像理解**（原生多模态）；V4-Pro **不支持**图像理解 | [图像理解](https://api-docs.deepseek.com/zh-cn/guides/vision)、模型 & 价格页 |
| 其它能力 | JSON Output、Tool Calls、Responses API、Anthropic API、对话前缀续写(Beta)；FIM(Beta) 仅非思考模式 | 模型 & 价格页、各 Guide |

**关于"1017 这一代着重增强抓资源能力"**：官方 10-17 新闻里能证实的只有两点——①**首次开放自研搜索 API**（Search/Fetch）；②agentic benchmark 提升（HLE w/tools 63.9，Chartography w/tools 78.9→83.0、BabyVision w/tools 92.5、ZeroBench-main w/tools 51.0）。**官方原文没有"专门增强抓取/爬取资源"这样的表述 → 该说法未证实**；等价、可依据的事实是「官方把搜索与抓取做成了可计费的 API」。
（来源：[V4.1-Flash-1017 发布](https://api-docs.deepseek.com/zh-cn/news/news261017/)、[Change Log](https://api-docs.deepseek.com/updates)）

### 1.2 四项能力逐个确认

**① Function Calling / Tool Use：支持。**
- OpenAI 兼容 `tools`（`type:"function"` + JSON Schema），模型返回 `tool_calls`，由**客户端执行**后以 `role:"tool"` 回传（模型自己不执行）。
- 思考模式下带 `tools` 时，历史轮次的 `reasoning_content` **必须回传**，否则 400。
- `strict` 模式（Beta）：需 `base_url="https://api.deepseek.com/beta"`，所有 function 设 `strict:true`，object 需 `required` 全列 + `additionalProperties:false`；支持 object/string/number/integer/boolean/array/enum/anyOf。
- Chat Completions 接口**不支持**在对话历史中间插入工具调用消息（要插只能走 Anthropic/Responses API）。
（来源：[Tool Calls](https://api-docs.deepseek.com/zh-cn/guides/tool_calls)）

**② JSON 结构化输出：支持。**
- `response_format:{"type":"json_object"}`；要求 prompt 里必须出现 "json" 字样并给样例；需自己控制 `max_tokens` 防截断；**非 JSON 内容会被替换成空格**，可能导致 content 全空。
（来源：[JSON Output](https://api-docs.deepseek.com/zh-cn/guides/json_mode)）

**③ 联网搜索：官方开放了独立 Search / Fetch API（不是"聊天里自动联网"）。**
| API | Endpoint | 参数 / 返回 | 价格 | QPS |
|---|---|---|---|---|
| Search | `POST https://api.deepseek.com/v1/tools/search` | `query`(1-128 字，支持 `site:`/`-site:`/`"短语"`/`lang:`/`after:`/`before:`)、`count`(1-50，默认 10)、`ori_question`、`localization`、`need_content`；返回 `results[]`，含 `rerank_score`(0-3，≥1.5 优质)、`title`、`url`、`snippet`、`summary`(600-800字，给模型读)、`content`(正文，需 need_content=true)、`site_name`、`date`、`authority`(0-4，≥3 极权威) | 5 元/1000 次成功请求 | 100 |
| Fetch | `POST https://api.deepseek.com/v1/tools/fetch` | `url`(≤8192 字符，需含 host 的 http/https) → `{title, content(Markdown)}`；404=抓不到/被站方拦，403=安全策略拒绝 | 5 元/1000 次成功请求 | 25（还按目标域名单独限速） |

- 计费口径：**只有 HTTP 200 且真的返回结果才计费**；失败/无结果/超时不计费。`count` 不影响单价。
- 原"免费"窗口（Harness/Claude Code/Codex 内调用）已于 **北京时间 2026-11-01 00:00 结束，开始按次收费**——即今天起没有免费额度。
（来源：[网页搜索与抓取](https://api-docs.deepseek.com/zh-cn/guides/search)、[模型 & 价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)）

**④ 文件 / 长文 / 多模态：**
- **长文**：直接走 messages 上下文（1M），**没有**"文本文件上传解析"能力。
- **Files API**：只支持上传**图片**（JPEG/PNG/GIF/WebP），`purpose` 必须为 `user_data`，单文件 ≤64MiB，可设 1 小时–30 天有效期；对话里用 `{"type":"file","file_id":"file-api-..."}` 引用。**不能传 PDF/DOCX/TXT**。
- **图像输入**：三种方式（base64 data URL / 外部 http(s) URL / Files API file_id）；`detail` 可选 low/high/original/auto；单图 ≤32MiB（内联/URL）、≤64MiB（file_id），请求体 ≤48MiB，单请求最多 600 张图；每张图 token 上限约 1024；**图片只能出现在 user 消息**。
（来源：[图像理解](https://api-docs.deepseek.com/zh-cn/guides/vision)、[Files API](https://api-docs.deepseek.com/zh-cn/guides/files_api)）

### 1.3 官方对"抓取/检索"的推荐用法
官方口径就是 **Search 拿到候选 → Fetch 抓正文 → 交给模型读**（"Search 接口和 Fetch 接口为 Agent 与 RAG 应用提供实时网页内容"）。这正好对应 App 里已有的「检索 → 抓正文 → 本地难度分析」链路，只是现在检索端是自建公开源、抓取端是自写正则抽取。**官方没有提供"托管式网页爬取"以外的浏览器渲染/反爬能力**；Fetch 明确"受目标站点可用性与访问策略影响"，且 403/404 是常态。

> 对 App 的直接含义：这是一条**用户自带 Key（BYOK）即可在客户端直连**的官方链路，成本约 `5元/1000次`。一次"AI 找材料"= 1 次 search + 3~5 次 fetch ≈ **0.02~0.03 元**，比走模型 token 更可预测。

---

## 2. 现有 AI 调用架构（站内审计）

### 2.1 槽位与模型

| 槽位 | 默认端点 | 默认模型 | 谁在用 |
|---|---|---|---|
| 主槽位 primary | `https://ark.cn-beijing.volces.com/api/v3`（火山方舟） | `doubao-seed-2-1-turbo-260628` | 识图/拍照取词、OCR、追问、写译批改、**AI 材料推荐（旧链路）** |
| 副槽位 secondary（未配置则回落主槽位） | `https://api.deepseek.com` | **`deepseek-flash`** | 文章生成、检索规划、标题中文化、逐段翻译、回译练习 |

- 槽位定义：`lib/services/api_endpoint.dart:50-68`；"是否 DeepSeek 官方"判定（baseUrl + 模型名双条件）：`api_endpoint.dart:23-29`；Key 前缀（`sk-`→DeepSeek）自动配端点：`api_endpoint.dart:107-121`。
- 模型常量：`lib/config/constants.dart:15-16`（`deepseekBaseUrl` / `deepseekChatModel='deepseek-flash'`）；内置兜底模型清单 `constants.dart:23-42`（含 `deepseek-v4-pro`、`deepseek-flash`）；`GET /models` 动态拉取：`lib/services/doubao_api.dart:1446-1519`。

### 2.2 请求构造与"思考"参数

- 统一构造：`BaseApiService.buildChatBody`（`lib/services/base_api.dart:68-88`）。**对 DeepSeek 官方端点会省略 `max_tokens` 与 `temperature`**（v1.9.0 修：max_tokens 是 reasoning+content 总预算，写死会被思考吃光），其它端点显式给；`stream_options.include_usage` 只在官方 + 流式时发。
- 思考参数：`ApiEndpointConfig.buildThinkingParamsFor`（`api_endpoint.dart:174-221`）→ `{thinking:{type}, reasoning_effort}`。档位表：`constants.dart:90-95`（DS 官方 disabled/low/high/max，**无 medium**；豆包系 2 档 `constants.dart:81-84`）。
- **默认档位是 `disabled`**（`api_endpoint.dart:135-148` 的 fallback）；识图**固定 low**（`doubao_api.dart:307-310`）、整页 OCR **固定 low**（`doubao_api.dart:374-375`）、词义解释**固定 disabled**（`doubao_api.dart:425`）。也就是说：**用户不手动改设置，"AI 找材料/翻译/生成"全部跑在不思考模式**，`max` 档从未在材料链路上使用。
- 降级重试：`postWithReasoningFallback`（`base_api.dart:140-170`）只在参数不兼容类 4xx 时**重试 1 次**并同时去掉 `reasoning_effort`、关闭 `thinking`（`degradeOnce`，`base_api.dart:95-109`）。
- 取正文兜底：正文空时从 `reasoning_content` 取（`base_api.dart:115-134`）。
- 超时：连接 60s / 接收 180s / 发送 60s（`base_api.dart:21-31`）；材料抓取 20s（大文件 90s，`material_source.dart:216-220`）。

### 2.3 能力边界：纯文本 + 图片，**没有工具调用、没有联网搜索、没有 JSON mode**

| 能力 | 现状 | 证据 |
|---|---|---|
| Tool / Function Calling | **无**。全库没有 `tools` / `tool_choice` 请求参数；唯一出现 `tool_calls` 的是旧表字段 | grep 全 `lib/`：仅 `lib/services/database.dart:459`（建表列）与 `:2545`（写库） |
| 联网搜索 | **LLM 不联网**；所有网络抓取都由 App 自己发（Dio 直连公开源） | `material_source.dart:206-253`、`original_search.dart:156-277` |
| JSON 结构化输出 | **无 `response_format`**；靠"提示词要求返回 JSON + 从文本里抠 JSON" | `deepseek_api.dart:369-383`（`_parseJsonResponse`）、`doubao_api.dart:1384+`（`extractJsonBlock`） |
| 模型流式 | 有（追问/推荐/OCR/整页提取），SSE 自解析 | `doubao_api.dart:576+`（`parseSseStream`）、`:1033-1063`（`streamPrompt`） |
| 图片输入 | 有（识图 + 图片导入提取全文） | `doubao_api.dart:204-296`、`:343-399` |
| 长文输入 | 只受上下文限制；没有文件解析（PDF/EPUB/DOCX 明确拒绝） | `material_import.dart:37-39` |

### 2.4 提示词模板与请求方法清单（全部散在 service 层，无集中注册表）

| 任务 | 提示词位置 | 请求方法 | 输出结构 | 备注 |
|---|---|---|---|---|
| 拍照取词（默认） | `doubao_api.dart:245-294` | `extractVocabularyStream`（`:461`） | JSON（items） | 逐行扫+下划线专项+对账 `mark_count` |
| 校准重识别 | `doubao_api.dart:216-244` | 同上（`calibrate:true`） | JSON | "宁可多收 + uncertain 标" |
| 图片全文翻译 | `doubao_api.dart:206-211` | 同上（`analysisModeFullText`） | JSON（paragraphs） | |
| 整页 OCR | `doubao_api.dart:355-364` | `extractFullTextStream`（`:343-399`） | 纯文本 | 不翻译/不改写/丢页眉 |
| 单词语境解释 | `doubao_api.dart:429-436` | `explainWord`（`:406-452`） | 纯文本流式 | 150 字内 |
| 追问 | `doubao_api.dart:1096-1102` | `followUpStream`（`:1073+`） | 纯文本流式 | 材料上下文进 system，历史 20 条 |
| 写译批改 | `doubao_api.dart:929-940` + 用户可改默认提示词 `writing_review_settings.dart:29-30` | `reviewWriting`（`:837+`） | JSON | 唯一"用户可自定义提示词"的链路 |
| AI 推荐清单 | `material_recommend_service.dart:58-67`、`:74-96` | `streamPrompt`（`doubao_api.dart:1033`） | JSON（items） | **走主槽位（方舟）**，用旧画像 |
| AI 精读内容 | `material_recommend_service.dart:103-116`、`:119-135` | 同上 | Markdown | |
| 检索规划 | `deepseek_api.dart:143-161` | `postWithReasoningFallback`（非流式） | JSON（queries/picks/note） | **本次重点** |
| 标题中文化 | `deepseek_api.dart:202-208` | 同上 | JSON（items） | 逐批 ≤20 条 |
| 逐段翻译 | `deepseek_api.dart:263-271` | `translateParagraphsRich`（`:252-309`） | JSON（translations） | 段数对齐，可取消，预算按字数自适应 |
| 生词文章生成 | `deepseek_api.dart:59-72` | `generateArticle`（`:41-104`） | JSON（title/content/translation） | 入口 `article_provider.dart:54-98` |
| 回译练习 | `deepseek_api.dart:320-330` | `generateBackTranslationExercise`（`:314-361`） | JSON（sentences） | |
| 私人导师 | `tutor_chat_screen.dart:439-449` + 证据包 `tutor_engine.dart:488-528` | `followUpStream` | 纯文本流式 | 本地诊断 `tutor_engine.dart:200/384` 先出结论，AI 只解释 |

**结论（Q1）**：App 的 AI 能力 = **纯文本生成 + 图片理解**，没有任何工具调用/联网/结构化输出。提示词是好东西（大量 v2.x 迭代的细节纪律、翻译纪律 `translation_policy.dart`），但**架构上是"每次调用一段自制 prompt + 从文本里抠 JSON"**，不是 agent 架构。

### 2.5 材料到底是怎么"找"的（三层，AI 只在最上面一层）

```
用户中文需求
   │  ┌─────────────── ① AI 规划（可选，deepseek_api.dart:119-194）───────────────┐
   ├──┤ 输入：需求 + 分类 + "基线一句话"(LearnerContext.describeBaseline) + 偏好串    │
   │  │ 输出：{"queries":[≤3 条英文词], "picks":[≤6 部作品+链接], "note"}          │
   │  └──────────────────────────────────────────────────────────────────────────┘
   │  ⚠️ 只用 queries.first（category_material_screen.dart:142-149），其余 2 条丢弃
   │  ⚠️ picks 只做展示 + 单条抓取（:580-709、:295-347），**不参与检索**
   ▼
② 真实检索（original_search.dart:156-277）
   - 分类 → 源写死：书籍/教材→gutenberg；论文→arxiv；外刊/碎片→npr/bbc_le/voa_le/ted（:134-139）
   - 多源并行 + 每源 12s 超时（:197-250）；6 小时内失败过的源直接跳过（:425-433）
   - RSS 源没有检索接口 → 拉最新 30 条 + 本地关键词过滤（:375-421）
   - 中文关键词直接提示"这些源只认英文"（:182-186）
   ▼
③ 抓取 + 入库（material_source.dart → material_library.dart）
   - Gutenberg 全文 TXT（:837-885）、Wikipedia REST（:1094-1151）、arXiv 摘要页（:1248-1311）、
     通用网页 readableText（:1341-1355）→ 切块（:996/938）→ 入库去重（material_library.dart:211-261）
   - **难度只在这一步算**：LearnerContext.knownWords → TextDifficulty.analyze（material_library.dart:164-193）
```

**AI 参与选源吗？不参与。** 源由「分类」+「偏好里的 kinds 与分类源求交集」决定（`original_search.dart:167-177`）。AI 唯一的影响力是"给英文检索词"和"点名作品"。
**检索阶段的难度可信吗？不可信。** 卡片上的 `Lv` 是 `MaterialLevel.fallbackForKind(kind)`（`lib/widgets/material_cover.dart:1038-1045`，按源类型给 5~9），全部结果都同款；唯一"检索前先抓正文算真实难度"的地方是「今日精读」那一张卡（`material_center_screen.dart:174-210`）。

**输入模块的 AI 入口全景**（`lib/screens/input/`）：
- 首页 `input_home.dart:74-116`：上传材料（拍照/相册/链接导入）→ 材料中心 → AI 文章 → 导入材料 → 我的材料。
- 材料中心 `material_center_screen.dart`：我的需求（`:987-1057`）→ 分类网格（`:1060-1123`）→ 今日精读/材料库/书架/发现。
- 分类二级页 `material_category_screen.dart`：题材 → `topic.queries.take(2)` 双 query 检索（`:59-96`）。
- 「按你的水平找材料」`category_material_screen.dart`：两个 Tab ——「资料原文」（走上面 ①→③）、「AI 整理编写」（旧推荐链路）。
- AI 推荐 `ai_material_search.dart`：**用主槽位（方舟）+ 旧 `LearnerProfile`**（`:39`、`:55`、`:79`），与 v2.0 的 `LearnerModel` 是两套画像；结果标注「AI 编写」（`:508-526`），黑名单本地过滤（`:206-221`、`:293-297`）。

---

## 3. 材料获取链路细节（现有源与可达性）

| 源 id | 形态 | 访问方式 | 大陆实测可达性 |
|---|---|---|---|
| `npr` | 新闻 RSS | `feeds.npr.org/1001/rss.xml` | ✅ 可达（默认源，`material_source.dart:346`） |
| `arxiv` | 论文摘要 | 官方 API `export.arxiv.org/api/query`（Atom）+ 摘要页解析 | ✅ 可达（约 0.9s） |
| `gutenberg` | 公版书全文 | 站内检索页 HTML + `pg<id>.txt` | ✅ 可达（首包慢，单独 90s 超时） |
| `bbc_le` | 播客 RSS | `feeds.bbci.co.uk/...rss.xml` | ❌ 实测超时 |
| `voa_le` | 播客 RSS | VOA 自研 `/api/...`（TODO 未验证） | ❌ 实测超时 |
| `ted` | 播客 RSS | feedburner | ❌ 实测超时 |
| `wikipedia` | 百科 | REST API | ❌ 实测超时 |

- 源清单与许可：`material_source.dart:261-328`（每个源都带 license，界面展示）；实测可达集合 `:353`；默认源 `:346`；"不可达不是代码问题"的说明 `:22-27`、`:258-260`。
- 源可用性记忆：`lib/services/material_source_status.dart:68-173`（记录 ok/时间/原因；下次默认落到上次成功的源；"检测可用源"按钮 `material_center_screen.dart:466-491`）。
- 合规边界（写在文件头）：只抓公开可访问内容，不绕登录墙/付费墙/验证码/robots，不伪造身份与 IP 轮换，面向个人学习（`material_source.dart:8-13`）。
- 抓取能力上限：**不跑无头浏览器**、不解析 PDF/EPUB、arXiv 只取摘要页不下载 PDF（`material_source.dart:21-29`）；导入侧明确拒绝 pdf/epub/mobi/doc/docx/ppt/xlsx 并说明原因（`material_import.dart:37-39`）。
- 技术栈事实：`pubspec.yaml:11-58` **没有** webview / html 解析库 / RSS 库 —— `html_text.dart`、`feed_parser.dart` 都是自写；加新依赖有历史教训（`pubspec.yaml:52-58` 注释：`file_picker` 两版都构建不过）。

---

## 4. 大陆网络下「AI 抓资源」的现实可行形态

> 前提：客户端 Flutter App + 用户自带 API Key（App 已是 BYOK 模式，`api_endpoint.dart:102-126`）。评判标准：**抓到的必须是真内容，抓不到就明说，不许让模型"回忆"出资源**。

### 4.1 真能做（可靠、合法、可落地）

1. **DeepSeek 官方 Search / Fetch API**（2026-10-17 起开放）：`/v1/tools/search` 拿真实网页候选 + `rerank_score/authority/date`，`/v1/tools/fetch` 拿 Markdown 正文。同域名、同一把 Key、按次 5 元/千次，**这是本次最大的新能力**。风险：失败/403/404 常态，需超时与降级。
2. **现有三类公开源**（已实测可达）：Project Gutenberg（公版书全文，站内检索页可解析）、arXiv 官方 API（Atom）、NPR RSS。Wikipedia REST 已有实现但大陆不可达（可保留，按可用性记忆自动跳过）。
3. **公开网页静态解析**：现有 `HtmlText.readableText` 已能抽正文/og:image/标题；适合新闻站点、机构官网、博客。
4. **文件/图片导入 + AI 提取**：`material_import.dart` + `extractFullTextStream` 已具备（图片 → 文本 → 材料）。
5. **长文一次投喂**：1M 上下文意味着"整本书/整套试卷一次丢给模型做结构化"技术上成立（成本另算）。
6. **官方开放样题**：四六级/雅思/托福/GRE 的官方样题页面原则上可抓（**但"能否稳定抓取、是否允许再分发"需要逐站核实，本次未验证 → 未证实**）。这是最贴合"备考→找材料"的公开合法源。
7. **多模态**：`deepseek-flash` 原生图像理解 + `detail:low` 省钱；可把"拍照→材料"做到"整页结构化"。

### 4.2 勉强能做（能用但质量不稳，必须给用户看"为什么失败"）

1. **RSS 无检索接口** → 只能"拉最新 N 条 + 本地关键词过滤"（现有实现，`original_search.dart:375-421`）：覆盖面窄，热点先到先得。
2. **通用网页正文抽取** → 版面改版即失效（现有已知局限 `material_source.dart:21-29`）；无法处理 JS 渲染页（SPA/站内搜索页很多属于此类）。
3. **AI "点名作品 + 自己给链接"** → 靠提示词纪律压制幻觉（`deepseek_api.dart:150-161` 已做得很细：只允许 Gutenberg `/ebooks/<id>`、arXiv `/abs/<id>`、机构官网，不确定就留空）；**但仍可能给出 404 链接**，必须"链接可点击验证"而不是当检索结果。
4. **第三方搜索 API（Bing/Tavily/Serper/博查等）** → 需要另注册 Key、另计费，大陆可达性与合规性**未证实**；且会引入第二套 Key 管理。
5. **难度打分前置** → 现有本地分析（词频表 + 覆盖度）是靠谱的，但**每篇都要先抓正文**，意味着检索要从"10 条结果"缩到"3~5 条"才能控时延与成本。

### 4.3 做不了（硬做就会变成幻觉/事故）

1. **让模型直接"列出有哪些资源"并当结果展示** → 无检索锚定，编书名/编 id/编链接（现有 `picks` 已踩过这个坑，靠"不确定就留空"缓解）。
2. **浏览器渲染 / 反爬对抗 / 绕登录墙付费墙验证码** → 客户端 App 做这个既违规又脆弱；官方 Fetch 也明确会 403/404。
3. **实时全网全文搜索** → 只能通过 Search API；没有免费无限抓取这回事。
4. **PDF/EPUB/DOCX 解析** → 现有代码明确拒绝（`material_import.dart:37-39`）；要做得新引解析库（构建风险见 `pubspec.yaml:52-58`）。
5. **付费墙内容**（NYT/Economist 等）→ 不做，现有源已避开。
6. **音频转写（ASR）** → 没有；只有 TTS 播放。

### 4.4 五个最有价值的具体能力点（按性价比排序）

| # | 能力点 | 形态 | 现状差距 |
|---|---|---|---|
| 1 | **目标 → 检索计划 → 多源并发 → 难度打分 → 结构化材料卡** | 一次调用产出"检索计划 JSON"（多 query + 目标源 + 难度/篇幅约束），App 并发跑 Search/公开源，抓回正文后**马上本地算 i+1 覆盖度**，再让模型只做"卡片化/中文标题/推荐理由" | 现在 query 只用第 1 条、picks 不参与检索、检索阶段 Lv 是猜的 |
| 2 | **用官方 Search/Fetch 补"长尾源"** | 公开源没有的题材（如"某篇 2026 年的气候报道"）走 `/v1/tools/search` + `/v1/tools/fetch`，结果必须带 `url/authority/date` 并标注"来源：DeepSeek 搜索" | 完全未接入（grep 无 `/v1/tools/`） |
| 3 | **考试/目标材料源摸底** | 把 goals（四六级/雅思/托福）与"官方公开样题"源打通，形成"备考材料包" | `goals` 字段**从未被写入**（见 §5），材料检索零考试维度 |
| 4 | **可审计的检索 agent（Tool Calls）** | 模型发 `search(query)` → App 调 `/v1/tools/search` → 回传 → 模型决定 fetch 哪几条 → App 调 `/v1/tools/fetch` → 回传 → 模型出卡片；**每一步都显示**（现有 `SearchEvent` UI 已是雏形：`original_search.dart:54-100`） | 现在是一次性"AI 出 query、代码去搜"，模型看不到检索结果 |
| 5 | **JSON Output + 1M 上下文做"整篇试卷/整本材料"结构化** | `response_format:json_object` 强制结构，一次吃下整份材料出大纲/难度/生词/题目；输出上限 384K | 现在靠 `extractJsonBlock` 抠文本，失败率与截断风险靠兜底 |

---

## 5. 个性化：现状、实际生效情况、缺什么

### 5.1 两套画像并存（架构债）

| 画像 | 存储 | 谁在用 | 谁负责写 |
|---|---|---|---|
| 旧 `LearnerProfile`（level/goal/interests/note） | Hive `learner_profile`（`learner_profile_store.dart:9`） | **只有 AI 推荐旧链路**（`ai_material_search.dart:55,79`；`material_recommend_service.dart:74-96`） | `learner_profile_screen.dart:54` |
| 新 `LearnerModel`（v2.0，带来源/置信度） | Hive `learner_model_v2`（`learner_model_store.dart:16`） | 材料检索、导师、练题、复习、周报、小组件 | 词汇量测试/导师面谈/偏好页/练题页 |

两套数据**不互通**：用户在「学习画像」填的水平/兴趣，材料检索的「按你的水平找材料」读不到；用户在导师面谈填的目标，AI 推荐读不到。

### 5.2 LearnerModel 字段清单 × 实际用途

`lib/models/learner_model.dart:91-132`：

| 字段 | 写入方 | 用于检索/选材？ | 用于生成？ | 判定 |
|---|---|---|---|---|
| `vocabEstimate` + `vocabLow/High` | 词汇量测试（`learner_model_store.dart:82-113`） | ❌ 不直接；只以「基线一句话」进检索提示词（`category_material_screen.dart:138` → `deepseek_api.dart:132-134`） | ✅ 难度分析 knownWords（`learner_context.dart:65-90`） | **半生效**：算难度用了，检索没用 |
| `cefr` | 测试/自报 | ❌ | ✅ 导师上下文（`tutor_engine.dart:534`）、`summaryText` | **半生效** |
| `goal` | 导师面谈（`tutor_interview_screen.dart:133-141`，自由文本） | ❌ | ✅ 导师 | 材料检索零使用 |
| `goals`（多选考试目标，`learner_model.dart:113`） | **无人写入**（全库无 `copyWith(goals:...)`/store 参数） | ❌ | 只被输出模块读（`output_home.dart:173`、`drill_plan_screen.dart:32,363`、`drill_screen.dart:338-340`） | **死数据** |
| `dailyMinutes` | 偏好页/面谈/导师页 | ❌ | ✅ 复习配额、导师派任务、周报 | 材料"单篇时长"没用它 |
| `maxNewWords` | 偏好页/导师页 | ❌ | ✅ 复习队列 | 与输入无关 |
| `interests` | 导师面谈（`tutor_interview_screen.dart:150-157`） | ❌（材料检索用 `MaterialPrefs.genres`） | ✅ 导师上下文 | **两套兴趣各存一份** |
| `blockedTopics` / `blockedKeywords` | 偏好页/面谈 | ❌ **公开源检索结果不过滤**（`material_center_screen.dart` 全文件无 blocked 引用） | ✅ AI 推荐过滤（`ai_material_search.dart:206-221,293-297`）+ 导师提示词 | 覆盖不全 |
| `extras['vocab_inferred']` | **无人写入**（只读：`learner_context.dart:30`、`drill_planner.dart:489-490`） | ❌ | ❌ | **死字段** |
| `extras['reading_wpm']` | **无人写入**（只读：`learner_context.dart:94`） | ❌ | 影响 estMinutes（永远用默认 200） | **死字段** |
| `extras['interview_at'/'last_placement'/'drill_level_note']` | 面谈/测试/练题 | ❌ | 局部 UI | 有写入但只做标记用 |

### 5.3 MaterialPrefs 字段清单 × 实际生效情况

`lib/services/material_prefs.dart`（Hive key：`constants.dart:160`）：

| 字段 | 界面 | 真实去向 | 判定 |
|---|---|---|---|
| `band`（i+1 / i+10 / i+100 / 不限） | 我的需求弹层（`material_center_screen.dart:629-647`） | ① AI 提示词 `bandHint`（`category_material_screen.dart:140`）；② 材料库排序/过滤（`material_library.dart:410-434`）；③ 首页"只看符合"过滤（`material_center_screen.dart:779-784`） | **当前唯一真正影响"找材料"的字段之一** |
| `kinds`（公版书/论文/外刊/播客/百科） | 同上（`:681-703`） | **收窄检索源**（`original_search.dart:167-177`）+ `preferredSources`（`material_prefs.dart:270-278`） | **真生效** |
| `contentTypes`（新闻/评论/科普/文学/…10 类，带英文检索词） | 同上（`:651-679`） | **只进 AI 提示词**（`hintForAi`，`material_prefs.dart:291-294`）；不参与真实检索条件 | 半生效（取决于 AI 是否被触发） |
| `genres`（题材自由文本） | 同上（`:705-714`） | 只进 AI 提示词（`hintForAi:295`） | 半生效 |
| `extra`（补充需求自由文本） | 同上（`:716-727`） | 只进 AI 提示词（`hintForAi:296`） | 半生效 |

**关键触发条件**：AI 检索规划只在「输入是中文 / 输入为空 / 有任意偏好」时才跑（`category_material_screen.dart:129`）；**用户用英文关键词搜且没设偏好时，AI 完全不参与**，纯关键词直搜。而一旦 AI 规划成功，**只有第一条 query 被用于检索**（`:142-149`）。

### 5.4 缺口清单（个性化闭环需要什么）

| 维度 | 现有 | 还缺 |
|---|---|---|
| 目标/考试 | `goal`（自由文本）、`goals`（死字段） | 结构化 `exam`（CET4/6、IELTS、TOEFL…）+ 目标分 + 期限；真正写入并进检索 |
| 兴趣/题材 | `interests`（导师）、`MaterialPrefs.genres`（材料） | 合并成一套；由"点击/读完/放弃"反馈自动更新 |
| 词汇量 | `vocabEstimate` + 区间 + 置信度（测出来的） | 把"已知词集合"结构化为检索约束（而不只是一句描述） |
| 语法薄弱点 | 无（`extras` 是预留位，无人写） | 结构化 `grammarWeak[]`（时态/从句/非谓语…）+ 来源/置信度，接写译批改错误标签 |
| 可投入时间 | `dailyMinutes` | **单篇材料时长偏好**（5/10/20 分钟）、每周次数、难度递进策略（i+1 占比） |
| 材料形态 | `kinds`、`contentTypes` | 音频/字幕偏好、语言变体（英/美）、体裁长度、是否接受 AI 改写 |
| 阅读能力 | `wpm` 字段存在但**无人写入** | 从阅读行为自动推断并写回（真正的 `inferred`） |
| 反馈闭环 | 无（推荐/检索不记点击、不记读完率） | 检索→打开→读完/放弃→回写偏好；否则个性化永远靠用户手填 |

---

## 6. 改造点（新一代模型能力提升后，最该动的 3 处）

### 改造点 1：把"检索"从『固定源 + 关键词』换成『计划 → 并发抓取 → 难度打分』（改动最大、收益最高）

- **文件**：`lib/services/original_search.dart:134-139`（分类→源写死）、`lib/screens/input/category_material_screen.dart:129-173`（只取 query.first、picks 不参与检索）。
- **新形态**：
  1. `MaterialSearchPlan` 结构化（`queries[]` 全用上、`sources[]`、`targetBand`、`maxMinutes`、`needAudio`、`avoid[]`）；
  2. App 端并发执行：公开源（gutenberg/arxiv/npr…）+ **DeepSeek `/v1/tools/search`**（长尾）；
  3. **候选先抓正文 → `MaterialLibrary.analyze` 算真实 knownTokenRatio → 按 band 过滤/排序**，再接模型做卡片化；
  4. 失败就让"这次没抓到"可见（现有 `SearchEvent` 时间线直接复用，`original_search.dart:54-100`）。
- **为什么要现在做**：官方 Search/Fetch 把"长尾资源"变成一次 HTTP 调用（5 元/千次），而 1M 上下文允许"抓 5 篇一次全读"来打分/出题；这是过去做不到的。

### 改造点 2：把 `planMaterialSearch` 从『一次性吐 JSON』换成『Tool Calls 闭环 + JSON Output』

- **文件**：`lib/services/deepseek_api.dart:119-194`（提示词 143-161）、`lib/services/base_api.dart:68-88`（构造请求，目前完全没 `tools`/`response_format`）。
- **新形态**：
  - 给模型注册 `search(query, count)` / `fetch(url)` 两个工具（真实执行在 App），模型多轮决定"搜什么、抓哪条"；
  - 用 `response_format:{type:'json_object'}`（`deepseek_api` 落地时注意：官方 JSON mode 要求 prompt 含 "json" 字样 + 给样例，且非 JSON 会被替换成空格 → 必须有防空兜底）；
  - 把画像从"一句话 hint"升级为结构化入参：`{exam, goals, vocab, cefr, band, minutes, genres, blocked[]}`；
  - **每条结果必须带 `url/source/authority/date`**，无出处的结果不进卡片（杜绝"AI 回忆书名"）。
- **注意**：思考模式下带 `tools` 时**必须回传 `reasoning_content`**，否则 400；现网所有链路默认 `thinking:disabled`（`api_endpoint.dart:135-148`），若要开思考，`buildChatBody`/`followUpStream` 的回传逻辑要同步改。

### 改造点 3：把『个性化』从两张表变成一条闭环（数据层）

- **文件**：`lib/models/learner_model.dart:91-132`（补字段/清理死字段）、`lib/services/material_prefs.dart`（补形态/时长）、`lib/services/learner_context.dart:65-90`（把已知词表给到检索侧）。
- **动作**：
  1. 补 `exam`（枚举+目标分+期限）、`grammarWeak[]`、`materialShape{minutes,audio,accent}`、`difficultyPolicy`；
  2. 统一两套画像（旧 `LearnerProfile` 只在 AI 推荐用；要么迁移合并，要么明确标注"这是 v1.8 遗留"）；
  3. 修死字段：`goals` 加写入入口（备考选择）、`reading_wpm`/`vocab_inferred` 从行为数据写回；
  4. **把 `blockedTopics/Keywords` 应用到公开源检索结果**（现在只过滤 AI 推荐，`material_center_screen.dart` 无 blocked 引用）；
  5. 记录"搜→开→读完/放弃"，作为兴趣与难度的隐式反馈（数据库已有 materials/progress 表，`material_library.dart:307-354`）。

---

## 7. 附：成本/时延粗算（用于方案取舍）

| 动作 | 成本 | 备注 |
|---|---|---|
| 一次 AI 检索规划（deepseek-flash，思考 disabled，输出 ~1KB） | < 0.01 元 | 输入 ~1K token、输出 ~500 token；高峰/空闲差 2 倍 |
| 一次官方 Search（count=10, need_content=true） | 0.005 元 | 失败/无结果不计费 |
| 抓 5 篇正文（Fetch ×5） | 0.025 元 | 403/404 不计费但会耗 QPS |
| 5 篇正文 + 5 条摘要交给 flash 打分/出卡片 | 输入 ~30K token ≈ 0.03~0.06 元 | 缓存命中再降一个量级（0.02~0.04 元/M） |
| **单次"AI 找材料"总成本（含打分）** | **≈ 0.05~0.1 元** | 比"模型自己编书单"贵，但结果可验证 |

**时延**：Search ~1s；Fetch 每篇 1~5s；5 篇并发约 5s；再加模型 3~10s → 一次完整"找 + 打分 + 卡片"约 10~20s，与现有 `OriginalSearch` 的 12s 超时预算同量级（需把超时策略改成"预算制"而不是每源固定 12s）。

---

## 8. 未证实/需下一轮验证的点

1. **四六级/雅思/托福"官方公开样题"能否稳定抓取、是否允许在 App 内展示** —— 本次未逐站核实，标注**未证实**。
2. **第三方搜索 API（Bing/Tavily/Serper/博查）在大陆网络下的可达性与合规** —— **未证实**，不建议在 v1 引入。
3. **"V4.1-Flash-1017 着重增强抓资源能力"** —— 官方原文未出现该表述，**未证实**；能证实的是官方开放了 Search/Fetch API 与 agentic benchmark 提升。
4. **`api.deepseek.com` 在当前客户端网络环境的实测时延** —— 本项目现网默认即用它（`constants.dart:15`），但本次只读审计**未做实机联网测试**。
5. **`deepseek-flash` 图像理解与方舟视觉模型同图同 prompt 的实际识别质量对比** —— 未测；若要"主槽位统一到 DS 一家"需先做识别质量对比。
