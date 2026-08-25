# PLAN.md — AI上外语 (readflow)

## 状态
- 当前版本:**v1.3.1**(Release 已发 = Latest,v1.3.0 被 v1.3.1 覆盖)
- 当前阶段:✅ v1.3.1 已发(模型列表过滤+端点防呆),**等用户按正确配置真机验收**
- 状态协议:DONE_WITH_CONCERNS(真机验收未做)

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

### v1.3.1 — 模型列表过滤+端点配对防呆(2026-08-25,构建发布中)
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

## 断点快照(2026-08-25)
- 正在做:**v1.3.0 发布完成,等用户真机验收 6 项**(0 主槽位 DS 视觉 / 1 追问 4 档 / 2 AI 补全 / 3 再识别 / 4 编辑重发 / 5 追问上下文)
- 下一步:用户真机验收 → 有问题按验收清单修,无问题状态转 DONE
- 关键事实:DeepSeek 2026-08-21 上线 `deepseek-v4-flash-vision-exp`(官方视觉 API,OpenAI 兼容);主槽位模型列表过滤是问题 0 根因
- 环境备忘:**本会话跑 flutter 命令必须 `FLUTTER_ALREADY_LOCKED=true` + 全盘权限(danger-full-access)**,否则 D:\flutter lockfile CreateFile failed 5 挂死;构建命令要开梯子;analyze 首跑 ~170s
- 备注:auto 更新链路真机跑通 ✓;发布命令 gh release create/upload 本会话直跑成功,无需用户自跑;gh release create 路径用正斜杠
