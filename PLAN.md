# PLAN.md — AI上外语 (readflow)

## 状态
- 当前版本:**v1.9.1+50**(Release v1.9.1 = Latest;v1.9.0 有流式致命 bug 已弃用;aapt versionCode=50/versionName=1.9.1)
- 当前阶段:✅ **2026-09-19 代码审查修复已交付 + v1.9.1 真机回归热修**(`docs/CODE-REVIEW-2026-09-19.md` §10)
- 状态协议:DONE(analyze 0 error/0 warning、195 测试全绿 +1 skip、APK 已发 Release、远端已同步)
- 维护约定:本状态区是版本/阶段的唯一事实源,**每次发版必须同步更新这三行**(历史小节只追加,不回改)

## 需求摘要
**项目**:AI上外语(Flutter 英语学习 App,D:\readflow)
**一句话**:拍照识词→生词归档→AI 文章→回译练习的个人英语学习闭环
**用户**:自己 + 几个朋友(Android)
**远程仓库**:https://github.com/820sz/ai-shangwaiyu(**公开**,AGPL-3.0,gh CLI 已登录 820sz)

## 设计笔记(2026-08-03,主/副槽位架构)
**背景**:全项目审查发现 3 个正确性 bug + 用户实测 3 个问题,且 DeepSeek 旧模型 ID 停用导致文本功能全挂。

**目标**:练习评分有真实依据 / 子分类保存可复用历史 / API 配置解绑厂商名 / 所有改动通过 analyze + 单测。

**方案**(已实现):
- 主/副槽位:Hive key 复用 doubao→主、deepseek→副,不迁移数据;keyDeepseekThinking(默认 disabled)
- ApiEndpointConfig + BaseApiService(共享 HTTP);MultimodalApiService(原 doubao)读主;TextApiService(原 deepseek)读副,副未配置 fallback 主
- 追问槽位 keyFollowUpSlot('primary'/'secondary'),双分组选择器,followUpStream 按槽位取端点
- A1:DB v4 reference_answers 列,评分=词集合重叠率(scoring.dart);旧练习保留长度启发式
- B1:getMaterialPathsByCategory 历史子分类 ChoiceChip 点选

**被否掉的方案**:只改设置页标签不角色化;单一 API 槽位。

## 版本记录(最新在前)

### v1.9.1 — 紧急修复 v1.9.0 流式全线不可用(Utf8Decoder 类型错)(2026-09-22,已发布)
**背景**:用户在真机装 v1.9.0 后实测"识图直接用不了了",界面报
`type 'Utf8Decoder' is not a subtype of type 'StreamTransformer<Uint8List, String>' of 'streamTransformer'`;追问/AI 文章/材料推荐一并失效(凡走流式的功能)。
**根因**:v1.9.0 修 P1-2(中文跨包乱码)时把 SSE 解析改成 `rawStream.transform(utf8.decoder)`,而 `rawStream` **声明**为 `Stream<List<int>>`、**运行时**是 `Stream<Uint8List>`(dio `ResponseBody.stream`);`Stream.transform` 按接收者实际类型参数做检查 → `Utf8Decoder` 被判不匹配 → 运行时 `_TypeError`,整条流读不出任何内容。
**为什么单测没拦住**:测试用 `Stream<List<int>>.fromIterable` 造流,接收者类型参数是 `List<int>`,检查通过 —— **真机类型与测试类型不一致,把缺陷测绿了**。
**修复**:`parseSseStream` 里先 `rawStream.cast<List<int>>()`(Dart 官方修法),4 个流式调用点全经此解析器,一处修复全覆盖;测试改用 `Stream<Uint8List>`/`StreamController<Uint8List>` 造流,新增 2 条针对该报错的回归用例(修复前逐字复现真机错误)。
**验证**:195 测试全绿 +1 skip(v1.9.0 为 193);analyze 0 error/0 warning;APK 1.9.1+50。


### v1.9.0 — 全面代码审查修复（P0 3/3 · P1 9/9 · P2 34/34）(2026-09-21,已发布)
**背景**:用户要求"把软件做一个好好的 review,再依次修复所有问题"。审查产出 `docs/CODE-REVIEW-2026-09-19.md`(45 个文件逐行过 + 5 维度审计 + 主审逐条复核,剔除 3 条不成立结论、改写 2 条机制错误、降级 2 条严重度),本版按该报告 §8 的 B1–B6 批次全部实施;落地记录见该文档 §10。
**最要紧的修复**:
- **P0-2 迁移不可自愈**:步骤级 `catch` 吞异常 + `user_version` 照推 → 失败的迁移永不重跑(生词本 `no such column`)。改幂等 + 单事务 + 真实错误上抛 + 启动自检补列。**并修掉审查自己漏掉的一处**:`_onCreate` 建表语缺 `phonetic` 列,全新安装必崩。
- **P0-3 第二个 API 服务没跟上修复**:DS 请求带 `max_tokens`/`temperature` → 正文被思考吃光。三个方法统一走 `buildChatBody` + 思考通道兜底。
- **P1-2 SSE 中文跨包损坏**:逐块 `utf8.decode(allowMalformed)` 把被 TCP 切开的中文字节解成 U+FFFD(不可恢复)或整帧静默丢弃 → 改流式解码 + `LineSplitter` 分帧,失败计数并抛出可诊断错误。
- **P1-3 流内卡死**:`receiveTimeout` 只管到响应头,首字节计时器收到第一个 chunk 就 cancel → 半开连接时前台永久转圈。三条流式链路各加 60s 空闲看门狗 + 「取消生成」。
- **P1-5 复习进度丢标记**:`marks` 只在内存 → 续看后标记消失且重复计数(与 9 月"能一直点认识刷进度"同源)。改随进度持久化 + 按 `lastId` 定位断点。
- **P1-7/P1-8/P1-9 数据一致性**:批量路径单事务分片、`fromMap` 全容错、dbVersion 10 补 9 索引 + 外键 + 清孤儿练习。
- **P0-1 更新链路**:下载后校验 sha256 + 字节数(料取自 Release asset 的 `digest`/`size`),校验不过拒绝安装;签名仍为 debug keystore(A/B/C 三条路需产品决策,本版按 C 走)。
**验证**:analyze 0 error / 0 warning(24 infos,与修复前同量级);193 测试全绿 +1 skip(修复前 176+1);APK arm64 versionName=1.9.0/versionCode=49,sha256 与 Release asset `digest` 逐字一致。
**未做(留 v1.9.1+)**:`process_chat.dart` 三分拆、`follow_up_drawer` 控制器分文件、交互组件抽取、`flutter_markdown`(已 discontinued)/`hive`/`fl_chart` 依赖升级、§5 的三条增量动效、`process_chat` 结果区 Sliver 惰性化、`.github/workflows/ci.yml` 推远端(需先 `gh auth refresh -s workflow`)。

### v1.4.2 — 追问第二问400根因+收藏提示/总览布局+全文翻译分组(2026-08-27,已发布)
**背景**:用户真机实测 v1.4.1:DS 不思考能识图但思考低度失败;追问第一问成功、第二问必 400;收藏提示相反;总览单词被挤拆行;首页模型菜单不跟随配置;全文翻译段落挤在一起。
**根因与修复**:
- **追问第二问 400(实锤)**:历史消息 role 直接用 'ai' → OpenAI 兼容协议只认 user/assistant → 带历史必 400。修复:buildFollowUpHistory 纯函数映射 ai→assistant(+4 回归测试)
- **收藏提示相反**:toggle 异步,点完立即读状态 → 读到旧值。修复:toggle 返回 Future<bool>(真实结果),await 后提示
- **总览单词拆行**:星标+箭头并排挤窄单词列。修复:星标取代箭头位置(无收藏功能时显示箭头)
- **首页模型菜单**:加当前配置模型(去重),跟随 API 设置变化
- **全文翻译分组**:多轮追加按图片显示分组标题("p1 识别结果 · 第 1 张图片")+ 段落;点击 pN 跳转到该图第一段
- **DS 思考失败诊断**:解析失败错误页展示 AI 返回原文(前 400 字);识别/追问 max_tokens 2048→4096
- 验证:analyze 0/0;123 测试全绿(+4);aapt 1.4.2+42
- ⚠️ 待用户复测:DS 思考低度仍失败的话,错误页原文片段会直接揭示根因(截断/格式/思考后无 content)

