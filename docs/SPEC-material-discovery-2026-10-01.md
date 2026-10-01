# 材料中心「发现页」设计规格(对标调研 + 可直接落地数值)

> 调研日期:2026-10-01 · 服务于任务板 `docs/TASK-BOARD-2026-10-01.md` 第 6(1)(2)(4)(5) 条
> 方法:App Store 中国区官方截屏(下载原始 PNG 后像素级测量)+ iTunes Lookup/Search API 官方文案 +
> 在本机网络环境实测图片源可达性(真实 HTTP 状态码/耗时/响应体)
> 标注约定:**[实测]** = 本次真的抓到/测到;**[截图观察]** = 从官方截屏读出来的;**[行业共识]** = 公开研究/通行做法;**[我的设计建议]** = 没有来源,是我的建议

---

## 一、这类 App 是哪几款,它们的发现页到底怎么组织

### 1.1 涉及的 App 清单(中国区,2026-10-01 实查)

| App | 开发商 | 定位 | 与「发现页」的关系 |
|---|---|---|---|
| 扇贝阅读 `id598541783` | 南京贝湾 | 每日热文 + 原版书 | **最接近用户给的截屏 A** |
| 百词斩爱阅读 `id1313658481` | 成都超爱学习 | 专辑式阅读 | 首页 = 分类 tab + 封面栅格 |
| 薄荷阅读 `id1303452045` | 百词斩旗下 | 分级阅读 + 互动小说 | 首页 = Mint Daily 大卡 + 猜你喜欢横滑 |
| 流利说阅读 `id1435478035` | 上海流利说 | 每日一篇外刊精读 | 纯文字极简,重讲解不重卡片 |
| 每日英语听力 `id570118289` | 欧路 | 泛听资源库 | 发现/分类/推荐 三 tab + 「外刊精读」栏目 |
| 轻听英语 `id1411918373` | 欧路系 | 听说读写一站 | 分级 + 题源分类 |
| 可可英语 `id557537604` | 可可 | 30 万有声资源 | 官方写明 **「分级推荐基于 CEFR 科学定级」** |
| 英语阅读(每日外刊头条)`id597131936` | — | 外刊头条 | 题源导向(经济学人/卫报/时代) |
| China Daily `id330543698` | 中国日报 | 英文新闻客户端 | 内有「精读/听力/口语」学习区 |
| 英语日报 EnglishDaily `id1658243940` | — | 头条新闻 | 榜单型 |
| 微信读书 / Kindle 英文原版 | — | 书库型 | 对照组:**书**用封面竖图,不用配图横图 |

### 1.2 扇贝阅读发现页(截屏 A 的原始出处)—— 一行一行抄下来

**[截图观察]** 官方截屏 1「全球热文 每日更新 / 涵盖各大考试题源 / 每日 6 篇覆盖热门话题」:

```
顶部行:  今日短文  7:00 准时更新              [全部 ▸]
                                                   ← 右侧竖排浮层:分类入口
                                                   [ 科学 ] [ 人文 ]
                                                   [ 商业 ] [ 成长 ]
                                                   [ 心理 ]
─────────────────────────────────────────────────
卡片 1(大卡):
  ┌───────────────────────────────┐
  │  配图(蓝天 + 手持黄色笑脸球)  │  ← 满宽,画幅≈1.93:1
  ├───────────────────────────────┤
  │  ▤ 心理                        │  ← 第一行:分类标签(前置线性图标)
  │  How Can We Stop Basing Our    │  ← 英文标题,两行,粗体
  │  Self-Worth Entirely on Our…   │
  │  你的自我价值,本就不该与工作划等号 │  ← 中文副标题(翻译)
  │  ( 中阶(四级)  ·▮▮ 424词 )      │  ← 难度标签 + 词数(带条形图标)
  └───────────────────────────────┘
────────────── 以下为列表项 ──────────────
列表项 2:
  ▤ 科学   [考研同源]              ← 分类标签 + 题源标签(绿底小圆角)
  Lucky Genes Can Help Protect    ← 英文标题(两行)
  People with Obesity from
  Some Disease
  "幸运基因",帮助避免肥胖相关疾病     ← 中文副标题
  中高阶(六级/考研)  ·▮▮ 398词      ← 难度(带体系括号!) + 词数
                          [缩略图]   ← 右侧方形缩略图
                            💬 432   ← 缩略图上的评论数角标
```

细节提取:
- **难度标签的写法是「档位(考试体系)」**:`中阶(四级)`、`中高阶(六级/考研)` —— 用母语用户熟悉的考试做锚点,而不是干巴巴的 Lv8。
- **元信息只有两项:难度 + 词数**。没有显示时长、没有显示句数、没有显示口音。
- **分类维度是「题材」**(科学/人文/商业/成长/心理/生活),外加**「题源」标签**(考研同源/四级同源)。
- 顶部写着 **「每日 6 篇」**,用「限量」制造稀缺感,这也是它敢收会员费的支点。
- 底部营销条写着:**考研 四级 六级 托福 雅思**(考试导向)。

**[截图观察]** 阅读页:顶部 5 个图标(排版 / 耳机 / 收藏 / 分享 / 更多),正文 tab「原文 / 笔记 / 精讲」,正文里**高亮单词**点击出底部释义卡(quietly, adv. 静静地),右侧有 AI 讲解浮层(词汇精讲 / AI 句子解析 / 长难句 NPC 分析:主干/N非谓语动词/P介词短语/C从句 四色标注)。
**[截图观察]** 分享:支持「一键生成 5 版手帐」——原文版 / ★双语版 / 思维导图 / 彩虹卡片 / 笔记版。

### 1.3 薄荷阅读发现页(第二个标杆)

**[截图观察]** 首页:
```
[←] [🔍 内容等你来搜]                 [书城] [单词本]
┌─────────────────────────────────────┐
│ Mint Daily            六月 2025  10 │  ← 品牌名 + 月/日 大数字
│ 如果全球气候停止变暖,               │  ← 中文标题在前
│ 冰川会复原吗?                       │
│ Permanent Glacier Loss: Why Climate │  ← 英文原标题在中文下面!
│ Delays Matter                       │
│ [配图:冰川人像]                     │
│ 编辑推荐  “冰川一旦消失,是否还能重新出现?” │
│ 回看往期                [ 开始阅读 ] │  ← 次按钮 + 主按钮同行
└─────────────────────────────────────┘
猜你喜欢 ❤️
[美国历史演讲]  [四级真题]  [美国独立宣言]  [心与…]
 历史新闻·美国   2018.06四级   美国独立宣言
 演讲名篇        真题题         14.1万人在读
 32.4万人在读    22.9万人在读
```
注意三个可抄的点:
1. **中文标题在上、英文在下**(和扇贝相反),因为它的读者更初级;
2. **「N 万人在读」当成社会证明**(32.4 万 / 22.9 万 / 14.1 万);
3. 大卡同时给「回看往期」和「开始阅读」,把"补昨天的"路径放在主按钮旁边。

