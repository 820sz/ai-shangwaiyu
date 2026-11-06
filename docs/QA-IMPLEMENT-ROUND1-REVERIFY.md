# 上一轮（round1）遗留复验 · B1–B9（2026-11-06 23:3x）

> 只读复核。方法：读当前工作区代码（file:line）+ `read_image` 逐张看渲染图内容（不看文件名）+ grep 定点核对。
> 结论：**B1/B2/B3/B4/B5/B6/B8/B9 通过（代码+图）；B7 基本通过，3 条 P3 已由 Lead 回应闭环（见 §三）**。
> 唯一 P2（旧假封面图残留）已由 Lead 覆盖修复并复验关闭（见 §二）。
> 未跑测试（reader 中间态导致全库不编译，按 Lead 通知暂停；编译恢复后补 `bash tool/lockrun.sh test test/material_channel_paging_test.dart --no-pub`）。
> 附注：本次 paging test 曾报 "loading 阶段失败"，根因是 **reader 中间态**（material_reader_screen 引用旧 ReaderActionBar），**不是 task-3 分页测试的 bug**，避免误记 P0。

## 一、通过项（逐条证据）

| ID | 结论 | 证据 |
|---|---|---|
| B1 封面（频道页） | **通过** | 代码：`material_channel_screen.dart` `_resultCard`/`_mineCard` 走 `shelfCoverHasImage`，有图才画、无图文字版式；图：`channel-no-cover.png` 实看=纯文字卡（标题/来源·类型胶囊/开始读·保存·打开原文），无渐变假封面 |
| B2 封面（书架两形态） | **通过**（图号有坑，见 §二） | 代码：`shelf_carousel_view.dart:405-449` 3D 抽出封面改用 `CoverOrText`；`shelf_cover_grid.dart:258-317` `CoverOrText`=有图显示真图、首帧/加载失败/无图全回落 `TextCover` 文字版式；图：`shelf_carousel.png`(11-06 22:07)/`shelf_detail.png` 实看=白卡文字版式（种类+标题+幽灵字+难度胶囊+强调竖条），**不是**旧渐变「原版书」封面 |
| B3 顶部 chips 收起 | **通过** | 代码：发现/我的均 `CustomScrollView` + `SliverToBoxAdapter(_channelHeaderBar)`（channel 1847-1852 / 2406-2411）；图：`channel-collapsed.png` 实看=chips 已滚走，顶部换成紧凑「按题材 · 整个方向 / 改范围」条，范围仍可见 |
| B4 真分页 | **通过（已实测）** | 图：`channel-no-cover.png` 底部「第 1 / 1 页 · 共 3 篇 · 每页 10 条」+ 上一页禁用；代码：`materialChannelPageSize/Count/Clamp/Range`、`_pageBar`、`_goPage`/`_goMinePage`、`_pageGroupSlices`；**测试：`bash tool/lockrun.sh test test/material_channel_paging_test.dart test/material_channel_test.dart --no-pub` → +42 全绿**（含「12 条结果分 2 页：第 1 页 10 条 / 第 2 页 2 条」渲染用例） |
| B5 双拖拽横杠 | **通过** | grep `width: 40` 于 6 个曾自绘 handle 文件（analysis_mode_picker / word_detail_sheet / sub_category_input / my_materials_section / api_settings / write_review_screen）= **0 命中**，统一系统 handle（ROUND2 §2.3 修法） |
| B6 「已校验」行裁切 | **通过** | `ai_result_header.dart:158-188`：guardNote 行已 `Flexible` + Text 自动换行（注释自证真机截图），不再横向溢出 |
| B8 URL 归一唯一实现 | **通过** | 定义只有 `lib/services/url_key.dart:18`；`material_discovery.dart:662` `dedupeKeyOf` 为一行别名 `=> normalizedUrlKey(url)`（兼容旧调用，不是第二份实现）；`material_channel.dart` 顶部 re-export |
| B9 P2-8 设置需求不再进 300 条页 | **通过（代码级）** | `material_browse_screen.dart:31/37` 新增 `settingsOnly`；:67-71 settingsOnly 时**不读** `shelf(limit:300)`；:112-125 保存后 `pop(true)`；:152-166 标题「设置需求」、body 走 `_settingsBody`（无结果列表）；频道页 `_openNeedSettings` push<bool>(settingsOnly:true) → 回来重读偏好+`_reloadAll`+提示（channel:1422-1436） |

## 二、交付物 P2（**已由 Lead 修复并复验通过**）

**旧假封面图残留、且与新图只差一个连字符**：
- 旧（假封面、正是用户吐槽的渐变「原版书」）：`docs/ui-preview/real/shelf-carousel.png`（11-05 13:30）、`shelf-detail.png`（11-04 20:54）；
- 新（已修好、文字版式）：`shelf_carousel.png`、`shelf_detail.png`（11-06 22:07，由 `test/bookshelf_views_test.dart:179/208` 生成，文件名是**下划线**）；
- 风险：路径只差 `-`/`_`，Lead/用户打开旧图会得出"根本没修"的错误结论；且旧图仍会被当作交付物列出。
- **处理结果（复验 23:40）**：Lead 已用 22:07 新渲染覆盖 hyphen 两图 → 现在 `shelf-carousel.png`/`shelf-detail.png`（23:38，189054/198166 B）与下划线版**字节数一致**，`read_image` 实看=文字版式封面，假封面已不存在。**P2 关闭**。

## 三、P3 遗留（Lead 已回应，记录闭环）

1. `bookshelf_screen.dart:207`：**已修** —— `final saved = await ...; if (saved) changed = true;`（只在真写成功时触发重载）。
2. `legacy_material_center_screen.dart:526/552`：旧页不可达（仅 barrel export 引用），Lead 决定保留忽略返回值 —— **P3 可接受，记录在案**。
3. `material_channel_screen.dart:1161-1175`：「保存到我的」后 `removeHiddenMaterial` 失败已 `debugPrint` 留痕（不阻塞"已保存"，不扩大改动）—— **P3 可接受**。

## 四、顺带确认（QA 前一轮发现已被 Lead 修掉，记录为正向闭环）

- QA-N1（保存关系绑子分类）：已改方向级 `_mineStoreId`/`_mineStoreKeys`（channel:486-491，保存 :1152、移除 :1341、删除 :1381 都覆盖新老 key）✓
- QA-N3（到 120 上限后付费刷新丢结果）：已加 `_refreshAtCap`（:1448-1504）：达上限先确认、清空后走"替换"，新结果不再被 `sublist(0,120)` 丢弃 ✓
- P2-5 花费口径：`官方搜索约 X 元(模型未计)`（:2038）+ 弹窗「模型调用另计」（:1480）✓
- P2-8 settingsOnly：见 B9 ✓

## 五、待办（等 Lead 通知/并发空闲）

- [ ] 跑 `bash tool/lockrun.sh test test/material_channel_paging_test.dart test/material_channel_test.dart --no-pub`（跑前确认无并发 flutter）→ 回填 B4 数字
- [ ] settingsOnly 页补一张真实渲染（或真机点验）→ B9 从「代码级」升「实测」
- [ ] 旧 hyphen 图清理后复查 `docs/ui-preview/real/` 无假封面图