### v1.4.1 — DeepSeek API 根因修复(http→https)+ 收藏星/错误中文/翻译跳转(2026-08-27,已发布)
**背景**:用户真机实测 v1.4.0 全崩:DS API 从来用不了(识别 302/追问 400-404/模型读不出);收藏星点无反应;全文翻译追加后 p1/p2 跳不回去;诊断信息被认为虚设。
**根因(实测实锤)**:用户 Base URL = `http://api.deepseek.com`(无 s)——DS 官方 CloudFront 对 http 返回 301/302,Dio 跨协议重定向抛 bad response。**DS 模型全链路(识别/追问/模型拉取)都指望这个端点,所以全线失败**。curl 实测:http → 301;https → 正常鉴权响应。
**修复**:
- normalizedBaseUrl:http:// → https:// 自动归一(测试覆盖)
- 设置页 Key 框 hint 修正(不再是 URL 灰字:"sk- 开头=DeepSeek 官方 · ark- 开头=火山方舟");URL 框"留空按 Key 类型自动使用";主 API 说明文案更新
- 收藏星标 UI 跟随:_isVocabBookmarked 由 context.read 改 context.watch(收藏/取消后星标实时变化,不重建的根因)
- 错误信息友好化:BaseApiService.friendlyError——优先服务端 error message + 常见状态码中文指引(识别页/追问页统一),不再满屏 DioException 英文
- 全文翻译 p1/p2 跳转:_fullTextGroupStarts 记录每轮识别段落起点 + 段卡 GlobalKey,_scrollToImageGroup 全文翻译分支跳对应段
- 模型拉取:兼容 {"data":[]} / {"models":[]} / 纯数组;lastFetchNote 记录结果(诊断信息页"模型列表加载"可见:成功 N 个/结构异常/失败原因)
- 验证:analyze 0/0;119 测试全绿(+1 http→https);aapt 1.4.1+41
- ⚠️ 教训:用户配置错误(手填 http://)导致的连锁失败,必须靠"诊断信息可读化"暴露真实状态,不能只改提示文案

### v1.4.0 — 追问记忆+复制交互+收藏夹+全文翻译增强(2026-08-26,开发完成待发)
**背景**:用户睡前留言 8 项(6~13),含一个核心 bug(追问失忆)+ 一批新功能/改名。
**实现**:
- **13 追问失忆(根因修复)**:followUpStream 的历史消息从未发送,messages 永远只有 system+当前问题 → AI 无任何上下楼记忆。修复:history 参数(最近 20 条已完成对话,排除当前问题自身)+ 材料上下文(识别结果/翻译)放 system 消息;最后一轮 user 只放"用户提问:xx"(带图时 parts)。纯函数 buildFollowUpLastUserContent 可测
- **7 复制交互**:词条长按两层逻辑(未选中→选中;已选中→复制菜单:原文/释义/全部,中文"复制");追问 AI 文本 SelectionArea + 自定义工具栏「复制全部/取消选择」(用户实测选完只能按返回键)
- **11 改名**:拍照取词→拍照识文;my_materials 空态文案同步
- **12 改名**:追问抽屉标题"追问对话"→"追问抽屉"
- **10 全文翻译追加图片**:按钮对 fullText 模式放开;追加时段落累计(不替换)
- **6 全文翻译讲解导引**:段落卡「✨ AI 讲解」按钮+点击原文 → 追问详解该段(带原文+译文上下文)
- **9 收藏夹**:DB v6 bookmarks 表(source/title/content/source_word/model/created_at)+ Bookmark model + BookmarkProvider + 我的页「收藏夹」入口 + BookmarksScreen(详情/复制/删除)
- **8 收藏 UI**:追问 AI 气泡星标(流式完成后显示)+ 词汇卡片星标(总览 WordListTile + 详细模式),词汇收藏=原文+释义+例句,独立于生词本
- **API 自动端点(v1.4.0 配套)**:Base URL 为空时按 Key 前缀自动配对——sk-→api.deepseek.com,ark-/其他→槽位默认(主=方舟);保存时自动补默认 URL 并提示;模型列表拉取同样按 key 推断端点(根治"方舟 key + DS 模型"错配)
- 验证:analyze 0 error / 0 warning;118 测试全绿(+3 bookmark 往返;DB v6 断言更新)
- 待办:构建发布 + 用户真机验收 8 项 + 之前的 3 项(0/1/5)回归

### v1.3.2 — 崩溃日志落盘 + Base URL/Key 清洗 + 诊断入口(2026-08-25,构建完成待发)
**背景**:用户实测:①Base URL 粘贴带全角冒号/空格 → Dio 抛 "Illegal scheme character (at character 5)"(截图实锤)②"改回豆包模型后第一次识别必闪退,第二次正常",无日志只能盲猜。
**修复**:
- CrashLogger:FlutterError/zone 异常全局捕获落盘 文档目录/crash_log.txt;我的页新增「诊断信息」入口(crash 日志+API 配置摘要 key 打码,可清空)——下次闪退自证根因,不再打地鼠
- cleanBaseUrl/normalizedBaseUrl:全角冒号/斜杠/空白/换行/BOM 清洗;非法(非 http(s) 开头)回默认端点,绝不进 Dio
- 设置页保存:URL 清洗+非法重置为默认+提示;API Key 去全部空白
- 验证:analyze 0/0;115 测试全绿(+8 base_url_clean)

### v1.3.1 — 模型列表过滤+端点配对防呆(2026-08-25,已发布)
**背景**:v1.3.0 真机测试失败:用户主槽位(方舟 ark- key + 空 Base URL)手输 DS 官方模型名 deepseek-v4-flash-vision-exp → 识别失败"API Key 无效"(实为端点/模型不匹配:该模型只存在于 api.deepseek.com);且主槽位"不过滤"后方舟 /models 全量展示(未开通的 doubao-1-5* / character / deepseek-r1/v3 转售)用户投诉"一堆乱模型"。
**修复**:
- 主槽位模型列表按**视觉候选过滤**(isVisionCandidate:含 vision 或 doubao-seed 系;隐藏 1-5 老文本/character/纯文本 DS 转售);过滤后为空回退内置视觉清单
- 选择器选中 DeepSeek 模型但端点为方舟(空/volces)→ SnackBar 即时提示配对
- 识别失败 401/403 且模型=DS视觉+端点为方舟 → 明确提示"模型与端点不匹配:需 api.deepseek.com + sk- Key",不再误导"Key 无效"
- 设置页主 API 说明文案补充配对说明
- 验证:analyze 0/0,107 测试全绿(+3 isVisionCandidate)
- ⚠️ 用户配置真相:主槽位单槽位只能配一家店——ark- 开头=方舟(豆包/doubao-seed 系+方舟版DS),sk- 开头=DeepSeek 官方(api.deepseek.com,deepseek-v4-flash-vision-exp 只在这家)。识图想用 DS 视觉 → 主槽位整体切到 DS 官方配置

### v1.3.0 — 用户人工测试 6 项修复(2026-08-25,构建完成,发布中)
**背景**:用户真机人工测试发现 6 项(见下),范围确认 6 项全做,4 阶段完成。
- 0. 主 API 界面无法唤起 DeepSeek 模型(似乎与豆包捆绑);DS 已上线识图模型需兼容调取
- 1. 追问抽屉 AI 回复思考档位被砍(用户本意只砍识图的思考)
- 2. 用户手动补充的词汇需要 AI 自动补全(释义/词性等,现需全手动)
- 3. 识别结果页需要"AI 二次识别补充"(入口不能在底部 UI)
- 4. 追问抽屉用户消息支持"编辑修改"
- 5. 追问抽屉的 AI 收不到识别结果(截图实锤:"这页主要讲了什么"→ AI 称未收到内容)

**根因与设计**:
- **问题 0**:主槽位 fetchModels 按前缀硬过滤 `['doubao']` + 兜底/菜单清单纯豆包系(模型列表里根本没有 DS 模型,手动填 ID 才能用)。修复:主槽位列表不过滤、兜底清单加 DS 视觉模型 `deepseek-v4-flash-vision-exp`(DS 2026-08-21 官方上线多模态,/chat/completions OpenAI 兼容);追问抽屉主分组/底部栏菜单从"硬编码豆包清单"改为"当前主槽位模型 + 主槽位兜底清单";请求体 detail 字段仅豆包系发(DS 不认未知字段防 400);思考档位映射按模型族(豆包 minimal/low/medium/high,DS low/medium/high,F6 fallback 保底);头像判断加 DS 视觉
- **问题 1**:v1.2.17 本意只砍识图,但实现把全局 thinkingOptions 砍成 2 档 + ApiEndpointConfig.thinking 把 medium/high 迁移成 low,追问档位一并丢失。修复:新增独立追问思考档位 keyFollowUpThinking(4 档:不思考/低/中/高),追问面板读写它;识图保持 2 档(8-08 决策不变);追问请求按追问档位构造思考参数(DS 不认枚举有 fallback)
- **问题 5**:_doFollowUpStream 默认上下文只有"已识别词汇"列表(全文翻译模式下为空!)+ followUpStream 是纯文本请求不带图。修复:默认上下文 = 词汇列表 + 全文翻译段落(原文+译文);支持图片:主槽位且模型支持视觉时附识别图片 data URI,图片被拒(400)自动降级纯文本重试
- **问题 2**:手动添加词汇对话框新增「✨ AI 补全」按钮——填词后点按调当前追问端点(JSON 返回 释义/词性/例句/语法)回填表单可改;无 AI 配置时禁用
- **问题 3**:识别结果 AppBar 右上角新增"再识别"图标(避开底部栏)——对当前全部图片重新识别,提示词"只找遗漏不重复已有词",按 word 去重合并
- **问题 4**:追问用户气泡长按 → 编辑 → 替换该消息 + 删除其后 AI 回复 + 自动重新发送生成(防手误重问)

**验证目标**:analyze 0 error / 单测(思考映射/请求体构建/合并去重/上下文组装)/ 真机验收清单(6 项逐一)

**阶段 1 完成(2026-08-25)**:问题 0/1/5 代码+验证全绿:
- analyze 21 存量 info 零新增(0 error / 0 warning)
- 96 测试全绿(+19:follow_up_context 4 / model_capability 10 / thinking_params 扩展 5)
- 修改文件:constants.dart(deepseekVisionModel/keyFollowUpThinking/followUpThinkingOptions/primaryFallbackModels)、api_endpoint.dart(supportsMinimalEffort 按模型名推断 + buildThinkingParamsFor 4 档)、doubao_api.dart(shouldSendDetailFlag/modelSupportsImages/追随带图+降级/imageDataUrisFor)、api_settings.dart(主槽位不过滤)、input_home.dart(菜单换新清单)、process_chat.dart(追问档位独立/上下文+图片/菜单清单)、新文件 utils/follow_up_context.dart + 2 个新测试文件
- ⚠️ 环境踩坑:本会话 flutter 命令需 FLUTTER_ALREADY_LOCKED=true + 全盘权限(danger-full-access)才能跑(沙箱只读 D:\flutter 导致 lockfile CreateFile failed 5);analyze 首跑 169s 后续 ~10s;docker 外的网络需梯子

**阶段 2 完成(2026-08-25)**:问题 2/3/4 代码+验证全绿:
- analyze 0 error / 0 warning,104 测试全绿(+8:parseWordInfo 4 / mergeSupplementResults 4)
- 问题 2:`completeWordInfo` 非流式补全(思考 disabled,端点=当前追问槽位)+ `parseWordInfo` 纯函数 + 添加词汇对话框「✨ AI 补全」(只回填空字段;未配置禁用)
- 问题 3:`_supplementMode` + `_reRecognize`(入口 AppBar auto_awesome 图标)+ `extractVocabularyStream(excludeWords)` 提示词加"已识别清单只找遗漏" + `mergeSupplementResults` 去重合并 + 空结果回结果页提示
- 问题 4:用户气泡长按编辑 → `_editFollowUpMessage`:替换 + 截断其后消息 + 自动重发
- 新文件:utils/supplement_merge.dart;测试:supplement_and_word_info_test.dart
- 待办:阶段 3(构建 v1.3.0 + 真机验收 6 项 + Release)

## 验证目标(当前版 v1.3.0)
- [x] flutter analyze 0 error / 0 warning(21 存量 info 零新增)
- [x] flutter test 104 全绿(+19 阶段1:+8 阶段2)
- [x] APK:versionName=1.3.0 versionCode=37(aapt 验证);构建 20.7MB arm64;libapp.so 含新代码字符串(follow_up_thinking/deepseek-v4-flash-vision-exp/补充识别/修改并重新发送)
- [ ] 真机验收(待用户):0 主槽位选 DS 视觉模型识别 / 1 追问 4 档 / 2 AI 补全 / 3 再识别补漏 / 4 编辑重发 / 5 追问"这页讲了什么"能答

### v1.2.26 — 例句精简+出处词标粗 / 全文翻译复制保存 / process_chat 拆分(2026-08-10,Release 已发 = Latest,**用户真机验收通过**)
- **例句精简(方案1)**:新组件 `widgets/example_sentence.dart`——出处例句限行 3 行 + 超限显示"展开/收起";**出处句中目标词加粗**(buildHighlightSpans 纯函数,12 测试:大小写不敏感/词边界守卫防 "cat" 标进 "concatenate"/变形词不标/词条化截断词不标/word==整句不标)。三处接入:识别结果页详细模式、词详情 BottomSheet、词库词汇详情页
- **全文翻译复制/保存**:AppBar 加 ⋮ 菜单(翻译存在时)——"复制全文翻译"(内置 Clipboard)+"保存/分享翻译"(自写原生通道 app/share_text,ACTION_SEND 系统分享面板,零新依赖;存到微信/备忘录/文件管理器)
- **process_chat 拆分(安全拆,用户确认)**:3766 → 3184 行(-582),4 个新文件:follow_up_models(FollowUpMessage/FollowUpSavedConversation 公开化)/ follow_up_bubble(AiFollowUpBubble+ThinkingBlock)/ scroll_buttons(FollowUpScrollButtons+ScrollToTopButton)/ model_avatars(userAvatar/aiAvatar 等 6 方法)。纯搬移+改名,行为零变化,每批 analyze+测试全绿。顺手归位 1 处错位注释
- 验证:analyze 21 存量 info 零新增 / 77 测试全绿(+12 新增);aapt versionName=1.2.26;资产 size 21672281 核对一致
- 真机验收(2026-08-10 用户):例句标粗/展开 ✓ 翻译菜单两项 ✓ 拆分后全流程回归 ✓

### v1.2.25 — 词条截断终局:overflow ellipsis→visible(2026-08-10,commit 4d2cd2b,**用户真机验证已解决**)
- 最终生效改动:详细/总览词条 Text `overflow: TextOverflow.ellipsis` → `visible`(maxLines 早已 null)。从 Flutter 语义封死省略号路径
- 血泪教训:用户从第一天说是 UI 层(10+ 截图),CC 死磕数据层一整晚(提示词/test/回退/清洗),实际 Expanded 一直在、maxLines 早 null,该早把 ellipsis 换 visible
- 保留防线(无害):displayWordText 省略号回退(v1.2.20/21)+ cleanTruncatedWord 数据清洗(v1.2.24)——仅词条带省略号时触发

### v1.2.24 — 数据层治本:解析后清洗词条化截断(commit fb618e0)
- cleanTruncatedWord:word 带截断特征(…/⋯/../.../…… 任意形态)且存在更长完整句 → 用 originalSentence 替换 word 数据本身(9 测试)。方向事后证明非根因,但作为数据防线保留

### v1.2.23 — 修复版本号(commit b92c7dd)
- v1.2.21/22 构建时忘 bump pubspec,APK 安装界面/设置页仍显示 1.2.20(用户实测"安装界面变成20"),白装两次。**发布铁律:bump 版本 + aapt 验证 versionName**

### v1.2.22 — 更新检查取最新 tag(commit aaa59a0)
- 检查竞速"先到先得"会拿镜像缓存的旧 latest 响应 → 误判"已是最新"(用户实测"自动更新还是20")。改为收集所有响应取 tag 最大(pickLatest,5 测试)

### v1.2.21 — 词条不限行(commit b206c6b)
- 详细/总览 word/translation Text 去掉 maxLines(word 类型原 1/2 行省略),一排放不下自动换行;TextPainter 验证换行引擎正常

### v1.2.20 — 词条回退放宽(commit 3728717)+ 回滚误回退(commit 691aad2)
- displayWordText 回退条件放宽(省略号变体 contains);**isShortened 按长度回退是回归**(短语"compound with"误回退成整句,用户实测),已回滚只留省略号特征

### v1.2.19 — 自动更新检查加镜像竞速(2026-08-09,commit 6935ae5)
- 根因(用户实测"收不到自动更新"):checkLatestRelease 裸连 api.github.com(国内经常连不上,10s 超时静默失败)——下载有 6 镜像竞速,检查却没有
- 修复:检查改直连+全部镜像前缀竞速,15s 总预算兜底
- ⚠️ 自动更新链路自 v1.2.9 权限修复后从未在真机验证成功过;本版需手动安装一次

### v1.2.18 — 修复返回结果页无保存弹窗(2026-08-09,commit e8b0948)
- 回归根因:v1.2.10 起识别完默认不选中(长按才选中),返回确认弹窗条件要求 _selected.isNotEmpty → 没选中词时返回=静默退出,"保存/暂时离开/不保存/取消"弹窗永不出现
- 修复:有识别结果就弹窗;未选中时"识别出 N 个词(未选中),是否全部保存?"+「保存全部」(_saveAndReturn 加 saveAll 参数)

### v1.2.17 — 识图思考砍中/高档,只留 不思考/低度(2026-08-08,commit cf69c90)
- 用户决策:中/高思考调多轮仍慢 → 砍掉。存量 medium/high 设置自动迁移到 low(getter + 设置页 _migrateThinking),UI 选项同步只剩 disabled/low
- 词条截断定位(08-08 决定性实验):v1.2.16 提示词(禁止截断/禁止省略号)已使模型完整输出——同段内容 4 组实测(2-0-lite/2-1-turbo × 禁用/minimal)全部 0 截断,App 流式重组→解析→显示链路逐行核查无截断点;用户端截断现象均为 ≤v1.2.15 旧提示词识别数据,重新识别即完整
- 验证:analyze 0 error / 40 测试全绿+1 skip;⚠️ 发布踩坑:build 未完成就建 Release 挂了旧 APK,须 --clobber 重传(已修正并核对字节一致)

### v1.2.16 — 砍掉思考降级链路 + 提示词根治词条截断(2026-08-08)
- 用户实测 v1.2.15:低档≈3s ✓;中档仍太长 ✗;详细模式短语/句子仍截断 ✗
- 思考:删除整个降级链路(_degradeToFast/_onThinkingTimeout/_thinkingDegraded/纯思考超时)——reasoning_effort 生效后思考时长可控(~3-25s),原降级=等满阈值+完整重跑一遍识别,总耗时双倍。思考模式首字节超时放宽 60s 只报错不自动重试;Dio receiveTimeout 180s 为最终兜底
- 词条截断根因(23:04 截图逐字读):word 字段被模型词条化截断(开头~20字符+"…"),且提示词把 original_sentence 标为"可选"→ 模型大量省略 → v1.2.15 的回退无源可用。修复:①提示词强制 word 完整输出、禁止截断/省略号;短语/句子 original_sentence 必填(治本,新识别生效)②显示回退去掉 word 类型豁免——任何类型 word 以省略号结尾且存在更长完整句子时回退 originalSentence(双保险)
- 验证:analyze 0 error / 40 测试全绿+1 skip

### v1.2.15 — 思考参数根治(reasoning_effort)+ 短语/句子完整显示回退 + 新logo(2026-08-07,commit 65faa23)
- 思考慢根因(实测):budget_tokens 对豆包完全无效(512/1024/2048 耗时 27-37s 无差别),不传 thinking 默认深度思考 61.8s;改用 reasoning_effort(官方分档,实测生效):档位映射(整体提速档)低→minimal≈3s/中→low≈14s/高→medium≈25s(复杂图);副槽位 DS 不认时自动降级移除(已有链路)
- 省略号根因(22:21 截图逐字读出):模型把 phrase/sentence 的 word 字段词条化截断(开头~20字符+"…"),originalSentence 字段完整——显示层回退:word 以省略号结尾且存在更长 originalSentence 时显示完整句子(详细模式 _displayWord + 总览 WordListTile)
- 思考文案按新映射更新;reasoning 超时阈值适配(低10s/中20s/高30s)
- 新 logo:用户定稿图直接缩放替换 5 密度(不做任何处理)
- 验证:analyze 0 error / 40 测试全绿+1 skip(含 thinking_params 6 用例)

### v1.2.14 — 换 logo + 句子显示修复确认(2026-08-07,commit a928006)
- 新图标(2048x2048)缩放到 5 密度替换 ic_launcher.png
- 句子截断排查结论:识别结果页 word 字段自 v1.2.10 起 phrase/sentence 已放开 maxLines(v1.2.13 补 phrase),**全项目无其他截断点**;用户截图仍截断 → 疑似手机版本 ≤ v1.2.9(旧版 maxLines:1 全截断,桌面曾堆多版本可能装到旧版)→ 发布后走自动更新,核对设置页版本号
- 思考模式维持 v1.2.13 双路降级现状,不折腾(**待新会话排查**)

### v1.2.13 — 思考兜底补首字节盲区 + 短语完整显示(2026-08-07,commit e8a80b0)
- 问题1:v1.2.12 的降级只在"收到 reasoning chunk 后"启动计时——豆包可能连 reasoning 都不吐,兜底失效(用户实测仍很长)
- 修复:思考档位**首字节超时** 20/25/30s,到点无任何字节 → _degradeToFast 自动降级快速识别(取消流/清状态/SnackBar/重发)。两路兜底齐:reasoning 超时(10/15/30s)+ 首字节超时(20/25/30s),总耗时封顶 ≈ 30-40s
- 问题2:短语(phrase)漏改 maxLines——上轮只放开 sentence。现在 word 单行/两行省略,phrase/sentence 完整多行,详细+总览一致
- 验证:analyze 0 error,34 测试全绿

### v1.2.12 — 思考模式恢复 + 纯思考超时自动降级(治本)(2026-08-07,commit 7d0158c)
- 背景:v1.2.11 直接禁用识图思考被用户否定(回避问题)。真相:**豆包视觉模型思考时间服务端不可控,budget_tokens 对它无效**,低中高各档都离谱,参数微调全是徒劳
- 方案:恢复思考模式 + 纯思考超时兜底:第一个 reasoning chunk 出现启动计时(低10s/中15s/高30s),到点没出 content → 切断流,自动降级"不思考"重识别(总耗时≈30-40s),SnackBar 提示
- _thinkingDegraded 状态:降级仅本次生效,识别完成/手动重试复位;首字节超时思考档位放宽 45/60/90s;dispose/_onStreamDone 清理计时器
- 验证:analyze 0 error,34 测试全绿

### v1.2.11 — 识图固定不思考 + 例句完整 + 取消选择 + 后台中断自动重试(2026-08-07,commit cb33119,**未单独发 Release**,并入后续)
- 识图请求直接 thinking disabled(豆包视觉思考速度不受 budget_tokens 控制,停止瞎改);追问仍可思考(followUpStream 保留 thinking 参数)
- 例句去掉 maxLines:2 截断;AppBar 选中态新增"取消选择(N)"按钮;onDone/onError 置 _subscription=null,resumed 时 connecting/streaming 且订阅已结束 → 自动重试
- 验证:analyze 0 error,34 测试全绿

### v1.2.10 — 选中交互重做 + 思考再降 + 句子完整 + 追加按钮挪位(2026-08-07,commit f2bb20f)
- 选中交互:识别完成/追加/恢复默认不选中(长按才选中);删除按钮移 AppBar 右上角(选中时红图标+计数);底部栏只留 模型/保存/追问
- 思考再降:budget_tokens 512/1024/2048(部分豆包视觉模型疑似只认 type 不认 budget);思考选项文案带预估耗时(低·约10s/中·约30s/高·约1分钟)
- sentence 类型词汇不限行数(之前 maxLines:1 过度截断);追加图片按钮挪到"共N张图片"行右侧
- 验证:analyze 0 error,34 测试全绿

### v1.2.9 — 安装终极根因:缺 REQUEST_INSTALL_PACKAGES 权限(2026-08-07,commit d649d41)
- 现象:v1.2.7 自写通道 startActivity 成功但安装器从不出现,静默关闭
- 终极根因:Manifest 只有 INTERNET/ACCESS_NETWORK_STATE,**缺 REQUEST_INSTALL_PACKAGES**——系统安装器对无此权限 App 的安装请求静默拒绝。手动装走文件管理器(有权限)所以一直成功;**App 内更新从上线起从未成功**(.part/authority 都是二三层问题)
- 修复:Manifest 加权限 + update_dialog 用 WidgetsBindingObserver 检测安装意图后是否进后台,没进→引导"设置→应用→AI上外语→安装未知应用→允许"+重试
- ⚠️ 从 ≤v1.2.8 升上来的版本缺权限,必须桌面 APK 手动过渡一次

### v1.2.8 — 思考提速 + 删除选中 + ✏布局 + 流式滚动/↑↓ + 追加图片识别(2026-08-07,commit 7a83b90)

### v1.2.7 — 自写 MethodChannel 安装通道,弃用 open_filex(2026-08-07,commit 7a83b90 前序)

### v1.2.6 — 追问抽屉 4 项体验 + 词汇 3 项功能(2026-08-07,已发 Release)

### v1.2.5 — 自动更新真正根因:FileProvider authority 不匹配(2026-08-04,commit a148025)
- open_filex 4.7.0 Android 硬编码 authority = `packageName + ".fileProvider.com.crazecoder.openfile"`(camelCase);Manifest 配的 `${applicationId}.fileprovider` 从未匹配 → getUriForFile 异常被插件吞,Dart 端静默失败
- 修复:Manifest authority 改 camelCase + installApk 检查 OpenResult.type 非 done 抛异常显示真实错误
- 教训:插件硬编码配置须与 Manifest 逐字核对;升级链路须真机完整走通一次才算交付

### v1.2.4 — 暂存会话崩溃修复 + 追问头像按消息模型(2026-08-04,commit 4ddd3c7)
- `_Map<dynamic,dynamic> is not subtype of Map<String,dynamic>` — Hive 读回嵌套 Map 运行时必炸,同款坑 4 处全改 `Map<String,dynamic>.from(e as Map)`;新增 Hive 往返回归测试
- 追问头像按消息模型:_FollowUpMessage 加 model 字段,气泡头像+模型名小标签,暂存/历史持久化

### v1.2.3 — .part 改 .apk 命名(2026-08-04,commit 11db7ed)
- v1.2.1 并发竞速把下载文件命名为 `.part`,PackageInstaller 按扩展名判断,非 .apk **静默拒绝**;胜出后 rename .apk

### v1.2.2 — 追问头像跟随槽位 + 暂存入口移入返回弹窗 + 恢复会话空白页(2026-08-04,commit dde45a1)
- 追问头像双根因:头像写死主槽位 `_currentModel` + 抽屉独立路由不重建 → _aiAvatar 参数化 + _followUpSlotNotifier(ValueNotifier)驱动
- 恢复会话空白页:读 camelCase `photoPath` 但 Vocabulary 写 snake_case `photo_path` → 兼容两种 + 图片空时占位"图片副本已丢失"

### v1.2.1 — 开源 + 下载并发竞速(2026-08-04,commit 4a69316)
- 仓库转公开,LICENSE = AGPL-3.0(防闭源白嫖,作者保留商业化);README 加开源说明
- 6 个 2026-03 实测镜像并发下载,首个完成者胜出取消其余,120s 总预算

### v1.2.0 — 人工实测 5 问题修复(2026-08-04,commit efcf4eb)
1. 模型列表混入无关模型 → fetchModels 按前缀过滤(主=doubao 系/副=deepseek 系),失败回退内置
2. 裁剪闪退 → Manifest 补 UCropActivity + Ucrop.CropTheme(values + values-v35 处理 Android 15)
3. 追问无法切主/副 → `'secondary:'` 10 字符误用 substring(11) 吃掉首字母 + 副未配置时分组禁用引导
4. 回译一直"正在生成" → receiveTimeout 600s 收紧 180s + 错误显示;Article 模型无翻译字段 → DB v5 加 translation 列,reader 对照渲染
5. 无暂存会话 → saved_session.dart 快照(结果+全文翻译+追问)+ process_chat 恢复模式 + 图片复制 documents/sessions/<id>/ + "继续上次会话"入口(≤5 条)

### v1.1.0 — 主/副 API 槽位 + 真实评分 + 历史子分类(2026-08-04,commit e4e1530)
- 主/副槽位(用户指定分工:主=多模态,副=专项文本);Hive key 复用 doubao→主/deepseek→副,零迁移
- 练习真实评分:DB v4 reference_answers 列,词集合重叠率;旧练习保留长度启发式
- DeepSeek chat/reasoner 2026-07-24 停用 → 默认 deepseek-v4-flash;两槽位支持 /models

## 验证目标(当前版 v1.2.26)
- [x] flutter analyze 0 error(21 存量 info 零新增)/ 77 测试全绿(+12 例句标粗匹配)
- [x] **真机**:例句限行 3 行+展开/收起;出处句中目标词标粗(详细模式/词详情/词库详情三处)— 用户 2026-08-10 验收通过
- [x] **真机**:文章页 AppBar ⋮ 菜单 → 复制全文翻译(剪贴板)、保存/分享翻译(系统分享面板)— 用户 2026-08-10 验收通过
- [x] **真机**:拆分后全流程回归——识别/追问/保存会话/恢复会话/模型头像切槽位 — 用户 2026-08-10 验收通过

## 当前任务 / 待办(v1.3.0)
- [ ] 用户确认设计(问题 2 触发方式 / 问题 3 入口位置两个选择)
- [ ] 阶段 1 曳光弹:主槽位解绑豆包(问题 0)+ 追问思考档位独立(问题 1)+ 追问上下文携带(问题 5)→ 真机/接口验证通过
- [ ] 阶段 2 核心:AI 补全(问题 2)+ 二次识别(问题 3)+ 消息编辑(问题 4)
- [ ] 阶段 3 打磨:错误处理/加载态/降级链路
- [ ] 发布:bump pubspec v1.3.0 + aapt 验证 versionName + 全量测试 + Release(先 build 完成再 gh release create)

## Backlog
- [ ] 成就徽章系统 / 词汇量测试 / Material You 动态主题(研究期已列,未排期)
- [~] process_chat 剩余大头拆分(追问面板 UI/AI 区/底部栏 ~1500 行,强依赖 State 需建回调接口)— v1.2.26 安全拆已完成 582 行,二期单独评估
- [x] 全文翻译结果可复制/保存 — **v1.2.26 完成**(复制+系统分享面板)
- [x] 例句框精简 — **v1.2.26 完成**(限行 3 行+展开+出处词标粗)
- [~] 模型列表拉取时区分"已开通"状态 — v1.2.0 已按模型族过滤;方舟"已开通"精确语义仍待查
- [ ] 腾讯云 COS 主源发布(用户开通中,需 bucket 访问域名)→ update_service 改 COS,镜像退兜底

## 已完成
- [x] 2026-08-03 全项目代码审查(报告含 11 项综合 + 10 项 UX 发现)— 双维度
- [x] 2026-08-07 v1.2.9→v1.2.14 全部提交 + Release(v1.2.11 未单独发,并入 v1.2.12)
- [x] 自动更新链路修复链:1.2.3 .part→.apk → 1.2.5 FileProvider authority → 1.2.9 REQUEST_INSTALL_PACKAGES(**等待真机端到端确认**)

## 决策记录
- 2026-08-XX v1.3.0 问题2 手动加词 AI 补全=**手动点「✨ AI 补全」按钮**(用户拍板,非保存自动)— 不耗 token 不等待,回填表单可改
- 2026-08-XX v1.3.0 问题3 二次识别入口=**AppBar 右上角图标**(用户拍板,非底部 UI、非列表区)— 与全选/详细切换并列
- 2026-08-XX v1.3.0 追问思考档位**独立存储**(keyFollowUpThinking,4 档)— v1.2.17 只砍识图,追问档位不该连坐;识图维持 2 档
- 2026-08-XX v1.3.0 问题 5 追问携带识别结果=**词汇+全文翻译段落+图片(data URI)**,图片被拒自动降级纯文本 — AI 真正"看到"页面,旧文本模型不崩
- 2026-08-10 例句精简=限行 3 行+展开(方案1)+ 出处词标粗(用户追加)— 冗长例句压缩列表高度,词条仍完整可读;标粗匹配保守(找不到/变形不标,绝不改变例句内容)
- 2026-08-10 process_chat 拆分=安全拆(用户确认):只搬零/低依赖模块,强依赖 State 的追问面板/气泡/AI 区留待二期单独评估 — 用户铁律"不要越改bug越多",纯搬移行为零变化
- 2026-08-10 全文翻译保存=自写原生 share_text 通道(ACTION_SEND),不用 share_plus — 零新依赖;open_filex 已因挂起 bug 弃用,不可复用
- 2026-08-03 主/副 API 角色分工(主=多模态,副=专项文本,副未配置全走主)— 用户指定;识别与生成解耦
- 2026-08-03 追问槽位独立记录 keyFollowUpSlot — 追问是识图上下文问答,模型自由
- 2026-08-03 复用现有 Hive key 不迁移 — 老配置自动成为主/副
- 2026-08-03 新练习评分=词集合重叠率,旧练习保留长度启发式 — 无法从现有数据恢复英文原文
- 2026-08-04 仓库转公开 + AGPL-3.0 — 镜像下载国内可用;核心提示词未来可抽私有包(已评估剽窃风险)
- 2026-08-07 识图思考策略演进:v1.2.11 禁用(被否定)→ v1.2.12 恢复+超时自动降级(治本)— 豆包视觉思考速度服务端不可控,禁用是回避问题
- 2026-08-07 v1.2.13 起思考档位首字节超时 20/25/30s + reasoning 超时 10/15/30s 双路兜底 — 补豆包连 reasoning 都不吐的盲区

## 坑与教训
- **🚨 2026-08-07 实测实锤:budget_tokens 对豆包完全无效**(决定性问题,三轮修复未根治的根源):同图同 prompt 实测 doubao-seed-2-0-lite-260428——disabled 3.7s / enabled+budget512 29.3s / enabled+budget2048 36.7s / enabled无budget 27.7s / 不传thinking(默认深度思考)61.8s。reasoning 长度不随预算走(334/615/494),**"低/中/高"档位是假的,服务端按默认深度思考**。auto 参数 400 不支持。第二轮(reasoning_effort minimal/low/high)待测
- **豆包视觉模型默认开启深度思考**(官方文档):不传 thinking = 61.8s 深度思考。App 识图 prompt "简洁思考" 可能被模型理解为"输出简洁"→ word 字段可能自带 "…" 截断(截图实锤:同一屏一个句子完整、一个 "Because reality is n…" 截断,渲染层 v1.2.14 已放开,数据层问题,待实测确认)
- **豆包视觉模型思考时间服务端不可控,budget_tokens 对它无效** — 参数微调全是徒劳,靠超时降级兜底;思考是"服务端行为"不是"可配置行为"(第一轮实测更新:不是不可控,是**控制参数不对**)
- DeepSeek chat/reasoner 2026-07-24 停用 → 模型 ID 必须跟随官方 changelog
- 豆包/DS 思考参数格式不同(豆包 reasoning_effort low/medium,DS low/high/max)→ 槽位化后按端点格式构建
- 自动更新四层坑:.part 扩展名 → FileProvider authority(camelCase 硬编码)→ open_filex 挂起 → **缺 REQUEST_INSTALL_PACKAGES 权限**(终极根因)。**真机端到端验证是唯一标准,代码推断不算数**
- Hive 读回嵌套 Map 是 `_Map<dynamic,dynamic>`,`as Map<String,dynamic>` 必炸 → 用 Map.from 重建
- 临时文件命名别用系统组件靠扩展名识别的场景(PackageInstaller 按 .apk 判断)
- 插件硬编码配置(open_filex authority)须与 Manifest 逐字核对
- **🚨 2026-09-22 单测造流用错类型 → 真机流式全挂(v1.9.0→v1.9.1)**:`utf8.decoder` 是 `StreamTransformer<List<int>, String>`,而 dio 的 `ResponseBody.stream` 运行时是 `Stream<Uint8List>`;`stream.transform(utf8.decoder)` 会在**运行时**抛 `type 'Utf8Decoder' is not a subtype of type 'StreamTransformer<Uint8List, String>'`(编译期查不出来,因为声明类型是 `Stream<List<int>>`)。**修法:`stream.cast<List<int>>()` 再 transform。** 单测当时用 `Stream<List<int>>.fromIterable` 造流 → 接收者类型参数是 `List<int>` → 检查通过 → 缺陷被"测绿"。**教训:凡是测流/字节管道,造流必须用与生产一致的运行时类型(`StreamController<Uint8List>`),否则等于没测。**
- **🚨 2026-09-21 血的教训:别用脚本做批量字符串替换。** 为把 60 处灰阶正文色收敛到 AA,用 pwsh 写了个 `[System.IO.File]::ReadAllText / Replace / WriteAllText` 的批量替换,数组构造写错导致替换对变成了单字符 `'s'→'t'`,**一次把 4 个源文件的每个 s 都改成了 t**(process_chat.dart 122KB、my_materials_section.dart、vocab_list.dart、writing_logs_screen.dart 全毁)。救援路径记下来备用:
  1. **`app.dill` 里有完整源码文本**。Flutter 构建产物 `.dart_tool/flutter_build/<hash>/app.dill`(kernel)内嵌了每个源文件的**原文**(注释都在),因为损坏是"每个 s→t"这种长度不变的双射,可以先用正则 `escape(损坏内容前 200 字) + t→[st]` 定位,再按**原始字符数**切出候选、用 `候选.Replace('s','t') == 损坏内容` 逐字节验证,1:1 还原(本次 4 个文件全部 VERIFIED 后还原成功,analyze 回到 24 infos 基线)。
  2. 前提是**损坏前刚跑过 build/test**;所以改代码后跑一次 `flutter analyze`/`build` 同时也是给自己留了份"可反解的编译快照"。
  3. 真要做批量替换,必须用 `edit` 工具(带确切 old/new 字面量),或者替换前 `git add` 一次留个 index 快照。
- **🚨 2026-09-22 同类事故第二次:别用 PowerShell 管道读写源码文件。** 为了把一个方法改名,用了 `Get-Content | -replace | Set-Content -Encoding UTF8` —— Windows PowerShell 5.1 的 `Get-Content` 对**无 BOM 的 UTF-8** 文件按系统 ANSI(中文机是 GBK)解码,于是整个文件的中文注释/字符串变成乱码,并因乱码里的引号把字符串字面量截断 → analyzer 一次报 525 个错。救援:该文件是**未提交的新文件**,直接用 `write` 工具按内容重写(凡是走 PowerShell 管道改过的源码,都要假设中文已损坏并复核)。**结论:改代码只用 `read`/`edit`/`write` 工具;PowerShell 只用来跑命令与查状态。**

## v1.2.15 — 思考参数根治(budget_tokens→reasoning_effort)+ 新 logo(2026-08-07)

**背景**:v1.2.14 用户实测两问题①思考模式时间依然非常长②词汇短语/句子显示省略号。

**实测验证(决定性,6+5+4+3 组真实 API 请求,doubao-seed-2-0-lite-260428 同图同 prompt)**:
- `thinking.budget_tokens` **完全无效**:512/1024/2048 耗时 27-37s 无差别,reasoning 长度不随预算(334/615/494)
- **不传 thinking = 默认深度思考 61.8s**(官方文档"默认开启深度思考"实锤)
- `reasoning_effort` **真实生效**:disabled 3.7s / minimal 2.9s / low 14s(复杂图)/ medium 25.1s / high 26.7s;书本照片场景 disabled 3.2s / minimal 4.5s / low 8.4s
- **省略号根因**:模型忠实识别输入文本——旧版 UI(maxLines:1)截断后的文本被拍照/识别 → word 字段带 "…"。书本照片输入时思考模式输出**无省略号**(旧 prompt 全档位验证)。新版渲染已放开(v1.2.10/13)+ 数据层无省略号 → 理论上新版拍照无此问题,待用户真机复核
- auto 参数 400 不支持;medium 档确认支持

**修复**(commit 待):
- api_endpoint.dart:budget_tokens → reasoning_effort,档位映射(用户决策"整体提速档")低→minimal/中→low/高→medium;副槽位 DS 不认 reasoning_effort 时 postWithReasoningFallback 自动移除降级(已有链路)
- constants.dart:思考文案按新映射实测更新(低·约3s/中·约15s/高·约25s)
- process_chat.dart:reasoning 超时阈值适配(低10s/中20s/高30s,防 low 档 13.6s 出 content 被误降级)
- 新增 test/thinking_params_test.dart(映射回归 6 用例)
- 验证:analyze 0 error / 40 测试全绿+1 skip
- 新 logo:用户定稿图(蓝发女仆举 language AI 书,1324px)直接缩放替换 5 密度(用户明确:图是反复改好的成品,不做任何处理)
- 构建:arm64 瘦身版;发布待用户确认

**省略号真正根因(2026-08-07 晚,用户 v1.2.14 实测截图逐字读出)**:
- 22:21 截图:phrase word="simply the recycling…" / sentence word="This has never bee…",**但 originalSentence 字段完整**("More often than not, what's mistaken for originality is simply the recycling of a forgotten influence.")
- **模型把 phrase/sentence 的 word 字段"词条化"**(输出开头 ~20 字符+"…"),originalSentence 才输出完整句子——与 UI 无关、与思考模式无关、与 71 字符硬限制(单行大字图测试)无关
- 实测链条:prompt 强制完整/思考模式/max_tokens/detail high/换模型(2-1-turbo/2-0-pro)都无法让 word 完整(词条化是模型输出策略);originalSentence 一直是完整的
- **修复(显示层回退)**:word 以省略号结尾且存在更长的 originalSentence → 显示 originalSentence(详细模式 _displayWord + 总览 WordListTile 同逻辑)
- 用户线索关键提示:"近几次词汇板块 UI 调整后就这样"+"原来正常"——但代码审查确认 UI 一直放开;数据层词条化是模型近端行为(v1.2.10 时代用户就反馈过截断,当时误判为 UI)

## v1.8.0 — 思考不再被砍 / 重新识别合并 / 复习修复 / 页码智能 / AI 推荐可用(2026-09-15)

**用户实测 8 条**

**① 思考模式被强行砍成"不思考"(根因两条)**
- 根因 A:请求写死 `max_tokens: 8192`(思考+正文总预算)→ 思考吃光预算,content 为空
  → **DS 请求不再发 max_tokens**(与官方/dsh 一致,交服务端默认);豆包仍显式限制
- 根因 B:检测 reasoning-only 就自动切不思考 → 改为:
  1) 先 `extractJsonBlock(reasoning)` 从思考通道取 JSON 直接用
  2) 仍无结果 → **同档位**重试一次(`_reasoningOnlyRetried` 守卫)
  3) 再失败 → 报错并附思考原文,档位保持用户所选(绝不偷偷降级)
