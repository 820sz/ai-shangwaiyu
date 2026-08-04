# PLAN.md — AI上外语 (readflow)

## 状态
- 当前阶段:🟣 审查完成 → 🔵 编码(本轮修复 5 项)
- 状态协议:NEEDS_CONTEXT(设计待确认)
- 时间盒:未设定(用户要求:全部问题查完解决,新功能后续再说)

## 需求摘要
**项目**:AI上外语(Flutter 英语学习 App,D:\readflow)
**一句话**:拍照识词→生词归档→AI 文章→回译练习的个人英语学习闭环
**用户**:自己 + 几个朋友(Android)

**本轮范围(5 项,均已确认)**:
- [ ] A1 回译练习英文参考答案入库,真实评分(现为中文占位假评分)
- [ ] A2 "我的"页"已完成练习"真实统计(现硬编码 0)
- [ ] B1 子分类记忆:保存生词时可选已建过的子分类,不必重填
- [ ] B2 主/副 API 重构:主=多模态(识图/翻译/推荐),副=专项文本(文章/回译/建议);副未配置→全部走主;追问可选主/副模型
- [ ] B3 模型列表更新:DeepSeek 默认 `deepseek-v4-flash`(chat/reasoner 已停用),两槽位都支持拉取 /models,推荐模型排序

## 设计笔记(2026-08-03)
**背景**:全项目审查发现 3 个正确性 bug + 用户实测 3 个问题,且 DeepSeek 旧模型 ID 已停用导致文本功能全挂。

**目标**:
- [ ] 练习评分有真实依据,统计数字可信
- [ ] 子分类保存可复用历史
- [ ] API 配置解绑厂商名,主/副职责清晰,模型列表与账号开通一致
- [ ] 所有改动通过 flutter analyze + 关键逻辑单测

**不做(non-goals)**:
- [ ] 不做真机回归验证(用户后续自己装 APK 验证)
- [ ] 不做新功能(成就系统/推荐引擎等进 backlog)
- [ ] 不迁移既有 Hive 配置数据(主/副槽位复用现有 keyDoubao*/keyDeepseek* key,老配置自动就位)

**方案**:
- 主/副槽位:Hive key 复用现有 doubao→主、deepseek→副,不迁移数据;新增 keyDeepseekThinking(默认 disabled)
- 服务层:抽 ApiEndpointConfig(4 字段读取)+ 共享 HTTP 工具(_dio 缓存/_extractContent/reasoning fallback);MultimodalApiService(原 doubao)读主槽位;TextApiService(原 deepseek)读副槽位,副未配置 fallback 主槽位;MaterialSearchService 读主槽位
- 追问槽位:新增 Hive keyFollowUpSlot('primary'/'secondary'),选择器双分组(主模型+副模型),followUpStream 按槽位取端点
- 模型列表:副槽位内置 ['deepseek-v4-flash','deepseek-v4-pro'],打开选择器时 GET {baseUrl}/models 拉取,失败用内置;主槽位拉取结果按内置推荐顺序重排
- A1:DB v4 加 reference_answers 列;评分改词集合重叠率;旧练习(无参考)→ 保留长度启发式
- A2:getTotalExerciseCount() 统计 score 非空练习数
- B1:getMaterialPathsByCategory(category) 查 DISTINCT material_path,子分类弹窗顶部加历史 ChoiceChip 点选区

**被否掉的方案**:
- 只改设置页标签(API1/API2)不角色化 — 追问仍无法选副模型,且降级逻辑无法表达
- 单一 API 槽位 — 识图与文本模型通常不同,用户明确要两个

## 验证目标(本轮)
- [ ] 当用户只填主 API 时,识图/文章/回译/建议全部可用
- [ ] 当用户填副 API(DS v4)时,文章生成用副槽位且成功;识图仍走主
- [ ] 追问选择器显示"主/副"两组模型,选副后追问走副 API
- [ ] 保存生词时,子分类弹窗显示该分类历史子分类,点选即填
- [ ] 练习提交后得分基于英文参考;旧练习不崩
- [ ] "我的"页练习计数 = 已评分的练习数
- [ ] flutter analyze 0 error 0 warning(存量除外)

## 当前任务(编码顺序,依赖从小到大)
- [x] 1. 全项目审查出报告(42 文件)
- [x] 2. B3-1:constants 默认模型改 deepseek-v4-flash + 副槽位内置列表
- [x] 3. A2:数据库查询 + stats_provider + profile_home 显示
- [x] 4. A1:DB v4 迁移 + Exercise 模型 + provider + exercise_screen
- [x] 5. B1:数据库查询 + sub_category_input 历史点选
- [x] 6. B2:ApiEndpointConfig + BaseApiService 抽取 + 设置页主/副 + 追问双槽位选择器 + 评分抽 utils/scoring.dart
- [x] 7. 验证:flutter analyze 0 error / 0 warning,23 个单测全绿(模板 widget_test 改为轻量冒烟测试)
- [x] 8. flutter build apk --release --target-platform android-arm64(20.1MB 瘦身版)
- [x] 9. git commit e4e1530 + 发 v1.1.0 Release(gh release create 成功,APK 已上传)