**[截图观察]** 书城页:「全部 / 小说名著 / 外刊文章 / 书单」四个 tab,下面列表项:
```
沃伦·巴菲特致股东信中的金句                      [人物照片缩略图]
Buffett's Legacy: Wisdom Beyond Wealth
中阶  热读100+  入门常读                          ← 一排 3 个标签
```
顶部有**题材 chip 行**:人文 / 经济 / 科学 / 商业 / 心理 / 成长 / 真题。

**[截图观察]** 阅读挑战页(等级体系最完整的一屏):
```
阅读挑战
[推荐] [我的计划]
难度: 全部 | 入门 | 初阶 | 中阶 | 高阶        ← 四档
天数: 全部 | 30-60天 | 100天
┌────────────────────────────────────┐
│ 经典神作                             │
│ 阿加莎精选:4本推理界中的神作  [封面拼图] │
│ 小说/悬疑/人性                        │
│ 初阶·   100天│共4本              [→] │
└────────────────────────────────────┘
│ 哈利波特全集:两代人的魔法回忆          │
│ 小说/影视/成长/冒险/奇幻  中阶+  365天│共7本│
```
→ **等级是「入门 / 初阶 / 中阶 / 高阶」四档,带 `+` 号做半档**(中阶+),并且**等级和"天数/本数"绑定展示**。

### 1.4 百词斩爱阅读 / 每日英语听力 / 流利说阅读

**[截图观察]** 百词斩爱阅读:
- 首页:`[🔍 想读的主题或专辑]` 搜索框 → 顶部 tab `推荐 / 美文 / 考试 / 知识 / 故事 / 演讲` → 运营 banner(`百万英镑最新上线 / MILLION POUND BANK NOTE / 赶紧查看`)→ 「猜你喜欢」**3 列封面栅格**,每格下面两行:标题 + `32.2万人在读`。
- 底部 5 tab:`专辑 / 计划 / 发现 / 我的`。
- 阅读页顶部大标题 + `作者:Mark Twain` + 「官方翻译 积分解锁」**开关**(把翻译做成付费点)。

**[截图观察]** 每日英语听力:
- 顶部三 tab:`发现 / 分类 / 推荐`;分类页是**左侧一级目录 + 右侧内容卡**:
  一级目录 = 每日收听 / 题源外刊 / 分级读物 / 有声名著 / 英语口语 / 英语考试 / 涨知识 / 影音娱乐 / 演讲访谈 / 精选播客 / 经典教材 / 外教达人 / 词汇语法…
- 卡片形如:`[封面图] 读外刊练阅读 · 高校名师带你精读经典外刊文章,全面提升阅读能力 [目录]`
- 「外刊精读」栏目:顶部是**当期报刊报头图**(The New York Times 原版报头),标题 `179期 | 佛罗里达州禁止手机进校园(上)`,元信息 `周羽讲解 · 纽约时报`,往期列表每行 `December.8 / 178期|… / 周羽讲解·英国卫报 / 3674(播放数)`。

**[截图观察]** 流利说阅读:白底极简,首屏几乎是**报纸 + 放大镜**的插画 + 讲师头像矩阵,把"人"当作信任来源。阅读页正文里生词**黄底高亮**,下方直接挂释义卡(`sweeping / adj. 影响广泛的,规模宏大的 / 音标 / 词性拓展 / 例句`)。

### 1.5 横向对比表

| App | 首屏结构(从上到下) | 配图 | 时长/句数/口音 | 等级体系 | 分类维度 | 会员墙 |
|---|---|---|---|---|---|---|
| 扇贝阅读 | 标题+更新时间 / 全部 / 大卡 / 列表 | **有,插画+照片** | 只有词数 | `中阶(四级)` 带考试括号 | 题材 + 题源 | 每日 6 篇,超出要会员 |
| 薄荷阅读 | Mint Daily 大卡 / 猜你喜欢 / 书城 | 有 | 无 | `入门/初阶/中阶/中阶+/高阶` | 题材 + 真题 + 书单 | 书单/挑战付费 |
| 百词斩爱阅读 | 搜索 / 分类 tab / banner / 3列栅格 | 有,封面图 | 无 | 难度自选(官方称"强力算法") | 体裁(美文/考试/故事/演讲) | 官方翻译积分 |
| 流利说阅读 | 更偏"每日一篇" | 插画为主 | 无 | 先做**词汇量测试**再定级 | 无强分类 | 全文精讲付费 |
| 每日英语听力 | 发现/分类/推荐 三 tab | 有 | 无(音频时长在播放器里) | 分级读物栏目 | **来源 + 体裁双维度** | VIP + 每日外刊 |
| 英语阅读(外刊头条) | 列表 | 有 | 无 | 无 | **纯来源**(经济学人/卫报/时代) | — |
| 可可英语 | — | 有 | 无 | **官方写明 CEFR 定级** | 来源+体裁+考试 | VIP |
| **用户给的标杆(截屏A)** | 大卡 / 发现更多 / 分类 tab / 列表 | **插画** | **有(60句·12分钟·美音)** | **Lv8** | 题材 | — |

> ⚠️ **重要发现**:用户截屏里那行 `💬 60句 · ⏱ 12分钟阅读 · 🔈 美音` 在这 8 款 App 的官方截屏里**一处都没出现**。这句元信息组合更像是 **ReadFlow 要超越它们的地方**,而不是"抄谁"。我们本来就已有 `wordCount / estMinutes / audioUrl`(见 `lib/services/material_library.dart` 的 `ShelfItem`),补 `句数` 和 `口音` 成本极低。

---

## 二、卡片视觉规格(可直接写进 Flutter 的 dp 数值)

### 2.1 基准与栅格

- 基准机型 **390 × 844 dp**(iPhone 14/15 逻辑分辨率)。
- 页面左右安全边距 **16 dp**(仓库已有 `Insets.page = EdgeInsets.fromLTRB(16,12,16,24)`,直接复用)。
- 可用内容宽 **390 − 32 = 358 dp**。
- 栅格间距:列间距 **12 dp**(`Gap.sm`),行间距 **12 dp**。

### 2.2 每日精读大卡(对应截屏 A 的主卡)