- 追问抽屉:思考通道有答案就直接当回答展示
- 截断重试也从"降级不思考"改成"同档位重试一次"(`_truncationRetried`)

**② 识图「重新识别」合并**:删掉 校准/补漏 二选一,单一动作(逐行扫描+高清+自检),整组替换但保留手动补充的词(弹窗写明条数)

**③ 复习模式**:认识 → 直接下一张;仅不认识/模糊翻面看释义;修「同一词反复点认识刷进度」(重复同档忽略 + 改标记先撤销旧计数)

**④ 页码智能 + 可改**:`lib/utils/page_label.dart`(`p9页/第9页/9/PP9页→p9`,`9~12→p9-12`,`p16 p17→p16-17`,非数字原样);DB v9 迁移归一历史数据;材料页书/材料文件夹可重命名(`renameBookPath`),页码分组可改(`updateSourcePageByIds`)

**⑤ 数量对不上**:分类详情默认 `limit=100` → 改 5000,标题与实际一致

**⑥ 「其他输入材料」做成可用功能**
- `LearnerProfile`(水平/目的/偏好/补充,Hive 持久化,可编辑)+ `suggestFromVocab` 按真实词汇量/来源推断
- `MaterialRecommendService`(纯函数:推荐 system/user 提示词、`parseRecommendations`、`vocabFingerprint`)
- DB v9 新表 `recommendations`;推荐清单与学习内容都落库缓存,不再每次重算
- 新页面:`learner_profile_screen.dart`(画像编辑)、重写 `ai_material_search.dart`(流式推荐+缓存列表)、`material_recommendation_detail_screen.dart`(流式精读内容:选段/导读/重点词/用法;可存为文章、收藏、追问)
- API 新增通用流式 `streamPrompt(system,user)`

