# QA 实施度复核 · 输出板块（A 纸面 + 来源修复 + 四六级分桶）· 最终版 · 2026-11-07 02:0x

> 复核对象：output-plan 收尾版（task-9）。基准：`docs/QA-IMPLEMENT-CHECKLISTS.md` §4 O1–O18 + 设计
> `OUTPUT-REDESIGN-PLAN-2026-11-06.md` §一/§二/§四A + `IMPLEMENT-PLAN` §2.4。
> 方法：9 张 PNG（新 home/write/plan/practice-center 逐张 read_image + 其余按 sha256 确认与已验版一致）→
> P0-1/P0-2/P2-1 证据链回代码 → 18 个输出相关测试文件 lockrun 实跑 → 目录级 analyze → grep Material 残留/占位。
> **结论：通过（P0=0、P1=0、P2 全关）**；剩 2 条 P3 记录。状态=最终通过，可进集成。

## 一、实测数字（我实跑）

- 测试：18 个输出相关文件 lockrun → **265 passed / 0 failed**
  （含 `output_paper_meta_test` 29 例，新增「resolveExamType · 入口等级筛选优先(P2-1)」组；`output_impl_render_test` 9/9 出图）。
  注：对照表 §6 写 264 是加 resolveExamType 单例之前的数，实测现为 265（P3 文档精度，可顺手改）。
- analyze（目录级）：`lockrun analyze --no-pub lib/screens/output lib/screens/writing` → **0 error / 0 warning / 1 info**
  （仅存量 `article_reader.dart:319`；paper_kit 3 条风格 info 已清零）。
- 图：`home/write/plan/practice-center` 为新版逐张看过；`setup/setup-bottom/answer/result/history` sha256 与初版一致（内容未变，沿用已验结论）。

## 二、P2-1 闭环复验（Lead 指定重点 ①）

| 环节 | 证据 | 结论 |
|---|---|---|
| 新纯函数 | `output_composer.dart:896-903 resolveExamType({examGoals, examTypeOverride})`：override 非空且 != 'none' 返回 override，否则 `examTypeFromGoalIds(examGoals)` | ☑ |
| 出题器透传 | `composeFromMaterial({..., String? examTypeOverride})`（:973）→ `resolveExamType(...)`（:982-985）；material 题组 `exam_type` 取它 | ☑ |
| 页面接线 | `practice_setup_screen.dart:329` 传 `examTypeOverride: _effectiveExam`（`_effectiveExam = 筛选优先 → targetExamOf(goals)`，:77-78） | ☑ |
| 单测 | `test/output_paper_meta_test.dart:221-240` 组「resolveExamType · 入口等级筛选优先(P2-1)」：筛 CET-6 + goals=四六级 → cet6；无筛选回落 cet4（泛化）；`none`/空不覆盖 → 3 用例 | ☑（265 passed 内实跑通过） |
| 端到端推演 | 写篇 → 筛 CET-6 → 选已读材料出题：`_effectiveExam='cet6'` → composeFromMaterial(examTypeOverride:'cet6') → OutputSetSpec.examType='cet6' → `_saveSet` 写 `exercise_sets.exam_type` → 题库 `listExerciseSets(examType:'cet6')`（WHERE exam_type=?）可筛到 | ☑ |

## 三、P3 收尾复验

| P3 | 结论 | 证据 |
|---|---|---|
| ① home 500px 空白 | ☑ 关闭 | `output_home.dart:471` 注释：今日建议卡不再套 `AppStagger`（其入场延迟在首帧留"不可见但占位"）；新版 `home.png` 实看：目标卡 → **今日建议（完整可见）** → 01 四阶，间距正常，无空洞 |
| ② 残留 Material | ☑ 关闭 | 练习中心 2 个 ListTile → `PaperRow`（output_home:140/151，`grep ListTile(`=0）；真题类型弹层 2 个 → `PaperRow`（practice_setup:388/399，`grep ListTile(`=0）；写译「批改设置」弹层整体 `Theme(data: paperThemeOf(context))`（write_review:2054），ChoiceChip 不再落果冻色；新版 `practice-center.png` 实看=纸面行（图标+双行+chevron），非 Material ListTile 长相 |
| ③ 对照表数字/完成度 | ☑（附 1 处 P3 精度） | `OUTPUT-IMPLEMENT.md §4` 增「完成度」列且与代码/图一致：home=逐控件重排、practice-center=逐控件重排、setup/answer/result/history=逐控件重排、**write="首屏逐控件重排；结果/加载态为主题覆写（沿用既有结构）"、plan="首屏结构重排 + 主题覆写（内部为共享组件）"**——诚实标注、不虚报；§6 已有最终数字。**唯一 P3**：文档 264 vs 实测 265（新增 resolveExamType 单例后 +1），顺手改 |
| 视觉补强：写译工作台/旧计划页真重排 | ☑ | `write.png` 实看：`PaperTitle「写译批改」` + 01 材料类型/02 练习类型（新 `PaperSegmented` 细边+选中墨实心）/03 手写稿（纸面卡：相册拍照/先转电子档/直接批改主行动）/04 电子档；中部空白消失、同屏一个主行动。`plan.png` 实看：**01 怎么练 / 02 目标需求 / 03 当前水平 / 04 进度追踪 / 05 开始练** 五个编号区块 + 底部「生成 4 周计划」主行动。代码侧 write 使用 Paper* 组件（:1089-1203）、plan 使用 `paperThemeOf` + PaperSectionHead。 |

## 四、O1–O18 最终状态

- **O13 由 ◐ → ☑**（P2-1 闭环，见 §二）。
- 其余 O1–O12、O14–O18 维持初版结论 ☑（证据见本文 §三 + 初版报告段落，未改动项 sha256 一致）：
  四阶设置/答题/批改/题库/写译/计划 A 纸面；入口 B 头图；`parsePaperMeta` 只认命中不猜（29 例单测：裸数字不当年份/非法月份套数丢弃/无年份留空）；
  set paper 字段 + `_saveSet` 写 paper_year/paper_label（0 迁移）；题库/答题/历史三处统一来源行；筛选真查库；映射统一（`examTypeFromGoalIds`→`examTypeOfText`）；
  回填按钮只写现有列；拆四级/六级零迁移（`examTypesForGoals` 读时展开）；词池 `ExamVocab.wordsFor`；对照表 + 9 图 + 测试。

## 五、剩余 P3（不阻塞）

1. `OUTPUT-IMPLEMENT.md §6` 数字 264 → 实测 265（新增 resolveExamType 单例后 +1），顺手更新即可。
2. 写译「批改设置」弹层内 `ChoiceChip`（write_review:2173）仍是 Material 控件、但已套 `paperThemeOf` → 视觉纸面、行为正常，记录为"主题覆写范围内"（Lead 修法即此）。
3. `write/plan` 的"结果/加载态"沿用既有结构 + 主题覆写（doc §4 已诚实标注），若后续要求全屏逐控件再排可排入下轮。

## 六、最终结论

**输出板块：通过（P0=0、P1=0、P2 全关）**。P2-1「材料出题吃入口等级筛选」已闭环（纯函数+透传+页面+3 单测，端到端推演到题库筛选），P3 空白带/残留 ListTile/文档数字均已处理（文档数字差 1 为 P3 精度），写译工作台与旧计划页确认是**真重排**而非外壳+主题覆写（write 首屏逐控件；plan 5 编号区块）。**可进集成**。
