# v2.28.0 交付清单（真机反馈 8 条整改 + 开屏/Logo + 关于/开屏公告）

> 用户 2026-11-07 真机验收提出 8 条问题 + 追加"开屏/Logo 重做 + 关于三件套"；本版一次交付。
> 每项都有「对照表 + 真实渲染 + 定向测试 + analyze」；QA 终验 8/8 ☑、P0=0（`docs/QA-IMPLEMENT-ROUND3.md`）。

## 0. 版本与产物

| 项 | 值 |
|---|---|
| 版本 | `2.28.0+93` |
| APK | `build/app/outputs/flutter-apk/app-release.apk`（arm64 release，26.9MB，versionCode 93） |
| 桌面副本 | `C:\Users\xi283\Desktop\ReadFlow-v2.28.0.apk` |
| SHA256 | `eb49cfffaff516b1138b04114b32b65efc467e72f7bdc8995bb2d454f1ce356e` |
| 符号 | `tool/symbols/2.28.0/mapping.txt` + `sha256.txt` |

## 1. 八条整改（全部完成）

| # | 用户反馈 | 修法 | 证据 |
|---|---|---|---|
| 1 | 材料中心相关性弱、越南语/报名网、真题不分四六级、被"用户需求"框死 | 频道只按「分类+难度」（`buildChannelQueries`/`buildChannelPromptHint`，taxonomy:262/296）；候选级三层过滤 `looksLatinNonEnglish`(:363)/`looksLikeAnnouncementPage`(:407)/`isWeaklyRelated`(:434) 接在抓取前；真题拆四级/六级+`examLevelOf`(:333)；理由阈值 0.10 | QA §1.9；109 tests；`channel-form.png`/`channel-filtered.png` |
| 2 | 阅读器空间利用率低、右侧留白多 | 正文 318→354px（+11.3%）；竖轨改 3px overlay 不挤压；% 胶囊移顶部；留白收紧；未填充轨道对比度 1.45/1.42/1.65 | QA §2.9；paper 9/9、layout 1/1、render 16/16；before/after 图 |
| 3 | 书架一进去有书横档 | 初始不选中；点书脊才抽出，封面浮在书架排上方；再点/点空白收回；滑动只滚书脊 | QA §3.9；+2 tests；`shelf-carousel-initial/open/swiped.png` |
| 4 | 自由搜输入框裁字、筛选不收起、无 AI 保底 | 输入框 `minHeight`+行高修复；筛选默认收起可展开；0 结果时给真实原因 + 「AI 改写学习版（非原文）」+来源/字数/难度；有原文时绝不替换 | QA §4.9；free_search 12、ai_rewrite 21；`free-input/free-filters/ai-generated/ai-empty.png` |
| 5 | 材料封面又不配图 | 卡片级懒加载 og:image（缓存/3 并发/负缓存/失败静默）+ 公版书封面；有图/无图两态，不画假封面 | QA §5.9；result_list 21；`cover-with/cover-without.png` |
| 6 | 输出四阶裁字 / rubric 等级错 / 不能跳题 / 材料不留存 | 四阶网格 1.28→1.02 + Expanded；CET-6 六级中文 rubric（开库幂等补种）；答题卡自由跳题；Hive 草稿 + 首页「继续上次练习」（零迁移） | QA §6.9；render 10/10、定向 58、组合 85；`output-impl-home/answer-cet6.png` |
| 7 | 我的名片背景看不清 | 背景图 6px 模糊 + 三层纸色 scrim；无图纸面卡 | QA §7.9；`namecard-plain/photo.png` |
| 8 | 关于：软件声明/特色/思想 + 首启公告 | 三入口 + Markdown 内容页（外链可开）+ 首启公告只弹一次（Hive）+ 开源许可；内容：声明（著作权/使用范围/免责，署名 xi283）、特色（技术架构定位）、思想（用户原文 + 21 条真实文献） | QA §8.9；profile_about 8/8、render 5/5；`about/about-notice/about-doc.png` |

## 2. 开屏 + Logo + 桌面图标（本版追加）

- 开屏：A 方案「琉璃凝结」——极光底 + 132 琉璃块磨砂→澄澈 + 引号（language）与星芒（AI）相向汇合 + 字标/自定义文案；1.5s、可点跳过、深色跟随、减少动效降级；AboutNoticeGate 顺序不变；
- Logo：L1「引号·星」（白色 mark + 投影），开屏与图标共用同一份 Path；
- 桌面图标：16 张 PNG（mipmap 5 密度 + drawable 前景/monochrome 5 密度 + 1024 主图），Android 8+ adaptive icon、Android 12+ 系统开屏样式（浅/深）；
- 方案对照与实现规格：`docs/SPLASH-LOGO-OPTIONS-2026-11-07.md`；线上帧 `splash-real-a-f1/f4/dark.png`。

## 3. 闸门（最终，`tool/final_gate.sh` 实跑通过）

- `flutter analyze --no-pub lib`：**0 error / 0 warning**（仅 7 条存量 info：process_chat×5、ai_article_section×1、article_reader×1）
- 全部渲染测试：**全绿**（19 个 preview/render 文件，含 splash_preview 21 帧、gen_icons 16 图）
- 全量 `flutter test -j 1`：**通过**（串行跑：多个测试文件共用同一 sqflite 磁盘库，并行会偶发 `database is locked`；仅 `profile_card_test` 历史已知假失败，Hive 假时钟，交接文档标注不修）
- 本轮测试账：QA 独立复跑 213 passed；splash 5/5 + preview 21/21 + icons PASS
- 签名与 v2.27.0 一致（可直接覆盖安装/应用内更新）

## 4. 已知未做 / P3（不影响本版验收）

- 软件使用教程（卡片式教程 + 首启推送）——用户同意排下一版，约 6~8h；
- 关于页「开源许可」在第二屏；内容页标题与正文首个 H1 轻微重复；频道「其他」chip 孤行；notes 两轮重复截断；answer-cet6 图未含题干（图注问题）；
- 单题 source_url 入库需加列（等批准）；找材料 PDF 正文提取需加依赖（等调研）；360dp/系统深色弹层未逐屏出图；长书进度轻微跳动（二期校准）。

## 5. 发布

- 本地提交后 push master + tag `v2.28.0` + GitHub Release（APK 资产，供应用内「检查更新」拉取）；
- 用户通过**内置更新**验收。