**⑦ 「AI 生成文章」迁到输入页** → `widgets/ai_article_section.dart`「特色功能 · AI 生词定制文章」;输出页精简为 写译批改/写译记录(`output_home.dart` 重写)

**⑧ 识图选中模式单击即选中**:平铺/分组/详细三种卡片 onTap 都先判 `_selected.isNotEmpty` → 切换选中;底部提示随模式变化

**验证**:analyze 0/0;176 测试全绿(+1 skip,新增 16 条);aapt versionCode=48/versionName=1.8.0;Release v1.8.0 = Latest
**同步**:`$env:RF_DIFF_BASE='451b1db'`(v1.7.0 本地提交,其 tree 与远端一致)后跑 `tool/push_via_api.ps1`

## v1.7.0 — 极致思考修复 / 识别校准 / 复习模式重做 / UI 瘦身(2026-08-26)

**用户实测 4 组问题**

**① 思考强度「极致」点了变成不思考(根因修复)**
- 根因:`ApiEndpointConfig.thinking` 只放行 `low/disabled`,DS 官方 `high/max` 被末尾兜底打回 disabled
- 修复:档位合法性统一由 `AppConstants.thinkingOptionsFor(model)` 判定;表内原样生效,表外旧值(豆包 medium/high→low、minimal→disabled)迁移写回
- 追问档位新增 `followUpThinkingOptionsFor(model)`(DS = disabled/low/high/max,无 medium)
- 页头/设置页档位显示改取配置层已校验值(`_currentThinking`),UI 与请求行为一致
- **踩坑**:getter 曾在读路径上无条件写 Hive(null 也写)→ 触发 Hive 监听重建 → build 中无限重建 → `restore_session_test` 挂死 10 分钟。修复:只对"确实存过的旧档位"写回

