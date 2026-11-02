# ReadFlow v2.23.0 · 最终版：需求闭环（前端 + 后端）

> 终版（2026-11-02）。这一版把自查清单里剩下的数据层/材料中心/助理/阅读器缺口全部收口，
> 与前面 9 个版本合起来，就是「输入 → 输出 → 助理 → 复盘」的完整闭环。

## 更新内容

1. 备份/恢复升级到完整版：阅读译文、题组与题目、输出作答、能力快照、任务与任务事件、错误档案、复习记录都进备份；旧备份仍能导入，导出被截断时会明确提示。
2. 能力快照全链路：测词汇量、写译批改、输出练习之后都会记下能力值，助理「现状分析」与复盘的趋势才有真实数据。
3. 阅读速度/词汇量回写：打开助理或统计时用真实阅读数据与测试基线补全画像，不再有「读了很久却显示没数据」。
4. 材料中心收尾：屏蔽词会真正过滤今日推荐/发现列表并说明过滤了几条；今日推荐给出「预计难度区间」（标明是估算、不给假百分比）；修掉重复条目、打开失败提示、分类筛选失效、加载态、长标题溢出、书架首屏不加载 6 类问题。
5. 周报与助理共用同一份输出统计口径：两边看到的输出次数/均分一致，不会再出现「周报一个数、助理另一个数」。
6. 水平测试的语法错题按考点建档（时态/冠词/介词/主谓一致/虚拟语气），错误档案里能看到「水平测试」来源的分项记录，不再只存一个总分。
7. 阅读器加目录：长材料/书可跳到任意章节；默认字号已下调一档，字号/行距面板保留。
8. 全 App 尊重系统「减少动态效果」：开启后入场动效直接呈现，不再有多余动画。
9. 删除材料时级联清理该材料的译文，避免重导出现旧译文。

## 技术细节

- 备份 v2：`backup_service.dart` 新增 `backupVersion`/`tables`/`truncation`/`counts`（10 张表；output_attempts/task_events 各保留最近 5000 条并写报告）；恢复走"v3 表整块事务 + 自然键判重 + id 映射重建"，v1 备份兼容；`RestoreReport` 增加逐表条数与跳过原因；备份/恢复页展示截断说明与逐表结果。
- 能力快照：新 `ability_recorder.dart`（placement→vocab/test，写译与练习→output/inferred，同日 upsert，失败静默）；`learner_extras_sync.dart` 回写 `reading_wpm`(60~1000 合法区间) 与 `vocab_inferred`(仅 test 基线)，幂等不重复写。
- 材料中心：`MaterialLibrary.filterBlocked/estimateDifficulty/rankForGoals/dedupeShelf` 纯函数 + 11 条测试；`material_center_screen` 接入屏蔽过滤/预计难度/去重/统一失败提示/偏好重读/骨架统一/书架首屏加载。
- 周报：`WeeklyOutputBlock` 唯一解析实现 + `weekly_report_consistency_test` 12 条断言两侧同口径。
- 语法诊断：`placement_diagnosis.dart` 纯函数按题目标签 `bumpErrorTag(source:'placement')`，错误档案来源新增「水平测试」。
- 阅读器：目录抽屉（章节标题/字数/当前节高亮，跳转复用 `_scrollToChunk`）；`AppStagger` 检测 `MediaQuery.disableAnimations` 直接呈现。
- 验证：`flutter analyze` 0 error / 0 warning（8 条存量 info）；全量测试 **1577 passed + 1 skip + 1 已知假失败**（`profile_card_test` Hive 假时钟问题，与 App 无关）。

## 终版状态说明

- 自查清单剩余项：听力入口（按你的要求不做）；完整官方考纲词表（当前 859 词精选，可后续扩表）；真题抓取质量需要你用真 Key 实测后调优。
- 数据库版本保持 22（本版无迁移）。