| 元素 | 数值 | 说明 |
|---|---|---|
| 卡片圆角 | **16 dp** | 直接复用 `Radii.cardRadius`(`Radii.card = 16`) |
| 卡片外边距 | 左右 16,上 8,下 16 | |
| 配图区 | **358 × 201 dp(16:9)** | 备选 3:2 = 358 × 239(更"杂志感",但一屏会被吃掉 38 dp);**建议 16:9** |
| 配图裁切 | `BoxFit.cover`,顶部圆角 16 dp(底部 0) | 用 `ClipRRect(borderRadius: BorderRadius.vertical(top: Radius.circular(16)))` |
| 配图占位 | 16:9 灰底 + `Icons.image_outlined` 40 dp 居中,透明度 0.25 | 加载中/无图都用它,不要空白 |
| 图上左下角可选浮层 | 距左 12 / 距下 12,`日期` 白字 12 sp + 16% 黑遮罩 | 只在"每日一篇"用 |
| 卡内边距 | **14 dp**(复用 `Insets.card`) | 与 AppCard 一致 |
| 标签行高 | 24 dp | |
| 标签样式 | 高 **24**,左右 padding **10**,圆角 **8**(`Radii.control = 10` 亦可,建议 8 更硬朗) | |
| 标签-标题间距 | **8 dp** | |
| 英文主标题 | **18 sp / w700 / height 1.30**,最多 **2 行**,溢出省略 | 358−28=330 dp 宽下,18 sp 约 **34–36 字符/行** |
| 标题-副标题间距 | **6 dp** | |
| 中文副标题 | **14 sp / w400 / height 1.45**,最多 **1 行**,`textSecondary` | |
| 副标题-元信息间距 | **10 dp** | |
| 元信息行 | **12 sp**,图标 **14 dp**,图标与文字间距 **4 dp**,条目间分隔 **·** 两侧各 6 dp | |
| 元信息-按钮间距 | **14 dp** | |
| 按钮 | **整宽 × 48 dp 高**,圆角 **12**,主色填充,白字 **16 sp / w600**,`Icons.play_arrow_rounded` 20 dp + 8 dp 间隙 | |
| 卡片阴影 | `BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4))` | 深色模式下改为 0 阴影 + 1 dp `outlineVariant` 描边 |
| 卡片描边 | 浅色模式不加;深色模式 **1 dp** `darkOutlineVariant` | |

**一屏几张卡**:顶部大标题区约 88 dp(大标题 28 sp + 日期 14 sp)→ 大卡 201+~150 = **351 dp** → 屏内剩余约 400 dp,「发现更多」区块能露出 **2.5 张列表卡**(每张约 104 dp)。**结论:首屏必须能看到第三张卡的标题行**(证明下面还有内容)。

### 2.3 「发现更多」列表卡(横排:左文右图)

| 元素 | 数值 |
|---|---|
| 卡片高度 | **104 dp**(固定) |
| 圆角 / 内边距 | 16 dp / `EdgeInsets.symmetric(horizontal: 14, vertical: 12)` |
| 缩略图 | **96 × 72 dp(4:3)**,圆角 **12 dp**,`BoxFit.cover` |
| 文字列宽 | **358 − 28 − 96 − 12 = 222 dp** |
| 第一行 | 日期(`10月1日`,**11 sp**,`textSecondary`)+ 分类标签(高 20,圆角 6,11 sp) |
| 第二行 | 英文标题 **15 sp / w600 / height 1.28**,**最多 2 行** |
| 第三行 | 中文副标题 **12.5 sp**,1 行省略 |
| 竖排 Lv 徽标 | **宽 26 × 高 40 dp**,圆角 **8**,背景主色 12% 透明,`Lv` 10 sp + 数字 15 sp/w700 竖排(`Column`,行高 0.9);定位在缩略图**左侧外沿外 8 dp**,垂直居中 |
| 卡片间距 | **12 dp** |
| 分隔方式 | 用卡片(阴影)还是分隔线?→ **用卡片**;若追求信息密度(一屏 5 条)则改为「无卡片 + 1 dp 分隔线 + 垂直 padding 12」,两者选一,不要混用 |

### 2.4 分类 tab(chip 行)

- 高 **32 dp**,左右 padding **14**,圆角 **999**(胶囊)。
- 选中:主色填充 + 白字 **13.5 sp / w600**;未选中:`surfaceVariant` 填充 + 次文字色。
- chip 间距 **8 dp**,整行左右 padding 16 dp,横向滚动(不用 `TabBar`,用 `SingleChildScrollView` 更可控)。
- 选中态用 220 ms `Curves.easeOutCubic`(复用 `Motion.transition`)做颜色过渡 + 底部 2 dp 指示条滑入。
- **切换分类后列表要用 `AnimatedSwitcher`(180 ms 淡入),不要整页 loading 转圈** —— 转圈会让"切 tab"显得很慢。

### 2.5 等级徽标(Lv)三处变体

| 场景 | 尺寸 | 样式 |
|---|---|---|
| 大卡标签 | 高 24 × 自适应宽 | `Lv8` 单行,圆角 8,主色 12% 底 + 主色字 |
| 列表卡竖排 | 26 × 40 dp | 见上,`L` `V` `8` 竖排 |
| 详情页/阅读器 | 36 × 36 dp 圆形 | 只放数字,外圈 2 dp 主色环 |

> 只有**等级色**跟随体系变化:Lv1–3 用 `#28A745`(绿)/ Lv4–6 用 `#4A90D9`(蓝)/ Lv7–8 用 `#B45309`(琥珀)/ Lv9–10 用 `#C62828`(红);其余标签一律中性灰,避免"花"(这正是任务板第 8 条的同类问题)。

### 2.6 一屏信息量基准(验收标准)

| 屏 | 首屏必须出现 |
|---|---|
| 材料中心首页 | 大标题 + 日期 + 1 张大卡(含配图 + 中文副标题 + 等级 + 元信息 + 主按钮)+ 分类 chip 行 + **至少 2.5 张列表卡** |
| 分类页 | chip 行 + **至少 4.5 张列表卡** |
| 网格模式(可选,平板/横屏) | 2 列 × 3 行,封面比 **3:4 竖图**(书封场景) |

---

## 三、配图从哪来(含本机实测结果)

### 3.1 实测总表(2026-10-01,本机网络)

**[实测]** 以下是真实 HTTP 探测结果,不是查文档抄的:

| 源 | 测试 URL | 结果 | 可用于 |
|---|---|---|---|
| Gutenberg 封面 | `https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg` | **200 / 31,675 B / image/jpeg / 3.4 s** | ✅ 书籍材料封面 |
| Gutenberg 小图 | `.../pg84.cover.small.jpg` | 200 | ✅ 列表缩略图 |
| Gutenberg 搜索页 | `https://www.gutenberg.org/ebooks/search/?query=…` | 200,HTML 里真实存在 `<img class="cover-thumb" src="/cache/epub/84/pg84.cover.small.jpg">` | ✅ 抓封面 |
| Commons API | `https://commons.wikimedia.org/w/api.php?action=query&prop=pageimages&generator=search&gsrsearch=filetype:bitmap%20mountain&gsrnamespace=6&format=json` | **200 / JSON**,返回 `thumbnail.source` | ✅ 找图 |
| **Wikimedia 图床** | `https://upload.wikimedia.org/...` 与 `https://thumb.wikimedia.org/...` | ❌ **超时 20 s**(DNS 解析到 103.102.166.240,握手被重置) | ❌ **API 能查、图拿不到** |
| Wikipedia API | `https://en.wikipedia.org/w/api.php` | ❌ 超时;DNS 解析到 `31.13.94.37`(**Facebook 的 IP 段 = 典型 DNS 污染**) | ❌ |
| Gutendex | `https://gutendex.com/books` | ❌ `Recv failure: Connection was reset`(DNS 172.67.174.132,同样污染) | ❌ |
| Open Library | `https://openlibrary.org/…`、`https://covers.openlibrary.org/b/id/…-L.jpg` | ❌ 双双超时 | ❌ |
| Openverse | `https://api.openverse.org/v1/images/` | ❌ 超时;DNS 解析到 `31.13.87.33`(污染) | ❌ **一条都用不了** |
| Internet Archive | `https://archive.org/advancedsearch.php` | ❌ 超时 | ❌ |
| Unsplash 图床 | `https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=1200&h=675&fit=crop` | ✅ **200 / image/jpeg / 0.9–3.6 s**(走 IPv6) | ✅ 直接当配图 |
| Unsplash 随机源 | `https://source.unsplash.com/800x450/?nature` | ❌ **503(该服务已废弃)** | ❌ 别用 |
| Pexels 图床 | `https://images.pexels.com/photos/414612/pexels-photo-414612.jpeg?auto=compress&cs=tinysrgb&w=800&h=450&fit=crop` | ✅ **200 / image/jpeg** | ✅ 直接当配图 |
| Pixabay 图床 | `https://cdn.pixabay.com/photo/2015/04/23/22/00/tree-736885_1280.jpg` | ✅ 200 | ✅ 直接当配图 |
| Bing 每日图 | `https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=2&mkt=zh-CN` | ✅ **200 / 0.37 s / 解析到国内 IP 202.89.233.100** | ✅ **最稳** |
| arXiv API | `https://export.arxiv.org/api/query?search_query=all:electron&max_results=1` | ✅ 200,返回 Atom XML | ✅ 论文元数据 |
| 知乎 / BBC RSS | — | ❌ 403 / 超时 | ❌ |

> ⚠️ **重要口径说明**:这是**本机(用户 Windows 11 + 该出口网络)**的真实结果。用户机器上能连 Unsplash/Pexels **不等于终端用户能连** —— 移动端在中国大陆直连 `images.unsplash.com` 经常不稳。**下面 3.3 的方案 B/C 才是给终端用户用的**。

### 3.2 URL 规律手册(可直接写进 Dart)

```dart
// ── A. Gutenberg 公版书封面(已实测 200)─────────────────────────
// 有封面:https://www.gutenberg.org/cache/epub/{id}/pg{id}.cover.medium.jpg   // 约 31675 B
//         小图  pg{id}.cover.small.jpg
// 无封面:404  → 必须做兜底(见 3.4)
// 详情页 <meta property="og:image"> 就是同一个 URL,可用于二次校验
String gutenbergCover(int id, {bool small = false}) =>
    'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.${small ? 'small' : 'medium'}.jpg';

// ── B. Commons 找图(API 实测 200,但图床实测超时)──────────────
// 只建议**服务端**用,拿到 URL 后转存自己的 CDN
const commonsSearch =
    'https://commons.wikimedia.org/w/api.php?action=query&format=json'
    '&prop=pageimages&piprop=thumbnail&pithumbsize=800'
    '&generator=search&gsrnamespace=6&gsrsearch=filetype:bitmap%20{关键词}';
// 真实返回(实测):
// {"query":{"pages":{"125747465":{"title":"File:Everest, Himalayas.jpg",
//   "thumbnail":{"source":"https://thumb.wikimedia.org/wikipedia/commons/thumb/9/90/
//     Everest%2C_Himalayas.jpg/960px-Everest%2C_Himalayas.jpg?...&width":800,"height":533}}}}}
// 注意:返回的 source 指向 thumb.wikimedia.org → 本机实测超时,需替换 host 或转存

// ── C. Bing 每日图(实测 200 / 0.37 s / 国内 IP)→ 推荐做兜底 ──
// 列表: https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=zh-CN
//   → images[].urlbase           例:/th?id=OHR.OlmstedPoint_ZH-CN4182671075
//   → 带尺寸: https://www.bing.com{urlbase}_1920x1080.jpg
//   → 裁成 16:9 卡片: https://www.bing.com{urlbase}_800x450.jpg  (Bing 支持自定义 _WxH)
//   → 还有 images[].copyright 字段(例:"奥姆斯特德的日落…(© Robb Hirsch/Tandem Stills + Motion)")
//     和 images[].title(例:"在花岗岩中读懂时间")→ 可当"今日配图"的说明,版权署名现成的

// ── D. Unsplash / Pexels / Pixabay 直链(实测 200)─────────────
// Unsplash(需要 photo id,不能随机):
'https://images.unsplash.com/photo-{id}?w=800&h=450&fit=crop&q=75&fm=jpg'
//   ⚠️ 必须带 &w=&h=&fit=crop,否则返回原始 4000px 大图(流量灾难)
//   ⚠️ source.unsplash.com 已废弃(实测 503),别写
// Pexels(photo id 在 URL 里,可不带 key 直链):
'https://images.pexels.com/photos/{id}/pexels-photo-{id}.jpeg?auto=compress&cs=tinysrgb&w=800&h=450&fit=crop'
// Pixabay:
'https://cdn.pixabay.com/photo/{y}/{m}/{d}/{h}/{name}-{id}_1280.jpg'  // 路径含上传日期,不适合凭 id 猜

// ── E. RSS 里的图(feed_parser 已经在做的事,只差暴露出来)──────
// <media:content url="…jpg" type="image/jpeg">    ← Yahoo Media RSS
// <media:thumbnail url="…">                        ← 已匹配
// <itunes:image href="…">                          ← 已匹配
// <enclosure url="…jpg" type="image/jpeg">         ← 已匹配
// 另外两级兜底:item 内嵌 <img src>；再不行抓原页 <meta property="og:image">
```

### 3.3 给终端用户的三条落地方案(按推荐度)

**方案 A(推荐,覆盖 90% 场景):`og:image` + RSS 图 + 本地 CDN 缓存**
1. 入库时抓原页 `<meta property="og:image">`(几乎所有新闻站都有,国内站也有);
2. RSS 源直接用 `media:content / media:thumbnail / itunes:image / enclosure`(仓库已解析);
3. **首屏取图一律走自建图床 / 对象存储缓存**(Flutter 端只请求 `https://<你的域名>/img/{sha1}.jpg`),服务端回源失败就落兜底图。
   → 这样终端用户永远不直连境外图床,大陆网络 100% 可达。