**② 识图「重新识别」不真实(只有补充)**
- AppBar 拆成「识别质量」菜单两个入口:
  - **重新识别(校准)**:逐行扫描 + 标记类型清单 + 输出前自检 + 高清图(`detail:'high'`),结果**整组替换**(先弹确认)
  - **补充识别(只补漏)**:保留现有结果,只并入遗漏项
- `extractVocabularyStream(calibrate: true)` → `_buildRequestBody` 走校准提示词;首次识别提示词同步加强(标记类型枚举 + 先扫标记再读字 + 同处不重复)

**③ 复习模式 5 项**
1. 标记后自动翻面显示释义(不再直接跳过),看完点「下一张」
2. 左右滑动 + ⬅➡ 按钮前后翻卡,回看显示当时标记结果
3. 顶部筛选 chip/进度文字改深色加粗、进度条主题色
4. 新增日期筛选(今天/近3天/近一周/近一月)+ 卡片显示「保存于 …」(`Vocabulary.createdLabel`,生词本卡片同显)
5. 进度持久化(Hive `review_progress`):退出再进提示「上次复习到第 X 张」→ 继续/重新开始;卡组顺序与标记统计一起存
- 新增 `lib/utils/review_deck.dart`(纯函数:`filterReviewItems` / `ReviewProgress` / `restoreDeck`)