## v1.2.0 人工实测 5 问题修复(2026-08-04 白天)
用户装 1.1.2 实测出 5 个问题,全部定位根因并修复(代码完成,APK 构建中):
1. **模型列表混入无关模型**:方舟聚合端点 /models 返回混合模型。fetchModels 加按前缀过滤(主槽位 doubao 系列/副槽位 deepseek 系列),过滤空回退全列表,拉取失败回退内置清单
2. **裁剪闪退**:AndroidManifest 缺 UCropActivity 声明(image_cropper 官方要求手动声明)→ 补齐 activity + Ucrop.CropTheme 主题(values + values-v35 处理 Android 15 edge-to-edge)
3. **追问抽屉无法切主/副**:两个根因——(a) `'secondary:'` 是 10 字符但用 substring(11) 截断吃掉模型名首字母 → 修正;(b) 副 API 未配置时菜单无副分组 → 分组始终显示,未配置时禁用并引导去设置页
4. **回译练习"一直正在生成" + 显示翻译无反应**:(a) article_reader 从不显示 provider.error + sentences 为空时无提示 + receiveTimeout 600s 太长 → 加错误显示、空结果设 error、超时收紧 180s;(b) Article 模型根本没有翻译数据,_showTranslation 空转 → DB v5 articles 加 translation 列,生成 prompt 要求同步返回逐段中文翻译,reader 对照渲染;旧文章无翻译时按钮提示"删除后重新生成"
5. **无暂存会话能力**:新建 models/saved_session.dart(结果+全文翻译+追问消息快照),process_chat 加"暂存"按钮(AppBar 结果态)+ 恢复模式(restoreSession 参数,跳过识别直接还原,追问消息原样进抽屉),图片复制到 documents/sessions/<id>/ 持久化;输入页"继续上次会话"入口(最多 5 条,可删除)
- 交互保证:恢复会话后追问抽屉消息不消失(会话快照含追问);保存单词流程复用;照片副本丢失时 photoPath 置 null 不崩
- 验证:flutter analyze 0 error / 23 单测全绿(含 dbVersion==5 冒烟)
- 待办:APK 构建后发 v1.2.0 Release(含 v1.1.2 未提交的公开化改动)

## 断点快照(2026-08-04 白天)
- 正在做:v1.2.0 构建 + 发布
- 卡在哪:无
- 下一步:构建完成后 `cd D:\readflow && git add -A && git commit -m "fix: 5项实测问题(模型过滤/裁剪闪退/追问切换/练习反馈/会话暂存)" && gh release create v1.2.0 build/app/outputs/flutter-apk/app-release.apk --title "v1.2.0" --notes "..."`

## v1.1.x 补充记录(更新下载修复)
- v1.1.0:5 项功能修复(e4e1530)
- v1.1.1:下载超时修复(20s 连接/30s 接收),私有仓库不再空转镜像
- v1.1.2:仓库转公开(用户确认)+ 移除 PAT + downloadApk 镜像优先 → 直连兜底;APK 已构建(20.1MB)并复制到桌面
- 决策记录补充:2026-08-04 仓库转公开 — 理由:镜像下载国内可用;PAT 已移除;核心提示词未来可抽私有包(用户担心创意剽窃,已评估风险后选择公开)

## Backlog
- [ ] 成就徽章系统 / 词汇量测试 / Material You 动态主题(研究期已列,未排期)
- [ ] process_chat 2359 行拆分 5-6 文件(审查建议)
- [ ] 全文翻译结果可复制/保存(审查发现的功能缺口)
- [~] 模型列表拉取时区分"已开通"状态 — v1.2.0 已按模型族过滤(不弹无关模型);方舟"已开通"精确语义仍待查

## 已完成
- [x] 2026-08-03 全项目代码审查(报告含 11 项综合 + 10 项 UX 发现)— 双维度
- [x] 2026-08-03 核实:仓库 820sz/ai-shangwaiyu 私有,Release v1.0.5,git 干净

## 决策记录
- 2026-08-03 主/副 API 角色分工:主=多模态,副=专项文本,副未配置全走主 — 理由:用户指定;识别与生成解耦
- 2026-08-03 追问槽位独立记录(Hive keyFollowUpSlot)— 理由:追问是识图上下文问答,模型自由
- 2026-08-03 复用现有 Hive key 不迁移数据 — 理由:老配置自动成为主/副,零迁移成本
- 2026-08-03 新练习评分=词集合重叠率,旧练习(无英文参考)保留长度启发式 — 理由:无法从现有数据恢复英文原文

## 坑与教训
- DeepSeek deepseek-chat/deepseek-reasoner 已于 2026-07-24 停用,App 文本功能因此全挂 → 模型 ID 必须跟随官方 changelog,不能假设默认值永续
- 豆包/DS 思考参数格式不同:豆包 reasoning_effort 取值 low/medium(映射),DS 为 low/high/max → 槽位化后按端点格式构建,靠 fallback 降级兜底

## 断点快照
- 正在做:设计已产出,待用户 30 秒确认后开码
- 卡在哪:无
- 下一步:从任务 2(B3-1 模型默认值)开始,每步 flutter analyze 验证
