# PLAN.md — AI上外语 (readflow)

## 状态
- 当前版本:**v1.2.14**(commit a928006,Release 已发 = Latest,带 app-release.apk)
- 当前阶段:🔵 编码完成 → 待真机验证(v1.2.14 走自动更新,用户核对设置页版本号)
- 状态协议:DONE_WITH_CONCERNS(句子截断疑似旧版本现象 + 思考模式双路降级待排查)

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

## 验证目标(当前版)
- [x] flutter analyze 0 error / 34 测试全绿(v1.2.14)
- [ ] **真机**:用户手机走自动更新到 v1.2.14(或手动装桌面 APK),核对设置页版本号
- [ ] **真机**:句子截断问题在 v1.2.14 上确认消失(疑似旧版本现象)
- [ ] **真机**:思考模式双路降级(纯思考超时)实际触发一次,总耗时可控

## 当前任务 / 待办
- [ ] 等用户真机验证 v1.2.14(自动更新链路 + 句子显示 + 设置页版本号核对)
- [ ] 思考模式双路降级待新会话排查(用户实测仍很长的话)
- [ ] 发布流程补"桌面复制 APK":v1.2.14 起桌面只有 v1.2.13 fat,最新版没复制

## Backlog
- [ ] 成就徽章系统 / 词汇量测试 / Material You 动态主题(研究期已列,未排期)
- [ ] process_chat 2359 行拆分 5-6 文件(审查建议)
- [ ] 全文翻译结果可复制/保存(审查发现的功能缺口)
- [~] 模型列表拉取时区分"已开通"状态 — v1.2.0 已按模型族过滤;方舟"已开通"精确语义仍待查
- [ ] 腾讯云 COS 主源发布(用户开通中,需 bucket 访问域名)→ update_service 改 COS,镜像退兜底

## 已完成
- [x] 2026-08-03 全项目代码审查(报告含 11 项综合 + 10 项 UX 发现)— 双维度
- [x] 2026-08-07 v1.2.9→v1.2.14 全部提交 + Release(v1.2.11 未单独发,并入 v1.2.12)
- [x] 自动更新链路修复链:1.2.3 .part→.apk → 1.2.5 FileProvider authority → 1.2.9 REQUEST_INSTALL_PACKAGES(**等待真机端到端确认**)

## 决策记录
- 2026-08-03 主/副 API 角色分工(主=多模态,副=专项文本,副未配置全走主)— 用户指定;识别与生成解耦
- 2026-08-03 追问槽位独立记录 keyFollowUpSlot — 追问是识图上下文问答,模型自由
- 2026-08-03 复用现有 Hive key 不迁移 — 老配置自动成为主/副
- 2026-08-03 新练习评分=词集合重叠率,旧练习保留长度启发式 — 无法从现有数据恢复英文原文
- 2026-08-04 仓库转公开 + AGPL-3.0 — 镜像下载国内可用;核心提示词未来可抽私有包(已评估剽窃风险)
- 2026-08-07 识图思考策略演进:v1.2.11 禁用(被否定)→ v1.2.12 恢复+超时自动降级(治本)— 豆包视觉思考速度服务端不可控,禁用是回避问题
- 2026-08-07 v1.2.13 起思考档位首字节超时 20/25/30s + reasoning 超时 10/15/30s 双路兜底 — 补豆包连 reasoning 都不吐的盲区

## 坑与教训
- **豆包视觉模型思考时间服务端不可控,budget_tokens 对它无效** — 参数微调全是徒劳,靠超时降级兜底;思考是"服务端行为"不是"可配置行为"
- DeepSeek chat/reasoner 2026-07-24 停用 → 模型 ID 必须跟随官方 changelog
- 豆包/DS 思考参数格式不同(豆包 reasoning_effort low/medium,DS low/high/max)→ 槽位化后按端点格式构建
- 自动更新四层坑:.part 扩展名 → FileProvider authority(camelCase 硬编码)→ open_filex 挂起 → **缺 REQUEST_INSTALL_PACKAGES 权限**(终极根因)。**真机端到端验证是唯一标准,代码推断不算数**
- Hive 读回嵌套 Map 是 `_Map<dynamic,dynamic>`,`as Map<String,dynamic>` 必炸 → 用 Map.from 重建
- 临时文件命名别用系统组件靠扩展名识别的场景(PackageInstaller 按 .apk 判断)
- 插件硬编码配置(open_filex authority)须与 Manifest 逐字核对

## 断点快照(2026-08-07)
- 正在做:文档同步(本次会话)——PLAN.md + memory 已补到 v1.2.14
- 卡在哪:无
- 下一步:等用户真机验证 v1.2.14(自动更新 + 句子显示 + 版本号核对);验证结果出来后再决定是否排查思考模式