**④ 写译批改 UI**
- 手写稿改固定高度横向缩略图条(可滑、点击全屏查看 + 双指缩放);文本框固定高度内部滚动 → 长文不再撑破页面/卡住滚动
- 删除多余灰色说明文案(流程 ①②③、"批改返回:…"、"可一次选多张…" 等),并全局精简输入页/我的/分类弹窗/写译记录等处啰嗦副标题

**验证**:analyze 0/0;160 测试全绿(+1 skip,新增 15 条);arm64 aapt versionCode=47/versionName=1.7.0;Release v1.7.0 = Latest
**同步**:`$env:RF_DIFF_BASE='aa43675'`(v1.6.0 本地提交,其 tree 与远端一致)后跑 `tool/push_via_api.ps1`

## v1.6.0 — 写译批改重构 + 书籍分组修复 + 写译日志(2026-08-26)

**用户反馈(三条)**:①写译批改该在输出页、太简陋(交互/分类混乱、不能多图)②书籍子分类仍按页分裂③批改要有追问抽屉(收藏/选模型)、AI 末尾按词汇/语法/表达优化/其他汇总、可保存练习日志按日期归档复盘

**① 写译批改重做**(`lib/screens/writing/write_review_screen.dart`)
- 入口从「输入」页搬到「输出」页(输出页顶部两个入口:写译批改 / 写译记录)
- 进页先选材料类型:**手写档**(可一次多张,拍照/相册多选,≤9 张)或**电子档**(直接粘贴)
- 手写档:上传 → 「识别为电子档」(`transcribeWriting(List<File>)` 多图一次转写合并)→ 文本可改 → 批改
- 结果:分数 + 总评 + **错误分类汇总(词汇/语法/表达优化/其他)** + 逐条点评 + 修正后全文 + 我的原文
- 追问抽屉:复用与识图页**同一套** `FollowUpController`(收藏星标、主/副槽位模型、思考档、上下楼记忆、编辑重发、历史对话);上下文自动带原文+批改结果

