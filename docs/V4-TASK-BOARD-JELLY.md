# v4 明亮果冻 · 施工任务板(规划与管理)

> 用户 2026-11-03 选定「明亮果冻」并开工。本板是**唯一进度事实源**:
> 每完成一屏就更新状态;每批结束跑一次质量闸门。规则:**先出图 → 用户过目 → 再进下一屏**;
> 四组全过 → 全量 analyze/test → 打 v2.25.0 APK(用户确认前不打包)。
>
> **2026-11-03 23:58 已发布 v2.24.0**(用户要求"先推动一版软件内置更新"):
> https://github.com/820sz/ai-shangwaiyu/releases/tag/v2.24.0
> —— 明亮果冻全 App 视觉 + 输入板块重做 + AI 原生件 + 材料自动配图;
> 包内 versionName 2.24.0 / versionCode 84,sha256 与 Release asset digest 一致。
> 同版开始「输出练习图片上传」:答题页(四阶练习器)、写句/纠错已支持拍照作答;
> 剩余:翻译练习(drill)、题库练习、词库拼写(拼写题无需图片)下一批补。
>
> **2026-11-04 起进入 v5 架构阶段（先定架构再动前端）**:
> - 材料中心重构方案:`docs/V5-MATERIAL-CENTER-ARCH.md`（首页只留大分区 + 今日精读；
>   按需求/题材/形式/场景四维度；材料库编辑/删除/隐藏/收起；多选精准推荐）
> - 书架双形态方案:`docs/V5-BOOKSHELF-REDESIGN.md`（3D 轮播 / 详细书架可切换）
> - 阅读器翻译 bug 已定位修复(`$_units.length` 列表插值)；阅读器重做排入 P5

## 一、状态图例

| 符号 | 含义 |
|---|---|
| ✅ | 已迁移 + 已出图(或已过闸门) |
| 🟡 | 已迁移,待出图/待用户过目 |
| ⬜ | 未开始 |
| 🔒 | 本轮不动(冻结:功能/数据层/听力) |

## 二、地基(已完成)

- ✅ 皮肤令牌:`lib/config/v4_theme.dart`(`V4Skin` ThemeExtension,浅/深两套,可换肤)
- ✅ 主题映射:`lib/config/theme.dart`(主色/圆角/按钮/输入/弹窗/深色)
- ✅ 基础件:`app_ui.dart`(AppCard 135 处 / AppActionTile)、(AppSectionTitle…)
- ✅ 形态件:`design_kit.dart`(AppTag/AppContentTabs/AppProgressRing/AppHeroCard/AppWideCard/AppEmptyState)
- ✅ 底栏:`bottom_nav.dart`(悬浮玻璃胶囊)
- ✅ v4 组件:`v4_kit.dart`(主屏头图 + 内页头图 `V4DetailHeader` + `V4JellyAppBar` + `V4IconAction` + 卡片/糖果砖/胶囊/状态三件套)
- ✅ 主屏:输入页、输出页
- ✅ **材料封面(v4.2 重做)**:深色块 → 浅色"印刷封面"——糖果纸面按标题稳定取色 +
  域色书脊 + 按 kind 的极淡几何纹理 + 墨字 + 白玻璃徽标;有真图仍优先用图;
  单字标只留给 42×54 缩略,72+ 中卡给"能认出来的词/2~4 字",宽卡才上标题。
  样张:`docs/ui-preview/jelly/covers.png`(明/暗 × 5 种真实尺寸)
- ✅ **材料自动配图(v4.3,用户点名"让 AI 配材料自己的图")**:
  `lib/services/material_art.dart` + `lib/widgets/art_cover.dart` ——
  抓取**免费优先**:书用豆瓣书封(实测可达,真实文件 25~250KB),非书用 360 图片
  (实测可达,取 thumb CDN);抓到即落盘缓存(滚列表零网络),源头图 403/超时也会
  自动触发重抓;AI 生图(方舟 Seedream,按张计费)是**可选兜底,默认关**;
  设置页新增「材料自动配图」三档(抓取 / 抓取+AI 兜底 / 关闭)。
  已接入:继续读大封面、材料中心今日精读+材料库横卡、书架、导入列表、发现页、
  练习设置材料、AppHeroCard/AppWideCard 自动配图开关。
- ✅ **配图策略研究存档**:`docs/V4-MATERIAL-ART.md` —— 用户网络下图源可达性实测、
  成本对比、抓取/生成分层设计、明天拿到 Ark Key 后的验证清单与调优计划。
- ✅ **AI 原生件(v4.4,用户确认保留并升级)**:鲸鱼尾思考块(计时/渐隐/折叠)+
  流式呼吸光标与"生成中…" + 品牌 Logo 白底托圆环 + 追问抽屉新皮(身份行/渐变用户
  气泡/白卡 AI 气泡/胶囊快捷提问/圆形发送键);**流式·停止·超时·记忆逻辑未动**。
  实拍:`docs/ui-preview/jelly/ai-ux-actual.png`(production 组件渲染)。
- ✅ 预览管道:`test/ui_v4_preview_test.dart` → `build/ui_v4_preview/` → 归档 `docs/ui-preview/jelly/`
- ✅ 质量闸门:analyze 0 error/0 warning(8 条存量 info);测试基线 1578 passed + 1 skip
  (2 个失败:profile_card_test 交接文档标注的已知假失败;backup_v2_test 全量并行偶发、单跑通过)

## 三、四组屏清单

### 第 1 组 · 输入链路(今晚已全部重做完 ✅)