**方案 B(零服务端,只做缓存):`cached_network_image` + Bing 兜底**
- 直链只允许 **Bing / 国内可用源**;Unsplash/Pexels 只作为"服务端能连时"的回源;
- 兜底用 Bing 每日图池(实测国内 IP 0.37 s),**用 `articleId.hashCode % pool.length` 确定性选取** —— 同一篇文章每次刷新配图一致,不然列表会"闪来闪去"。

**方案 C(离线/纯本地,最稳):程序化生成封面**
- 用 `title.hashCode` 生成 **HSB 色相**(S 55% / B 82%),叠一个 40 dp 的题材图标(科学=`science`、商业=`trending_up`、旅行=`flight`…),再叠英文首字母大写。
- 优点:零网络、零版权、永不 404、深色模式免费;**缺点:比插画差一档**。
- 建议:**A/B 失败时的最终兜底,不要当主方案**。

### 3.4 版权与合规(必须看)

| 源 | 版权 | 中国大陆直连 | 结论 |
|---|---|---|---|
| Gutenberg 封面 | 公版(PD),可商用 | 实测可达 | ✅ 书籍材料首选 |
| Commons / Wikipedia | CC-BY-SA / PD,需署名 | **API 可达、图床不可达** | ⚠️ 只能服务端用 + 转存 + 保留署名 |
| Bing 每日图 | ⚠️ **Bing 官方明确写"此图片不能下载用作壁纸 / 仅限用作桌面壁纸"**(实测 JSON 的 `tooltips.walle`/`walls` 字段) | ✅ 很快 | ⚠️ **不能当商用素材直接用**;做内部占位/开发期兜底可以,上架前必须换掉 |
| Unsplash | Unsplash License,免费商用、免署名(不强制) | ⚠️ 本机可达,终端不稳 | ⚠️ 必须缓存到自己的图床 |
| Pexels | Pexels License,免费商用 | 同上 | ⚠️ 同上 |
| Pixabay | Pixabay License,免费商用 | 同上 | ⚠️ 同上 |
| Openverse | 聚合 CC 内容,须逐条看许可 | ❌ 域名不可达 | ❌ 别考虑 |
| RSS / `og:image` 原图 | **归原媒体所有** —— 用于"链接预览/聚合摘要是行业惯例,直接永久存图库有风险** | 通常可达 | ⚠️ 只做列表预览,不提供下载/导出;详情页显著位置给「查看原文」链回 |
| 自绘/自购插画 | 自有 | ✅ | ✅ **想做到截屏 A 那种手绘水彩质感,只有这条路** |

> **一句结论**:截图 A 的"手绘水彩插画"是**自有版权图库**的产物,任何公开图源都给不了那个质感。想真的达到那个观感,只有两条路:① 自购插画库(如 Storyset / unDraw Plus / 站酷约稿,一次性几万)或 ② **用 AI 生图给每篇材料统一生成一张**(成本 ≈ 0.1 元/篇,风格可锁 prompt),然后缓存。**这是"要不要真的追平标杆"的分水岭,需要用户拍板。**

---

## 四、Lv1–Lv10 等级体系

### 4.1 结论先行:等级必须由两个量合成

- **文本难度 T(T for Text)**:这篇文章有多难 → 决定卡上的 `Lv` 标签;
- **个人匹配 M(M for Match)**:这篇文章对**这个人**有多合适 → 决定"适合你"提示与排序。

市面上的 Lv 标签(含用户截屏里的 `Lv8`)**只做了 T 没做 M**,所以同一个 Lv8 对学霸太简单、对新手太难。**我们把 M 显式展示出来,是差异点。**

### 4.2 文本难度 T 怎么算(可直接实现)

**步骤 1:算文本的可读性指标**(公式为公开标准算法,可直接实现):

```
Flesch Reading Ease  = 206.835 − 1.015 × ASL − 84.6 × ASW
Flesch–Kincaid Grade = 0.39 × ASL + 11.8 × ASW − 15.59
ARI   = 4.71 × (chars/words) + 0.5 × (words/sentences) − 21.43
SMOG  = 1.0430 × sqrt(polysyllables × 30/sentences) + 3.1291   // 建议 ≥30 句
Dale–Chall = 0.1579 × PDW + 0.0496 × ASL (+3.6365 若 PDW > 5%)
  其中 ASL = 平均句长(词/句),ASW = 平均词长(音节/词),
       PDW = 不在 Dale-Chall 3000 常用词表内的词占比
```
> 音节数是这几个公式的共同输入。英文近似的**可靠启发式**(比"数元音组"准得多):
> 1. 去尾 `e`(保留 `le` 结尾,如 `table`);
> 2. 相邻元音组只算 1 组;3. 结果至少 1。**必须配一份常见词音节表兜底**(`the/people/business` 这类会被规则算错)。

**步骤 2:映射到 Lv1–10** —— 建议用**多信号加权**而不是单一公式(单一公式在新闻短讯上会误判):

```dart
int textLevel(Text t) {
  // 1) 词汇分布(权重最高):按词频表把正文分成 5 档
  //    档位:NGSL 1-1000 / 1001-2000 / 2001-2800 / 学术词表 AWL / 表外专有名词
  final w = t.tokenCount;
  final core1 = t.inWordList(ngsl, 0, 1000)  / w;   // 例:0.82
  final core2 = t.inWordList(ngsl, 1000, 2000) / w; // 例:0.10
  final acad  = t.inWordList(awl) / w;              // 例:0.03
  final rare  = 1 - (core1 + core2 + acad);         // 例:0.05

  // 2) 句法复杂度
  final asl   = t.avgSentenceLength;  // 词/句
  final sub   = t.subordinateRatio;   // 含从句的句子占比

  // 3) 篇章因素(同 Lv 下,长文更"重")
  final load  = t.tokenCount / 1000.0;

  final score = 0.45 * (1 - core1 - 0.5 * core2)   // 1 档词越少越难
              + 0.20 * acad
              + 0.15 * ((asl - 12) / 18).clamp(0, 1)
              + 0.10 * sub
              + 0.10 * (load / 3).clamp(0, 1);

  return (1 + (score * 9)).round().clamp(1, 10);   // → Lv1..Lv10
}
```

### 4.3 Lv ↔ 词汇量 ↔ CEFR ↔ 蓝思 ↔ 生词率 映射表