**② 书籍分组修复**
- 新增 `lib/utils/material_group.dart`(纯函数,可单测):书籍 = 一本书一个文件夹,页/章为二级子分类;页码按数字排序;未标页码单独归类
- DB v8 迁移:旧数据 `书籍/《X》/p16 p17` → `material_path='书籍/《X》'` + `source_page='p16 p17'`(同一本书不再按页分裂)
- `my_materials_section.dart` 分类弹窗改为两级展开

**③ 写译练习日志**
- DB v8 新表 `writing_logs` + `WritingLog` 模型(原文/修正/分数/评语/逐条点评/四类汇总/原稿图/模型/时间)
- 批改完成弹「是否保存此次写译练习」;`writing_logs_screen.dart` 按日期文件夹归档,详情可看全部内容,可删除

**内部重构**:追问逻辑从 process_chat 抽成 `lib/screens/input/widgets/follow_up_drawer.dart`(`FollowUpController` + `showFollowUpDrawer` + `CompactModelPicker`),识图页与写译页共用一份实现(process_chat 净减约 700 行)

**验证**:analyze 0 error/0 warning;145 测试全绿(+1 skip,新增 11 条);arm64 release aapt versionCode=46/versionName=1.6.0;Release v1.6.0 = Latest

**踩坑**:Gradle 本次构建耗时 26 分钟(网络导致依赖下载慢),不是卡死——等待即可;同步远端仍需 `tool/push_via_api.ps1`(github.com 被 fake-IP 劫持),用法:`$env:RF_DIFF_BASE='<tree 与远端一致的本地提交>'; powershell -File tool\push_via_api.ps1`