| 屏 | 状态 | 备注 |
|---|---|---|
| 输入首页 | ✅ | 果冻头图 + 难度/目标玻璃胶囊 + 糖果动作砖 |
| 材料中心 | ✅ | 内页头图(V4DetailHeader)+ 玻璃圆键 + 整页去掉 AppBar;出图 `docs/ui-preview/jelly/inner.png` |
| 题材分类页 | ✅ | 内页头图;来源筛选/横卡/AI 入口保留;出图同上 |
| 书架 | ✅ | 内页头图(排序收进玻璃圆键)+ 骨架/空态统一;出图 `docs/ui-preview/jelly/inner2.png` |
| 收藏 | ✅ | 内页头图,三态(加载/失败/空/列表)保留;出图同上 |
| 阅读器(正文/翻译/目录/字号/查词/追问) | ✅ | v4.5:**纸面阅读区**(24 圆角白纸 + 细边)+ **译文便签**(淡主色卡 + 「译」徽标)+ 在途译文骨架卡;底部动作栏/字号/点词/追问逻辑未动;出图 `docs/ui-preview/jelly/input-final.png` |
| 拍照 / 相册导入 | ✅ | 通道选择器 / 进度弹窗随果冻主题;导入流程未变;出图 `docs/ui-preview/jelly/inner4.png` |
| 链接导入 | ✅ | 同走 MaterialImportFlow;链接确认框随主题;流程未变 |
| 识图结果(`process_chat`) | ✅ | v4.5:**扫描工作台状态卡**(连接中/逐行识别/识别完成/失败 + 已选计数 + 照片存档提示)+ **校对清单分组头**;识图三态与批注/保存逻辑未动;出图 `docs/ui-preview/jelly/input-final.png` |
| 材料分组 / 分类管理 | ✅ | 分类选择/子分类弹层已随主题果冻化;流程未动 |
| 词汇本:生词本列表 | ✅ | 内页头图 + 搜索/多选收进玻璃键;出图 `docs/ui-preview/jelly/inner3.png` |
| 词汇本:词条详情 | ✅ | 词本身做头图标题,朗读玻璃键;出图同上 |
| 词汇本:复习(FSRS) | ✅ | 内页头图 + 打乱/重算玻璃键,队列/卡片/三态保留;出图 `docs/ui-preview/jelly/main2.png` |

### 第 2 组 · 输出链路

输出首页已 ✅(头图卡)。四阶设置页、答题页、批改结果、写译工作台、题库、练习中心、真题抓取、旧计划页 ⬜。

### 第 3 组 · 助理链路

助理首页 🟡(已换主屏果冻头,骨架/读不到/正常三态统一)、现状、任务列表/详情/编辑、复盘、聊天、水平测试 ⬜。
(助理首页与我的首页是主屏,已完成头图迁移;内页随后。)

### 第 4 组 · 我的链路

我的首页 🟡(已换主屏果冻头 + 生词/连续胶囊;加载/刷新保留)、统计、周报、学习偏好、API 设置(已加自动配图项)、错误档案、写译记录、备份与恢复、关于/更新 ⬜。

## 四、每屏迁移配方(照做即可,避免走样)

1. **头**:`Scaffold + AppBar` → `V4DetailHeader`(可滚动内页)或 `V4JellyAppBar`(必须保留 AppBar 语义的页,如阅读器);
   - 头图 action 一律 `V4IconAction`(玻璃圆键),不再用裸 IconButton;
   - 根 tab 页 `leadingBack: false`,二级页保持 true。
2. **身**:页面容器 `Scaffold(backgroundColor: V4Skin.of(context).pageBg)`;
   内容左右 20、区块间距 24-32;不再手写 `Card/Padding` 堆叠。
3. **卡**:主内容用 `AppHeroCard`/`AppWideCard`/`V4ListCard`;入口用 `AppActionTile`/`V4ActionTile`;
   禁止页面里再写裸 `BoxDecoration` 圆角/阴影(走 `V4Skin`)。
4. **标签**:`AppTag`(果冻胶囊);难度 `AppLevelBadge`;tabs 用 `AppContentTabs`/`V4TopicTabs`。
5. **状态**:加载 `AppLoading`/`V4Skeleton`、空 `AppEmptyState`、错 `AppErrorCard`;三态必须同屏语言。
6. **底**:若页面有底部动作栏,统一白色/玻璃胶囊 + 主行动唯一。
7. **闸门**:`dart analyze <改过的文件>` → `flutter test <相关测试>` → 停;出图进对话。

## 五、交付节奏与质量闸门

- 每屏:改 → 静态检查 → 相关测试 → 渲图 → 用户过目 → 记录到本板;
- 每批(一组):全量 `flutter analyze --no-pub` + `flutter test --no-pub`,失败必须分类
  (真回归 / 测试断言过时 / 已知假失败),不允许"绿了但没说清";
- 四组全过:打 v2.25.0 APK(桌面 + GitHub Release),发布说明按 `## 更新内容` + 编号列表;
- 禁止:动数据库结构(dbVersion 22)、改功能逻辑、加听力、未经确认打包。

## 六、已知风险/注意

1. `theme_test` 的"硬编码浅色闸门"禁止 `onSurface.withAlpha(...)` / `Colors.grey[50..800]` 等,
   新组件一律用 `withValues(alpha:)` + `V4Skin`;
2. 深色下"白胶囊上的字"必须用 `_inkOnLight`(浅色底 + 浅墨 = 看不见),v4_kit 已统一;
3. 阅读器/识图页有大量异步与持久化逻辑,**只改视觉不动状态机**;
4. `backup_v2_test` 偶发(全量并行时 SqliteFfi 时序),单跑通过 —— 记为已知 flake,
   改视觉期间不修;
5. 每屏改完必须跑相关测试(例如材料中心:material_center 相关测试),避免视觉改动压出回归。