| Lv | 词族量(参考) | CEFR | 蓝思(参考区间) | 目标生词率 | 典型人群 | 一句话描述 | 依据 |
|---|---|---|---|---|---|---|---|
| Lv1 | 500–1000 | A1 | BR–200L | ≤2% | 小学高年级 | 每句不到 8 个词,看图能猜 | **[行业共识]** CEFR A1≈500–1000 词 |
| Lv2 | 1000–1500 | A1+/A2 | 200L–400L | ≤3% | 初一 | 高频词讲日常事 | 同上 |
| Lv3 | 1500–2000 | A2 | 400L–600L | ≤4% | 初三 / 中考 | 能读简短新闻与故事 | A2≈1500–2500 |
| Lv4 | 2000–3000 | A2+/B1 | 600L–800L | ≤5% | 高一 / 四级起步 | 常见话题无障碍 | B1≈3000 |
| Lv5 | 3000–4000 | B1 | 800L–1000L | ≤5% | 高二 / 四级 | 能读外刊简讯 | **[我的设计建议]** 区间切分点 |
| Lv6 | 4000–5500 | B1+/B2 | 1000L–1150L | ≤6% | 大一 / 六级 | 能读常规新闻报道 | 六级≈5500–6000 |
| Lv7 | 5500–7000 | B2 | 1150L–1260L | ≤7% | 六级 / 考研 | 能读社论与深度报道 | 考研≈5500 词 |
| Lv8 | 7000–8500 | B2+/C1 | 1260L–1380L | ≤8% | 考研 / 雅思 6.5 | 能读《经济学人》主体文章 | C1≈8000 |
| Lv9 | 8500–10000 | C1 | 1380L–1500L | ≤8% | 雅思 7+ / 专八 | 能读学术论文引言 | 专八≈10000–13000 |
| Lv10 | 10000+ | C2 | 1500L+ | — | 接近母语 / GRE | 文学修辞、长难句自由 | C2≈16000–20000 |

> ⚠️ **不确定项**:CEFR↔蓝思的官方对照表由 MetaMetrics 发布(A1 ≈ 510L–620L 一类区间在论文中被广泛引用),但**各家转写区间不一致**;上表蓝思列是**平滑内插的结果,不是权威对照**,产品上建议**不要显示蓝思数字给用户**(中国用户不认),只在后台用于排序。

### 4.4 个人匹配 M 与「i+1」怎么落地

**理论依据 [行业共识]**:Hu & Nation (2000) 比较了 80%/90%/95%/100% 文本覆盖率对阅读理解的影响,通行结论是 **98% 覆盖率可支撑"独立阅读"**,**95% 是"有支持的阅读"下限**(Laufer 1989 也给出 95% 用于语境猜词的阈值)。这正是 **i+1** 的量化口径。

```dart
// 已知词覆盖率:用「用户已知词集」∩「文章词集」加权(按出现次数,不是按词型)
double knownCoverage(Set<String> known, List<String> tokens) {
  int hit = 0;
  for (final t in tokens) { if (known.contains(lemmatize(t))) hit++; }
  return hit / tokens.length;                 // 目标区间 0.95 – 0.98
}

// 匹配度(0–100):以 98% 为满分锚点,1 个生词 ≈ 扣 5 分(6.3 个已见词/生词)
int matchScore(double cov) =>
    ((cov - 0.90) / 0.08 * 100).round().clamp(0, 100);
// cov=98% → 100 分;95% → 62.5;92% → 25;90% → 0
```

**UI 表达(卡片上就这么写)**:

| 覆盖率 | 匹配度 | 卡片提示文案 | 颜色 |
|---|---|---|---|
| 99%+ | — | `太简单了 · 建议跳级` | 中性灰 |
| **96–98%** | 75–100 | **`刚好适合你 · 已知 97%`** | 绿 `#28A745` |
| 93–95% | 37–62 | `有点挑战 · 已知 94% · 约 12 个生词` | 琥珀 `#B45309` |
| 88–92% | 0–25 | `需要带读 · 已知 90% · 约 24 个生词` | 橙 |
| <88% | 0 | `先攒基础 · 建议从 Lv{n-1} 开始` | 灰 |

一句话总结:**`Lv8` 告诉用户"这文章多难",`已知 97%` 告诉他"你能不能读"** —— 后者才是让人点进去的那句话。

---

## 五、「查阅了 xxx」流式过程展示

### 5.1 主流产品怎么做的(逐家)

> ⚠️ **口径声明**:本节基于公开报道 + 通行 UI 观察整理。**Kimi / 豆包 / 秘塔 / DeepSeek 的登录后界面本次无法直接抓取(域名受限)**,所以逐条文案标注为 **[公开报道]** 或 **[通行写法·需复核]**。Perplexity 的步骤文案来自其产品通行认知,同样标 **[通行写法]**。

| 产品 | 展示的步骤(顺序) | 来源列表形态 | 失败态 |
|---|---|---|---|
| **Perplexity** | ① 先亮出它自己改写的搜索词(多条并列)② 每条的进度(`Searching` → `Reading sources`)③ 折叠头显示耗时(`Pro search · 8s`)④ 正文里 `[1][2]` 行内角标 [通行写法] | 答案**上方**横滑 `N sources` 卡片(域名 + 标题 + 缩略图),点开右侧抽屉 [通行写法] | 保留已得来源 + 顶部 `Something went wrong` + Retry [通行写法] |
| **Kimi 探索版** | **自主规划策略 → 并行检索几十个关键词 → 精读数百个页面 → 反思补充** [公开报道:发布时官方描述"模拟人类的推理思考过程,多级分解复杂问题",一次搜索精读 500 个页面,搜索量是普通版 10 倍] | 答案里编号角标 + 底部来源列表 [公开报道] | 未公开 |
| **秘塔 AI 搜索** | **全网搜索 → 阅读网页 → 生成大纲 → 生成正文**;可切「全网/学术/播客」范围 [通行写法·需复核] | 右侧「来源」面板,按网站归类 [通行写法] | 提示"没有找到相关结果",引导换关键词 [通行写法] |
| **DeepSeek 网页版** | 默认**不展示中间步骤**,只在答案上挂引用编号;开启联网后有一段"搜索中" [通行写法] | 答案下方编号来源卡片 [通行写法] | 明确提示未联网/未找到 |
| **豆包** | 「深度思考」把推理链**可视化**展开(官方称"AI 逻辑链条可视化")[公开报道] | 来源卡片 | — |
| **天工 / 元宝 / Genspark / Felo** | 普遍是「规划 → 搜索 → 阅读 → 写作」四段式折叠面板 [通行写法] | 多为侧栏/底部抽屉 | 多数降级为"直接回答" |

**可提炼的三条共性(可直接照抄)**:
1. **过程可折叠、默认展开进行中、完成后自动收起**并留一行"已完成 · 用时 Xs · 阅读 N 篇"可点开回看;
2. **步骤文案是"动词 + 对象"**(检索网页/阅读来源/整理要点),不是"加载中…";
3. **来源在正文之前就出现**,先给"我找到了什么"再给"我怎么想"—— 这是信任感的来源。

### 5.2 状态机(照抄即可)