## v1.5.0 — 音标+系统TTS发音(#4) / 复习模式(#5) / 写译批改(2026-08-26)

**范围**(用户拍板节奏:先修复版再新功能;发音=系统TTS+音标;输出=先写译批改)

**#4 音标 + 系统 TTS 发音**
- DB v7:vocabulary 新增 `phonetic` 列(迁移 + Vocabulary 模型字段 + toMap/fromMap/copyWith)
- 音标来源:识别 prompt 新增可选 `phonetic` 字段 + `completeWordInfo`/`parseWordInfo` 新增 phonetic + 手动添加/编辑表单新增「音标」输入
- 朗读:新增 `lib/services/tts_service.dart`(flutter_tts 懒初始化,en-US,失败静默返回 false → 界面提示「设备未找到可用语音引擎」)
- 入口:词列表小喇叭(WordListTile.onSpeak)、词详情页点单词本体/喇叭按钮、生词本卡片喇叭、生词详情页点词/喇叭

**#5 复习模式**(我的 → 复习模式,`lib/screens/review/review_screen.dart`)
- 抽认卡:看词想义 → 轻点翻面核对(释义/例句/语法) → 底部三档标记(不认识/模糊/认识 → mastery 0/1/2 实时写库)
- 筛选(全部/新词/学习中/已掌握)+ 打乱重来 + 进度条 + 本轮统计小结 + 再来一轮
- 只收「有释义」的条目(没释义的卡片无法"想义")

**写译批改**(输入页 → 写译批改,`lib/screens/writing/write_review_screen.dart`)
- 手写英文拍照/相册 → 「识别文本」(`transcribeWriting`,主槽位视觉,思考 disabled)→ 文本框可编辑确认 → 「AI 批改」
- 批改(`reviewWriting`,优先副槽位,未配置用主槽位)→ 分数 + 修正后全文 + 逐条点评(语法/拼写/用词/搭配/标点/自然度)+ 总体评语 + 「我的原文」对照
- 解析失败自诊断:把 AI 原文前 400 字带进错误页

**其他**:软件图标换成用户新定稿 AI language 图标(5 密度);`tool/push_via_api.ps1`(网络阻断时用 GitHub API 同步提交的应急脚本)

**验证**:analyze 0 error/0 warning(24 条历史 info);134 测试全绿(+1 skip);arm64 release 构建 aapt 验证 versionCode=45 versionName=1.5.0;GitHub Release v1.5.0 = Latest,资产 app-release.apk

**踩坑(重要)**:
- 本机 github.com 被网络层劫持到 fake-IP(198.18.0.84,TUN/代理节点失效)→ `git push` schannel/openssl 全部握手失败;api.github.com 正常
- 应急方案:GitHub REST git API(blobs→trees→commits→refs)按本地对象逐层重建提交;**远端 master 原停在 v1.2.1(4a693160)**——此前多个版本的 git push 一直没成功(Release 走 API 所以正常)
- PS 5.1 三坑:①UTF-8 无 BOM 的 .ps1 会因中文乱码解析失败(必须写 BOM)②`gh --jq` 多行输出在 PS 里是数组,`"$out"` 会按空格拼成一行(必须 `-join "`n"`)③`git/commits/<sha>` API 只认 40 位完整 SHA
- 重建树时必须把「新增目录」作为条目插进父树(review/writing/tool 三个新目录曾整目录丢失);删除的文件要从树里丢弃;最后用 `git rev-parse HEAD^{tree}` 与 API 返回的根树 SHA 比对一致才提交

**断点(2026-08-26 收尾)**:远端 master = 5c206a4,内容与本地 HEAD 树 SHA 完全一致(6a2c7ed0);本地保留完整历史,网络恢复后 `git push --force origin master` 即可把完整提交历史补回远端(并带上 PLAN.md 本次更新)

## 断点快照(2026-08-26 收尾)
- 正在做:**v1.5.0 已发布(Release = Latest),等用户真机验收**——#4 音标+朗读、#5 复习模式、写译批改、新图标
- 验收清单(重点):①生词列表/详情出现音标(识别 prompt 已要求返回,老词可编辑补充)②点小喇叭/点单词本体能朗读(无引擎会提示)③我的→复习模式:抽认卡翻面 + 三档标记后进度推进,标记后回生词本掌握度同步④输入页→写译批改:拍手写英文→识别→可改文本→批改出分数/修正全文/逐条点评⑤新图标是否已生效(桌面图标可能需重装/重启桌面)
- 环境备忘:**本会话跑 flutter 命令必须 `FLUTTER_ALREADY_LOCKED=true` + 全盘权限(danger-full-access)**,否则 D:\flutter lockfile CreateFile failed 5 挂死
- 网络备忘:**github.com 被劫持到 fake-IP 198.18.0.84,git push 不通;api.github.com 通** → 用 `tool/push_via_api.ps1` 经 API 同步(脚本须存为 UTF-8 BOM)
- 备注:auto 更新链路真机跑通 ✓;gh release create/upload 本会话直跑成功;PLAN.md 编辑注意版本标题完整性
