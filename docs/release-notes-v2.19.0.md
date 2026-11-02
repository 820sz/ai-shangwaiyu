# ReadFlow v2.19.0 · 其余屏统一：我的 / 统计 / 设置 / 书架 / 收藏 / 错误档案 / 写译记录

> 批 5（2026-11-01）：把「我的」「统计」「设置」「学习偏好」「书架」「收藏夹」
> 「错误档案」「写译记录」全部换到 v3 设计系统上——你说的"其他页面太丑"这一条。

## 更新内容

1. 我的页重做：顶部变成「学习概览」大卡，用活跃率环形 + 近 7 天柱状图讲清"最近有没有在学"；学习曲线单独成卡。
2. 统计页重做：趋势线、柱状、热力日历、环形进度都换新版图形，每张图标注统计口径（近 7 / 30 天），没数据时给空态而不是画一排 0。
3. 学习偏好页重做：学习目标改为多选（可同时选四六级 + 兴趣阅读等），勾选后保存会真的写进画像；难度档在页面里按 i+1 舒适 / i+10 挑战 / i+100 快反馈展示，与材料中心同一份数据。
4. 重置偏好的危险操作统一二次确认，并写清"会清什么、不会动什么（生词/材料/学习记录不受影响）"。
5. API 设置重做：主/副槽位卡片统一形态；新增"没配 Key 时哪些 AI 功能不可用"的逐项说明，不再只写一句"未配置"。
6. 书架、收藏夹、错误档案、写译记录统一卡片形态与信息层级：关键词/来源/时间/次数一眼可见，长文案截断不撑破卡片。
7. 空态全部换成对应插画并给下一步动作（例如书架空 → "去材料中心挑一本"），不再只写"暂无数据"。
8. 删除/清空类操作统一二次确认，并说明"只删本机记录，不影响原始材料"。

## 技术细节

- 只改 UI 层，不改数据层与数据库结构：`lib/screens/profile/*`、`lib/screens/input/bookshelf_screen.dart`、`lib/screens/input/learner_preferences_screen.dart`、`lib/screens/writing/writing_logs_screen.dart`。
- 统一使用 `config/design_tokens.dart`（AppFont/Gap/Radii/Insets）、`widgets/app_ui.dart`、`widgets/design_kit.dart`、`widgets/graphics/graphics.dart`；禁掉裸转圈、硬编码颜色与 Markdown 星号文案（`theme_test` / `ui_copy_lint_test` 双闸门通过）。
- 学习偏好多选写回 `LearnerModelStore.saveSelfReported(goals:)`（新增 goals 参数的那一层），难度档写回 `MaterialPrefs.band`，材料中心读同一份。
- 验证：`flutter analyze` 0 error / 0 warning（9 条存量 info）；全量测试 **1442 passed + 1 skip + 1 已知假失败**（`profile_card_test` 的 Hive 假时钟问题，与 App 无关）。

## 还没做

- 批 6：动效打磨 + 最终全量验证 + 发版（Release notes / 版本号 / 校验 / 同步远端）。
- 阅读器视觉细排、考纲词表、听力入口仍是后续项（不在本版范围）。
- 真题抓取的提示词效果还需要你用真 Key 实测调优。

> 注意：数据库版本保持 22（本版无迁移），升级仍只能前向。