```
                    ┌──────────────┐
        submit ───▶ │  preparing   │  准备:解析需求/命中缓存/定计划
                    └──────┬───────┘
                           │ 计划就绪(或 400ms)
                    ┌──────▼───────┐
                    │  searching   │  检索中:并行多路(题库/RSS/外刊/网页)
                    └──┬────────┬──┘
             命中>0 ───┘        └─── 命中=0
        ┌──────────▼─────────┐  ┌──▼──────────┐
        │      found         │  │   empty     │
        │ 找到 N 篇(首个结果)│  │ 无结果(可改条件)│
        └──────────┬─────────┘  └─────────────┘
                   │ 开始逐篇读
        ┌──────────▼─────────┐
        │     analyzing      │  阅读来源:第 k/N 篇、抽词、算难度
        └──────────┬─────────┘
                   │ 首 token
        ┌──────────▼─────────┐
        │    generating      │  生成结果:流式吐卡片
        └──────────┬─────────┘
         完整 ─────┴───── 部分源失败
   ┌──────────▼───┐   ┌───▼──────────┐
   │     done     │   │   partial    │
   └──────────────┘   └──────────────┘
                   │ 任一步硬失败/超时
              ┌────▼─────┐
              │  error   │  失败(可重试 + 降级)
              └──────────┘
```

**关键工程口径「真事件 + 最短展示时长」**:
- 后端每完成一步就推一个事件(SSE / WebSocket),前端**只渲染真事件**;
- 但每个状态设 **最短展示 600 ms** —— 否则快的时候文字"闪一下"更难看;
- 若某步 > **2.5 s** 无事件:文案自动加"仍在检索…",同时把已完成的子项打勾;
- 总时长 > **8 s**:文案升级为"正在深入检索(已阅读 {k} 篇)",并允许用户离开 → 完成后发本地通知;
- > **20 s**:显示「先看已有结果」按钮,把已找到的 N 篇先渲染出来(渐进式渲染,而不是等全量)。

> 数值依据 **[行业共识]**:3 s 内必须有可见反馈;>10 s 必须给可读的进度而不是无限转圈。

### 5.3 每个状态的文案模板(中英各一套,可直接粘)

| 状态 id | 触发 | 中文文案 | English | 图标 | 最短展示 |
|---|---|---|---|---|---|
| `preparing` | 点击「找材料」 | `正在理解你的需求…` | `Understanding your request…` | `Icons.psychology_outlined` 微旋转 | 400 ms |
| `planning`(可选) | 拿到计划 | `已拟好 {n} 条检索方向` | `Planned {n} search paths` | `Icons.checklist_rounded` | 600 ms |
| `searching` | 发出检索 | `正在检索 {scope}…`(scope 例:题库 / 外刊 / 网络) | `Searching {scope}…` | `Icons.travel_explore` 呼吸缩放 | 600 ms |
| `searching.multi` | 多路并行 | `并行检索 {n} 个方向…` | `Searching {n} sources in parallel…` | 同心圆涟漪 | 600 ms |
| `found` | 首个命中 | **`找到 {count} 篇候选`** | `Found {count} candidates` | `Icons.article_outlined` | 800 ms |
| `analyzing` | 开始逐篇读 | **`正在阅读第 {k}/{n} 篇 · {domain}`** | `Reading {k}/{n} · {domain}` | `Icons.menu_book_outlined` | 400 ms |
| `analyzing.long` | 2.5 s 无事件 | `还在读 {domain},稍等…` | `Still reading {domain}…` | 同上 + 省略号动画 | 400 ms |
| `analyzing.deep` | 总时长 > 8 s | `正在深入检索 · 已阅读 {k} 篇` | `Deep search · {k} sources read` | 同上 | — |
| `filtering` | 读完后筛选 | `从 {n} 篇里挑出 {m} 篇最适合你的` | `Kept {m} of {n} for your level` | `Icons.filter_alt_outlined` | 500 ms |
| `generating` | 首 token | `正在生成推荐…` | `Generating recommendations…` | `Icons.auto_awesome` | — |
| `done` | 结束 | **`查阅了 {count} 篇 · 用时 {seconds} 秒`** | `Reviewed {count} sources · {seconds}s` | `Icons.check_circle_outline` 绿色 | — |
| `empty` | 命中 0 | `没找到匹配的材料 —— 换个说法,或放宽难度试试` + `[放宽难度] [换个方向]` | `No matches. Try broader terms or an easier level.` | `Icons.search_off_rounded` | — |
| `partial` | 部分源失败 | `有 {failed} 个来源没响应,先用这 {ok} 篇` | `{failed} sources failed; showing {ok}.` | `Icons.warning_amber_rounded` 琥珀 | — |
| `error` | 硬失败 | `检索失败了(网络或服务超时)` + `[重试] [看热门材料]` | `Search failed.` + `Retry` / `Browse popular` | `Icons.error_outline` 红 | — |

**折叠头的三态文案(最常被看到的一行,单独优化)**:

```
进行中  ⟳ 查阅了 3 篇…                          [展开 ▾]
完成    ✓ 查阅了 12 篇 · 用时 6 秒               [展开 ▾]
失败    ⚠ 部分来源未响应(查到 5 篇)              [重试]
```
> 「查阅了 xxx」这个说法本身很好(拟人、克制、有信息量),**建议保留并补上"用时 N 秒"和"来源数"**——这是 Perplexity 那条折叠头最值钱的两个数字。

### 5.4 Flutter 落地建议

- 用 `AnimationController` + `AnimatedSwitcher`(200 ms,`Curves.easeOutCubic`)在状态间切换,**不要用 `CircularProgressIndicator` 独占一屏**;
- 步骤列表用 `ListView.builder` 只渲染已完成 + 当前项,老步骤**折叠成一行**;
- 完成态整块可点开回看(`ExpansionTile` 风格,但自己写以控制动画);
- **无障碍**:给状态行加 `Semantics(liveRegion: true, label: ...)`,转场动画在 `MediaQuery.disableAnimations` 为真时退化为静态;颜色之外必须有图标区分状态(绿勾/琥珀叹号/红叉),不要只靠颜色。

---

## 六、本 App 可直接落地的 10 条改造清单(按性价比排序)

> 性价比 = 用户可感知收益 ÷ 改动成本。前 3 条是"零新增网络、零新增数据"就能做完的。

