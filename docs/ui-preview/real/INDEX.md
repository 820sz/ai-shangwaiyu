# 真实渲染图索引（v2.27.0 交付验收用）

> 全部 390×844 逻辑尺寸 @3x = 1170×2532 PNG；生产组件 + 假数据（不联网）。
> 看设计稿请用 `docs/ui-preview/real/*`；`build/ui_real/` 是测试运行时写出的临时副本（build/ 不入库）。

## 阅读器 C（选型 C + 纸张三色 + 真实进度%）

| 文件 | 内容 |
|---|---|
| `reader-c-first-white.png` | 首屏：刊头双线 / 标题 28 / 首段 20 / 零常驻按钮 / 顶部 0% |
| `reader-c-paper-white.png` | 纸白纸 · 37% |
| `reader-c-paper-beige.png` | 米黄纸 · 37% |
| `reader-c-paper-night.png` | 墨夜纸 · 37%（砖红提亮 #E0604F） |
| `reader-c-console.png` | 上滑「阅读控制台」4 组（进度卡/学习/目录/材料） |
| `reader-c-console-material.png` | 控制台滚到底（材料组完整、当前节 03=90%） |
| `reader-c-console-night.png` | 墨夜纸上的控制台 |
| `reader-c-settings.png` | 阅读设置：5 档字号 / 3 档行距 / 三色卡 / 实时预览 |
| `reader-c-settings-night.png` | 墨夜纸上的设置 |
| `reader-c-toc.png` | 完整目录（每节 %、当前节砖红） |
| `reader-c-resume.png` | 续读弹层（上次 37%） |
| `reader-c-translating.png` | 翻译进行中（砖红进度，不压正文） |
| `reader-c-word.png` | 查词弹层（正常词条：词性/释义/音标/例句/询问 AI/收藏） |

## 找材料 A（并列大卡：自由搜 / 按我的情况找）

| 文件 | 内容 |
|---|---|
| `find-material-impl-entry.png` | 入口首屏：两张等宽大卡 + 最近搜过 + 上次结果 + [历史] |
| `find-material-impl-free-empty.png` | 自由搜空态（5 类筛选全可见） |
| `find-material-impl-free-result.png` | 自由搜结果（13 条/5 组/第 1-2 页） |
| `find-material-impl-free-pager.png` | 滚到底：页码控件 + 继续找更多 |
| `find-material-impl-free-empty-result.png` | 空结果 + 再搜一次 |
| `find-material-impl-need-panel.png` | 按需找依据面板（4 行真实数据 + 为什么推这些） |
| `find-material-impl-need-result.png` | 按需找结果（每卡"为什么推"只在有覆盖率时出现） |
| `find-material-impl-need-pager.png` | 按需找滚到底（页内分组 + 页码） |
| `find-material-impl-need-empty.png` | 缺数据降级（全部「待测」不显示数字） |
| `find-material-impl-no-cover.png` | 无真封面 → 纯文字版式（不画假封面） |
| `find-material-impl-history.png` | [历史] sheet（回填 / 清空） |

## 材料中心 / 书架（上一轮修复）

`channel-discover-p1.png`、`channel-discover-p2.png`、`channel-my-p1.png`、`channel-no-cover.png`、`channel-collapsed.png`（分类条滚走后紧凑范围条）、`shelf-carousel.png`、`shelf_detail.png`（书架 3D/网格：有真封面才显示，无图文字版式）

## 助理 / 我的（B 每日简报 + A 诊断台）

`assist-mine-impl-assistant-home.png`（助理首页 B）、`assist-mine-impl-mine-home.png`（我的首页 B）、`assist-mine-impl-stats.png`（A 诊断）、`assist-mine-impl-weekly.png`（A 诊断周报）、`assist-mine-impl-error-archive.png`（错误档案）、`assist-mine-impl-task-detail.png`（任务详情页）、`assist-mine-impl-review.png`（复盘页）、`assist-mine-impl-writing-logs.png`、`assist-mine-impl-api-settings.png`、`assist-mine-impl-appearance.png`、`assist-mine-impl-backup.png`、`assist-mine-impl-widget-settings.png`、`assist-mine-impl-about.png`、`assist-mine-impl-interview.png`、`assist-mine-impl-chat.png`、`assist-mine-impl-placement.png`

## 输出（A 纸面工作台 + 来源修复 + 四六级分桶）

| 文件 | 内容 |
|---|---|
| `output-impl-home.png` | 输出首页（B 果冻头图 + 四阶纸面清单） |
| `output-impl-practice-center.png` | 练习中心（纸面行） |
| `output-impl-setup.png` | 四阶设置（等级筛选 / 两种来源 / 来源说明） |
| `output-impl-setup-bottom.png` | 四阶设置滚到底（最后一张卡完整、CTA 不遮挡） |
| `output-impl-answer.png` | 答题页（来源行 + 等级徽标 + 白纸作答区 + rubric 预告） |
| `output-impl-result.png` | 批改结果（分数环 + 编号区块 + 低干扰问题条） |
| `output-impl-history.png` | 题库（等级筛选 + 统一来源行 + 回填按钮） |
| `output-impl-plan.png` | 旧计划页（5 个编号区块） |
| `output-impl-write.png` | 写译工作台（编号 01-04 + 纸面分段 + 唯一主行动） |

## 历史上的设计稿（选型阶段，保留备查，不是当前实现）

`reader-redesign-*.png`、`reader-plan-*.png`、`find-material-{A,B,C}-*.png`、`assistant-{A,B,C}.png`、`mine-{A,B,C}.png`、`detail-{A,B,C}.png`、`output-preview-*.png`、`material-hub-home.png`、`material-library.png`、`import-channel-picker.png`、`category-picker.png`、`fulltext-result-card.png`、`process-results.png`、`material-center*.png`。
