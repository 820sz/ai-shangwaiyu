# v2.27.0 交付清单（四主题全量交付 · 2026-11-07）

> 用户拍板选型 → 四主题并行实施 → 每主题「设计清单逐项落地 + 真实渲染 + 定向测试 + analyze」→ 独立 QA 逐项复核 → 全量闸门通过。
> 本文是最终交付索引：每个主题的对照表、QA 报告、渲染图、测试数字。

## 0. 全量闸门结果（Lead 实跑 `tool/final_gate.sh`）

| 项 | 结果 |
|---|---|
| `flutter analyze --no-pub lib` | **0 error / 0 warning**（7 条存量 info：process_chat ×5、ai_article_section ×1、article_reader ×1） |
| 全部渲染测试重出 | **全绿**（16 个 preview/render 测试文件） |
| 全量 `flutter test` | **1839 passed + 2 skipped + 1 已知假失败**（`profile_card_test` Hive 假时钟，交接文档标注「别修」；非本轮引入） |
| 版本 | `2.27.0+92` |

## 1. 阅读器（C 方案 + 三纸色 + 真实进度%）

- 对照表：`docs/READER-C-IMPLEMENT.md`（281 行，含作用域例外 §7.2）
- QA：`docs/QA-IMPLEMENT-reader.md`（R1–R15 全 ☑，P0=0）
- 渲染：`docs/ui-preview/real/reader-c-*.png` ×13
- 测试：widget 5 + paper 8 + render 14 + 旧功能回归 29 = **56 passed**
- 关键：零常驻按钮、上滑控制台 4 组、右侧 % 胶囊 + 96px 竖轨、纸白/米黄/墨夜三色（Hive 持久化 + 对比度守门）、真实 percent 落库（≤99）与续读、翻译进度不再压正文

## 2. 找材料（A 方案：并列大卡）

- 对照表：`docs/FIND-MATERIAL-IMPLEMENT.md`（含 W1/W2 整改、D6 历史、遗留清单）
- QA：`docs/QA-IMPLEMENT-find-material.md`（13/13 ☑，P0=0）
- 渲染：`docs/ui-preview/real/find-material-impl-*.png` ×11
- 测试：find_need_context 8 + material_result_list 14 + hub + 频道页分页/渲染 + 渲染 11 = **52 passed**
- 关键：自由搜（9 来源/5 类型/4 难度/4 场景）、按需找（4 行真实依据 + 两级"为什么推"）、共享结果件（频道页薄委托零行为变化）、快照/历史/继续找更多/切页回顶

## 3. 助理 / 我的（B 每日简报 + A 诊断台）

- 对照表：`docs/ASSISTANT-MINE-IMPLEMENT.md`（12 内页逐项勾选 + §5.5 P1 修复记录）
- QA：`docs/QA-IMPLEMENT-assist-mine.md`（M1–M15 全 ☑，P0=0、P1×3 关闭）
- 渲染：`docs/ui-preview/real/assist-mine-impl-*.png` ×16
- 测试：briefing 17 + profile 15 + tutor 6 = **38 passed**
- 关键：B 简报首页（助理/我的）、`TutorBriefing/MineBriefing` 纯本地文案、A 诊断三屏、12/12 内页换 V4JellyAppBar、任务详情页 + 复盘页 + 写译记录入口、名片整卡重排

## 4. 输出（A 纸面工作台 + 来源修复 + 四六级分桶）

- 对照表：`docs/OUTPUT-IMPLEMENT.md`（§4 完成度列 + §6 数字 + §7 已知限制）
- QA：`docs/QA-IMPLEMENT-output.md`（O1–O18 全 ☑，P0=0、P1=0、P2 全关）
- 渲染：`docs/ui-preview/real/output-impl-*.png` ×9
- 测试：输出相关 **265 passed / 0 failed**（含 `output_paper_meta_test` 29 例、render 9/9）
- 关键：A 纸面 7 屏 + 输出首页 B 头图、写译工作台逐控件重排、计划页 5 编号区块；P0-1 来源（年份套数只认命中不猜 → 真落库 → 三处统一来源行）；P0-2 四六级（筛选真查库 + 映射统一 + 回填按钮 + 拆四级/六级零迁移）

## 5. 输入 / 材料中心（上一轮修复收尾，QA 已复验）

- P2 数据层 10 条中的 1/2/3/4/5/7/9：失败语义返回成败、快照上限 120、URL 归一唯一实现、入库身份 URL、"我的"错误态、付费刷新确认、花费口径
- 正文质量闸门 `content_quality.dart`（找材料不再把书店/课程介绍/导航页当正文）
- 封面纪律（真封面才显示/无图文字版式/书架 3D 假封面移除）、顶部收起、真分页
- 输入内页：双横杠 ×6、已校验行溢出
- QA 记录：`docs/QA-REPORT-2026-11-06.md`、`docs/QA-IMPLEMENT-ROUND1-REVERIFY.md`

## 6. 未做 / 二期（已与用户对齐）

- 单题 `source_url` 入库需加列迁移（等批准）；六级专属 rubric（当前复用四级维度）
- 360dp 窄屏 / 系统深色弹层未逐屏出图（墨夜纸覆盖深色阅读）
- 长书懒加载 percent 轻微跳动（二期块内比例校准）
- 找材料质量继续按真机结果调（PDF 正文提取需加依赖，等确认）

## 7. 发布状态

- 本地提交 `4c4f330`（功能）/ `e3b0e8e`（符号+交付清单）/ `9c3e00f`（交接文档+发布脚本）/ `8f94e87`（渲染图索引+发布前核验）——**未 push**
- 构建产物：`build/app/outputs/flutter-apk/app-release.apk`（arm64 release，versionCode 92 / versionName 2.27.0）
- **签名与上一版一致**（apksigner 证书 SHA-256 `f94a4bec…`，v2.26.0 相同）→ 可直接覆盖安装/App 内更新
- **原生库结构与上一版一致**（arm64-v8a: libapp/libflutter/libdartjni；libdartjni 另带 v7a/x86_64 条目，与 v2.26.0 相同）
- 渲染图索引：`docs/ui-preview/real/INDEX.md`（按主题列出每张图对应屏幕，供真机验收对照）
- 按约定：**等用户真机截图验收通过后**再 push master + tag `v2.27.0` + gh release（脚本 `tool/publish_v2.27.0.sh` 已备好）

### 7.1 发布前补漏（QA 复检通过）

产品级入口审计发现「旧 AI 找材料页」还有 2 处**活入口**（输入首页「AI 找材料」动作砖 +「AI 帮找」按钮、题材分类页"让 AI 去找"卡），
会与新的「找材料」形成两套入口。已修（只改接线/文案，不改业务）：
`input_home.dart` 与 `material_category_screen.dart` 均改推 `FindMaterialScreen`，文案统一为「找材料」。

- QA 复检：改路线由正确，`MaterialDiscoverScreen` **已无活入口**（剩余 3 处引用均在死链：`CategoryMaterialScreen` ← 旧 `MaterialCenterScreen` 页面零实例化；`MaterialBrowseScreen` 仅以 `settingsOnly:true` 构造不渲染补长尾卡）；回归 `material_hub_test` + `material_center_helpers_test` **+20 全过**。
- 勘误记录：`legacy_material_center_screen.dart` 里的类名是 `MaterialCenterScreen`（旧名遗留），不是 `LegacyMaterialCenterScreen`。
- 补漏后重建 APK：**SHA256 `5151176bc42c53335455039047c11be5912c5bf6dc3529a9c616ff5a0b971e6a`**（以此为准；旧包 `50ff35d…` 作废）。