| # | 改什么 | 具体动作 | 涉及文件 | 改动量 | 为什么排这 |
|---|---|---|---|---|---|
| **1** | **列表/推荐卡加配图 + 中文副标题** | ① `ShelfItem` 增 `String? imageUrl`(已有 `title/kind/source/cefr/wordCount/estMinutes/audioUrl`,只缺图);② 新组件 `MaterialCoverImage`:`16:9`(`AspectRatio`)+ `Radii.cardRadius` 顶部裁切 + 失败/加载时退化为**程序化封面**(`title.hashCode` 取 HSB 色 + 题材图标);③ 卡片改成**左文右图**:缩略图 `96×72`、圆角 12、右间距 12 | `lib/services/material_library.dart`、新增 `lib/widgets/material_cover_image.dart`、`category_material_screen.dart`、`material_center_screen.dart` | ~250 行 + 加 1 个 DB 字段 | 直击"整个软件全是字"这条原话,一改就变样。**先做"程序化封面兜底",一张网图都不用连** |
| **2** | **卡片元信息补齐:等级 + 认知率 + 句数 + 口音** | ① `ShelfItem` 增 `int level`(由第 5 条的 T 算)、`double? personalCoverage`;② 卡片元信息行按用户标杆排:`💬 60句 · ⏱ 12分钟 · 🔈 美音`(`Icons.chat_bubble_outline/schedule/volume_up`,14 dp 图标 + 12 sp 字);③ 加「刚好适合你 · 已知 97%」提示 | `material_library.dart`、`material_center_screen.dart` | ~180 行 | 仓库**已有 `wordCount/estMinutes/audioUrl/coverage`**,只差句数与口音,是"最便宜的高级感" |
| **3** | **大卡升级为「每日精读 + 开始阅读」** | ① 顶部:大标题「每日精读」28 sp/w700 + 日期 14 sp「星期四 · 10月1日」;② 大卡 = 16:9 图 + 标签行(题材 / `Lv{n}`)+ 英文标题 18 sp 两行 + **中文副标题**(复用已有翻译/摘要)+ 元信息 + 整宽 48 dp 主按钮「▶ 开始阅读」;③ 图表尺寸严格按 §2.2 | `material_center_screen.dart`(拆出 `_DailyCard` 子组件) | ~300 行 | 首屏观感 80% 由这一张卡决定;`estMinutes` 与 `audioUrl` 都现成 |
| **4** | **流式「查阅了 xxx」** | ① 新增 `lib/widgets/stream_progress_panel.dart`,实现 §5.2 状态机 + §5.3 文案表;② 把「个性化找资源」现有的单一转圈(`material_center_screen.dart` 附近)替换为它;③ 后端把每个检索步骤用 SSE 事件推出来 | 新增 widget + `material_recommend_service.dart` / `original_search.dart` / `category_material_screen.dart` | ~450 行 | 用户点名的第 6(4) 条;视觉冲击强,但依赖后端事件改造 → 排第 4 |
| **5** | **等级体系落成一套算法** | ① 新增 `lib/services/text_difficulty.dart`:实现 §4.2 的 `textLevel()`,以及 FK/ARI/SMOG/覆盖率的计算;② `MaterialAnalysis` 增 `int level`;③ 卡片显示 `Lv{n}` + 「已知 x%」;④ 与已有 `cefr` 字段做一致性校验(不一致以 level 为准并记录) | 新增 service、`material_library.dart` | ~300 行 + 词表资源 | 没等级就没有"发现感";但算法需要词表(建议内置 **NGSL 2800** 词表,约 30 KB),故排第 5 |
| **6** | **配图数据管道** | ① `FeedParser` 增 `imageOf(itemXml)`:复用已有 `_mediaContentTag`/`_enclosureTag`/`_attr` 正则,优先取 `type` 含 image 或扩展名为图片的 URL;② 无则抓原页 `<meta property="og:image">`;③ 书籍材料用 `gutenbergCover(bookId)`(实测 200);④ 全部失败 → 程序化封面 | `feed_parser.dart`(复用现有正则)、`material_import.dart`、`material_source.dart` | ~220 行 | **与第 1 条配对的"真图"来源**;`feed_parser` 里已经写好了大部分正则,几乎白捡 |
| **7** | **分类页加 AI 对话入口** | 每个分类页顶部放一条「没找到想要的?告诉我你更想要什么 →」输入条,复用 `ai_material_search.dart` + `material_recommend_service.dart`,把当前分类作为预置条件注入 prompt | `category_material_screen.dart` | ~200 行 | 用户第 6(5) 条;复用现成服务,成本低但价值明确 |
| **8** | **分类维度重构为「题材 × 题源 × 等级」三轴** | 参考截屏:`科学与技术 / 商业与政治 / 旅行与体验 / 健康与生活 / 人文历史 / 心理成长`(题材)+ `四六级 / 考研 / 雅思托福`(题源)+ 难度筛选条(参考薄荷的 `入门/初阶/中阶/高阶` + 天数/长度筛选) | `material_center_screen.dart` 的分类定义、`material_source.dart` 源标签 | ~250 行(主要是定义与标签映射) | 内容编排问题,收益长期;放在能力项之后 |
| **9** | **图片缓存 + 兜底** | ① `pubspec.yaml` **目前没有 `cached_network_image`**(已查:只有 `dio ^5.7.0` / `image_picker` / `image` / `image_cropper`),需新增;或者直接用已有的 `dio` + `image` 手写一个磁盘缓存(约 80 行,省一个依赖);② 一律请求**自建/国内可达**域名,境外图床只做服务端回源;③ 兜底链:原图 → Bing 池(确定性 hash 选取)→ 程序化封面;④ 定期清缓存(设置页给"清理图片缓存") | `pubspec.yaml`、`material_cover_image.dart` | ~150 行 | 不做这条,第 1/6 条的图在弱网下会变成一片灰 |
| **10** | **「更多操作」弹层 + 分享海报** | 文章页「更多」:分享文章(生成阅读海报)/ 导出 PDF / 问题反馈 / 举报内容,四条;海报复用现有分享能力 + 一张带标题/等级/二维码的合成图 | `material_reader_screen.dart`、`lib/widgets/reader_action_bar.dart` | ~350 行 | 截屏 B 的内容;传播价值高但开发量大,放最后 |

**第一批建议只做 1 → 2 → 3**(合计约 700 行、零新增网络依赖),做完就能把"全是字"这条彻底翻篇,再动 4/5/6。

---

## 附:本次调研的可信度说明

- **[实测]** 的数据(HTTP 状态码、DNS 解析结果、JSON/HTML 响应体、封面 URL 规律)全部来自本次在本机的真实请求,可复现;
- **[截图观察]** 的内容来自 App Store 官方截屏原图,已下载到 `D:\readflow\.research\`(扇贝 5 张 / 薄荷 5 张 / 百词斩 5 张 / 流利说 5 张 / 每日英语听力 3 张 / 可可 3 张 / 英语阅读 2 张 / 轻听 1 张),像素测量基于这些原图;
- **无法核实**的部分已逐条标注:各 AI 搜索产品的登录后界面细节(域名不可达)、CEFR↔Lexile 的权威对照区间、各 App 会员墙的具体位置;
- 网络结论的适用范围:**本机 Windows 出口网络**,不等价于中国大陆移动网络;凡涉及终端用户可访问性的判断,已在 §3.3 单独给了保守方案。
