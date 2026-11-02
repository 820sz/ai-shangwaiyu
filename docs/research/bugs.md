# ReadFlow 4 个 Bug 根因侦查（v2.13.0+71）

> 本轮边界：**只读不改源码**。全部结论基于 `D:\readflow` 工作区代码静态阅读（git HEAD `eeea4b4` + 未提交改动仅 `.tmp-docx.txt`）；未运行 `flutter build/run/analyze`，行号以当前工作区为准。
> 侦查人：bug-hunter（子代理）｜产出时间：2026-11-01

## 总览

| # | Bug | 根因一句话 | 推荐修法 | 必改文件数 |
|---|---|---|---|---|
| 1 | 识图追问抽屉滚动位置丢失 | `lastScrollOffset` 只在「消息列表重建后的 postFrame」里记录，用户单纯滚动/收起抽屉时没有任何代码写回；且 modal 路由每次打开都是新 ListView | 抽屉内加 `scrollCtrl` 监听持续记录 + 还原时 clamp/重试；跨会话要记住再落 Hive | 1（+0~1 可选） |
| 2 | 移动词汇重复建分类 | 移动弹层选项是**完整 material_path**，`_moveInto` 又把它当"材料名"传给 `buildMaterialPath()` 二次拼前缀 → `书籍/书籍/《X》`；分组键=原始路径字符串 → 不会并入老分组 | 移动链路直接使用完整路径 + 纯函数 `normalizeMaterialPath` + dbVersion 19 一次性迁移 | 4（+2 测试） |
| 3 | 识图结果出现后追加图片概率闪退 | 追加入口 `pickMultiImage(maxWidth:2600, q92)`，首页入口是 `1024/q50`（同一功能两条入口参数不一致）；v2.13 新加的 `detectRotation` 让每张图**多一次整图解码**，全部在 UI isolate 同步跑；结果出现后自动跑的「高清分块复查」同时在解码 → 内存峰值 OOM / 主线程卡死被系统杀 | 应急：追加降到 1600/85 或与首页一致 + 复查期间禁用追加；根治：`VisionImagePrep` 移入后台 isolate + 串行预处理 + 追加前等复查结束 | 应急 1；根治 3 |
| 4 | 识图词汇卡片加音标 | **音标全链路早已打通**（提示词要、解析留、Vocabulary 有、SQLite 有 3 列、其它 5 处 UI 都显示），唯一缺口是识图结果「详细模式」卡片 `_buildDetailTile` 没渲染 | 只改 UI：把 `item.displayPhonetic` 放进词性 chip 那行的 `Wrap`。**不需要 DB 迁移** | 1（+1 测试） |

---

# Bug 1｜识图追问抽屉的滚动位置丢失

## 现象（用户原话）
> "识别图片功能里的追问抽屉的进度悬置问题——每次唤起追问抽屉再收起时，之前浏览的地方会没法停留保存，又得从头往下划"。

## 复现路径定位

- 识图结果页宿主：`lib/screens/input/process_chat.dart:1200-1208` `_openFollowUp()` → 调 `showFollowUpDrawer(...)`（**未 await**）。
- 抽屉实现：`lib/screens/input/widgets/follow_up_drawer.dart`
  - 承载方式 = **`showModalBottomSheet`（独立路由）+ 内嵌 `DraggableScrollableSheet`**，不是页面内 Stack：
    - `follow_up_drawer.dart:417-431` `showModalBottomSheet(...)`，builder 里是 `_FollowUpSheet`
    - `follow_up_drawer.dart:443-448` `DraggableScrollableSheet(initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.85, expand: false, builder: (ctx, scrollCtrl) => Column(...))`
  - 列表：`follow_up_drawer.dart:571-579` `ListView.builder(controller: scrollCtrl, ...)` —— **没有 key、没有 PageStorageKey、没有 AutomaticKeepAlive、不是 reverse**。
  - 关闭：拖拽条下滑/点遮罩都会 pop 这条 modal 路由 → `_FollowUpSheet`/`ListView`/`ScrollPosition` 全部 dispose，**下次打开是全新 Dart 对象**（`FollowUpController` 本身是页面级、不会 dispose，见 `follow_up_drawer.dart:389-400`，所以只能靠 controller 上那几个字段续命）。
  - 该抽屉是**共享组件**，5 个页面在用：`process_chat.dart:1202`、`write_review_screen.dart:186,612`、`material_reader_screen.dart:835,1395`、`material_recommendation_detail_screen.dart:334,586`（修一次全受益，回归面也大）。

## 根因（file:line + 关键代码）

### 根因 1（主因）：记录时机绑在“消息列表重建”上，用户滚动/收起时根本没有写入点

v2.6 已加过一版“记住位置”（`follow_up_drawer.dart:84-90`）：

```dart
/// 上次退出抽屉时停留在哪个位置(v2.6,用户实测"收起再点开又回到顶部")。
double lastScrollOffset = 0;

/// 打开抽屉后是否要把位置还原到 [lastScrollOffset](消费一次即清)
bool scrollRestorePending = false;
```

打开时置位（`follow_up_drawer.dart:403-415`）：

```dart
void showFollowUpDrawer({ ... }) {
  ...
  // v2.6:标记"这次打开要还原上次的滚动位置"
  controller.scrollRestorePending = true;
  ...
  showModalBottomSheet(...);
```

而 **`lastScrollOffset` 唯一的写入点**，在消息列表 `ValueListenableBuilder` 的 postFrame 里（`follow_up_drawer.dart:516-568`，关键段）：

```dart
Expanded(
  child: ValueListenableBuilder<List<FollowUpMessage>>(
    valueListenable: controller.messages,
    builder: (ctx, msgs, child) {
      ...
      if (!controller.scrollScheduled) {                    // :532
        controller.scrollScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.scrollScheduled = false;
          if (!scrollCtrl.hasClients) return;
          final pos = scrollCtrl.position;
          if (controller.scrollRestorePending) {            // :540 还原分支
            controller.scrollRestorePending = false;
            final target = controller.lastScrollOffset.clamp(0.0, pos.maxScrollExtent);
            if (target > 0) { scrollCtrl.jumpTo(target); ...; return; }
          }
          controller.lastScrollOffset = pos.pixels;          // :551 ← 唯一的记录点
          final nearBottom = pos.maxScrollExtent - pos.pixels < 150;
          if (controller.pendingScroll || nearBottom) { ... jumpTo(max) ... }
        });
      }
      return Stack(children: [ ListView.builder(controller: scrollCtrl, ...) ... ]);
    },
  ),
),
```

问题链：

1. `ValueListenableBuilder` 只在 `controller.messages` **内容变化**时重建（发新问、流式 chunk 到达、清空、载入历史）。用户“上下滑动浏览”**不改变 messages**，滚动事件也不会触发这个 builder。
2. 用户从打开 → 滚动到某处看 → 收起抽屉，全程**没有一次 messages 重建** → `lastScrollOffset` 从来没被更新（大多数情况仍是初始 `0`）。下次打开还原目标 = 0 → 原地跳 0 → 就是用户说的“又得从头往下划”。
3. 即使期间恰好收到流式 chunk 触发了重建，`lastScrollOffset = pos.pixels` 记录的是 **自动滚到底之前** 的位置，紧接着 `pendingScroll/nearBottom` 又把列表拉到底（`:552-566`），记录值和用户实际留下位置不一致。
4. 打开命中还原分支时 `return` 提前退出，**本次会话之后再没有任何机会记录**（要等下一次 messages 变化），“读一段 → 收起”这种最典型场景永远记不住。

### 根因 2（次因）：抽屉高度可变，像素 offset 跨打开会错位
`DraggableScrollableSheet` 允许用户把抽屉从 0.6 拖到 0.85，关闭时若停在 0.85，重开固定在 0.6 —— `maxScrollExtent` 不同，同一像素值指向的内容位置就变了。当前代码只做 `clamp(0, maxScrollExtent)`（`:543`），没有按比例/锚点换算。

### 根因 3（排除项）：`PageStorageKey` 单独用救不了
Flutter 的每个 `ModalRoute` 有**自己的** PageStorage bucket：SDK `packages/flutter/lib/src/widgets/routes.dart:1193` `PageStorage(bucket: widget.route._storageBucket, ...)`；而 `showModalBottomSheet` 每次都是**新建 route** → 新 bucket。所以给 ListView 加 `PageStorageKey`（或依赖 `ScrollPosition.keepScrollOffset` 的自动存取，SDK `scroll_position.dart:202-203 / 1052-1057`：只在 `restore` 构造时读、`didEndScroll` 时写）**跨打开无效**。要用 PageStorage 必须由页面/controller 持有一个显式 `PageStorageBucket` 包住抽屉内容 —— 本质等价于“自己存 offset”，收益不如直接监听。

## 修法

### 推荐：方案 A —— 抽屉内监听滚动持续记录 + 关闭前已有值 + 还原时 clamp/重试/比例换算（1 文件，风险低）

1. `_FollowUpSheet` 从 `StatelessWidget` 改成 `StatefulWidget`（或包一层私有 Stateful 包装），`initState` 里：
   ```dart
   widget.scrollCtrl.addListener(_onScroll);   // DraggableScrollableSheet 给的 controller
   void _onScroll() {
     final pos = widget.scrollCtrl.position;
     widget.controller.lastScrollOffset = pos.pixels;
     widget.controller.lastScrollExtent = pos.maxScrollExtent; // 新增字段
   }
   ```
   （若担心每帧 setState/写字段太频繁，可只写字段不 setState —— 这里本来就不需要 UI 重建，开销可忽略；也可按 delta>4px 节流。）
2. 把 `:551` 的“随手记住”和 `:552-566` 的自动滚底逻辑中的记录动作交给监听，避免记录值被“跳底前的位置”覆盖；`pendingScroll` 跳底后监听自然会把 offset 更新成底部。
3. 还原（`:540-548`）改成“最多重试 3 帧 + 比例换算”：
   ```dart
   void _tryRestore(int attempt) {
     WidgetsBinding.instance.addPostFrameCallback((_) {
       if (!mounted || !scrollCtrl.hasClients) { if (attempt < 3) _tryRestore(attempt + 1); return; }
       final pos = scrollCtrl.position;
       if (pos.maxScrollExtent <= 0) { if (attempt < 3) _tryRestore(attempt + 1); return; }
       final ratio = controller.lastScrollExtent > 0
           ? (controller.lastScrollOffset / controller.lastScrollExtent).clamp(0.0, 1.0)
           : 0.0;
       scrollCtrl.jumpTo((ratio * pos.maxScrollExtent).clamp(0.0, pos.maxScrollExtent));
     });
   }
   ```
   （`lastScrollExtent` 是新字段，与 `lastScrollOffset` 同生命周期，记录上次关闭时的 `maxScrollExtent`。）
4. 恢复 `scrollRestorePending` 的一次性语义；`showFollowUpDrawer` 里仍置 true。跨 App 重启还想记住 → 再把这两个值落 Hive（`AppConstants.hiveBoxSettings`，key 按 `historyKey` 区分），见“需确认的歧义”。

### 备选 1：保活抽屉（改动面 2 文件，收益最彻底、风险中）
把抽屉从 `showModalBottomSheet`（销毁型路由）改成页面内 `Stack` + `AnimatedSlide`/`Offstage`（或 `showBottomSheet` + 自己控制显隐），`_FollowUpSheet` 常驻 widget 树、`ScrollController` 由页面持有 → `ScrollPosition` 从不 dispose，滚动位置/输入框草稿/焦点全部天然保住。代价：5 个调用页面都要接入（`showFollowUpDrawer` 是共享入口，可保留 API 改为“页面内 overlay”），还要处理返回键/遮罩/焦点/内存常驻，回归面大。

### 备选 2：controller 持有 `PageStorageBucket` + 显式 `PageStorage` 包裹（1 文件）
在 `_FollowUpSheet` 外层包 `PageStorage(bucket: controller.scrollBucket, child: ...)`，ListView 加固定 `PageStorageKey('follow_up_list')`。依赖 `ScrollPosition.didEndScroll → saveScrollOffset`（SDK 已确认）与构造时 `restoreScrollOffset`，**不需要自己写监听**。缺点：只能记住“滚动停止时”的位置（拖拽中止/快速点遮罩可能没经过 didEndScroll，仍是边界 case），且要保证抽屉高度变化时的 clamp —— 推荐度低于方案 A。

### 不推荐
只给 ListView 加 `PageStorageKey`（理由见根因 3，跨 modal 路由 bucket 不共享）。

## 涉及文件与风险
- `lib/screens/input/widgets/follow_up_drawer.dart`：`_FollowUpSheet` 改 Stateful + 监听 + 还原逻辑；新增 `lastScrollExtent` 字段。
- 可选：`process_chat.dart:1202` 改成 `await showFollowUpDrawer(...)`（若要“关闭后立刻落 Hive”或做关闭动画回调）。
- 回归面：5 个使用抽屉的页面；`FollowUpController` 另有 `compact/slot` 等 notifier 不要动。
- 风险：低。注意不要在监听里 `setState`（会与流式 chunk 叠加重建）；`scrollRestorePending` 只消费一次，避免“每次流式 chunk 都把用户拽回旧位置”。

## 验证方式
1. 手动回归（V2.13 真机）：打开抽屉 → 上滑到中间 → 收起 → 再打开，**应停在原处**；换 3 条路径各测一遍：读旧对话（不发消息）、发一问后等流式结束再滚上去、清空后重开（“新建”后 `lastScrollOffset` 不应把空列表搞乱）。
2. 抽屉高度差异：拖到 0.85 滚动后收起 → 重开 0.6 时应“内容位置大致不变”（比例换算生效）。
3. 现有测试：`test/follow_up_slot_test.dart` 里有一条 `skip: true`（FakeAsync + bottom sheet 挂起，见 `docs/CODE-REVIEW-2026-09-19.md:224`），不要指望它；建议把“比例换算/还原重试”抽成纯函数（如 `resolveRestoreOffset(lastOffset,lastExtent,newExtent)`) 加普通单测，widget 层只做冒烟。
4. 未证实项：无法在纯静态下确认真机上“打开首帧 `scrollCtrl.hasClients` 是否必为 true”；修法里的 3 帧重试就是对此的防御。

---

# Bug 2｜词汇本“移动词汇”重复建分类

## 现象（用户截图证据）
移动弹层里同时出现两级的重复项：「书籍/《Character》」和「书籍/书籍/《Character》」；移动后的词汇不并入目标老分类，而是**重复新建分类**。

## 复现路径定位

- 入口：输入页 →「我的词汇本」→ 点某个分类（`my_materials_section.dart:62-74`）→ `_showCategoryVocabList`（`:113-131`）打开分类词汇 BottomSheet → 分组 `ExpansionTile` 展开 → 操作行「移动材料…」（`:786-793`）。
- 移动 UI **不在** `vocab_list.dart`，在 `lib/screens/input/widgets/my_materials_section.dart`：
  - `:318-416` `_moveToExisting({required String label, required List<Vocabulary> items})` —— 弹「移动到哪?」列表，选项来自数据库。
  - `:418-440` `_moveInto(String materialName, List<Vocabulary> items)` —— 真正写库。
- `lib/screens/profile/vocab_list.dart:109-155` 的「批量移动」是**另一条链路**，用的是 `showSubCategoryInput`（正确，见下），**不是**用户截图这条。`lib/utils/material_group.dart` 只有构造/分组的纯函数，不写库。

## 根因（file:line + 关键代码）

### 根因 1（直接原因）：移动目标把“完整路径”当“材料名”，二次拼接分类前缀

`my_materials_section.dart:331-338` 选项来源（完整 `material_path`）：

```dart
final paths = await DatabaseService.getMaterialPathsByCategory(
  widget.category,
);
if (!mounted) return;
final choices = <String>[
  for (final p in paths)
    if (p.trim().isNotEmpty && p != label) p,     // ← label 是显示名，和完整路径永远不相等
]..sort();
```

`database.dart:1189-1200` 返回的每个元素就是**完整路径**（`书籍/《Character》` 这种）：

```dart
static Future<List<String>> getMaterialPathsByCategory(String category) async {
  final db = await database;
  final rows = await db.rawQuery(
    "SELECT DISTINCT material_path FROM vocabulary "
    "WHERE category = ? AND material_path IS NOT NULL AND material_path != '' "
    "ORDER BY material_path",
    [category],
  );
  return rows.map((r) => r['material_path'] as String).toList();
}
```

弹层把 `p` **原样显示**（`:375-391`，`title: Text(p)`）→ 用户看到 `书籍/《Character》`。点选后（`:410-415`）→ `_moveInto(picked, items)`：

```dart
/// 真正把这批词移到目标材料下(不弹任何对话框,选完即生效)
Future<void> _moveInto(String materialName, List<Vocabulary> items) async {
  final ids = items.map((v) => v.id).whereType<int>().toList();
  if (ids.isEmpty) return;
  await context.read<VocabProvider>().moveVocabularies(
        ids,
        category: widget.category,
        materialPath: buildMaterialPath(          // :425 ← 这里二次拼前缀
          category: widget.category,
          name: materialName,                     // 传进来的是 "书籍/《Character》"！
        ),
        sourceBook: materialName,                 // :429 ← source_book 也被写成完整路径
      );
```

`material_group.dart:66-75`：

```dart
String buildMaterialPath({required String category, required String name}) {
  final trimmed = name.trim();
  return '$category/${trimmed.isEmpty ? '未命名材料' : trimmed}';
}
```

于是 `buildMaterialPath(category:'书籍', name:'书籍/《Character》')` = **`书籍/书籍/《Character》`**。第二次移动会在脏路径上再叠一层，可以无限加深（`书籍/书籍/书籍/…`）。

### 根因 2：分组键 = 原始路径字符串，所以“并入老分类”不可能发生

`material_group.dart:78-139` `groupMaterials()` 直接以 `materialPath` 字符串为 key：

```dart
for (final v in items) {
  final rawPath = (v.materialPath ?? '').trim();
  final String groupPath;
  final String? pageLabel;
  if (isBook) {
    ...
    final split = splitBookMaterialPath(rawPath);
    groupPath = split.bookPath;          // :98
    ...
  } else {
    groupPath = rawPath.isEmpty ? '未归类' : rawPath;   // :105
  }
  ...
}
```

`书籍/《Character》` ≠ `书籍/书籍/《Character》` → 两个 `MaterialGroup`。而且脏的书籍路径会被 `splitBookMaterialPath`（`:43-56`）解析成 **书路径=`书籍/书籍`、页码=`《Character》`**：词汇本里会冒出一个显示名「书籍」的分组，点开子项叫「《Character》」—— 用户感知就是“多出来一个怪分类”。

### 根因 3（附带 bug，也是“重复项”的放大器）：过滤条件把显示名和路径比

调用处 `my_materials_section.dart:792`：

```dart
onPressed: () => _moveToExisting(label: g.label, items: items),
```

`g.label` 是**显示名**（`MaterialGroup.label`，来自 `materialDisplayName(path, category)`，即去掉 `书籍/` 前缀后的 `《Character》`，见 `material_group.dart:34-37,134-138`）。`_moveToExisting` 里用 `p != label` 过滤“当前分组自己”，`p` 是完整路径 → **永远不相等** → 当前分组自己也会出现在“移动到哪”的列表里。用户把自己移给自己 == 再生成一条重复前缀路径，也是截图里两条同源条目的来源之一。

### 已确认干净的其它链路（不是这个 bug 的来源）

| 链路 | 位置 | 结论 |
|---|---|---|
| 识图/保存时新建材料 | `sub_category_input.dart:147-166`：`buildMaterialPath(category:..., name: 用户输入短名)`，非书籍再拼 `/$extra` | 正确（name 是短名） |
| 「归入材料/改出处」 | `my_materials_section.dart:523-532`，`name` 来自对话框输入框 | 正确 |
| 阅读器/文章收词 | `word_action_sheet.dart:66-70` 拼 `'$category/$name'`，但 `name` = `WordSaveTarget.materialName`，各调用方传的都是短标题（`article_reader.dart:27-30`、`material_reader_screen.dart:1183-1186,1381-1384`、`material_recommendation_detail_screen.dart:69-72`） | 正确 |
| 重命名书籍文件夹 | `my_materials_section.dart:216-260`（`newPath = '$category/$newName'`，newName 是对话框里的短名）+ `database.dart:1224-1252` 的 `substr` 子路径重写（已验算：`书籍/旧` → `书籍/新` 时 `substr` 下标正确保留斜杠） | 正确 |
| 词汇本批量移动 | `vocab_list.dart:109-155` → `showSubCategoryInput` | 正确 |
| 导入材料分组 | `materials.group_name`（`database.dart:3147-3176`、`imported_materials_section.dart:122-156`）是**单层自定义组名**，与 `vocabulary.material_path` 是两套数据，不做路径拼接 | 无二次拼接风险 |
| 全局搜索 `parentId / path / groupName` 相似拼接 | `grep` 全库只有 `material_group.dart:35/74`、`my_materials_section.dart:251`、`word_action_sheet.dart:69`、`sub_category_input.dart:114/226`、`material_group.dart:34-37`（显示名剥离） | 只有移动链路这一处把“路径”当“名字” |

## 脏数据范围与自查

数据是 `vocabulary.material_path`（`database.dart:97-121` 建表；分组不落表，纯字符串派生）。凡**第二段 == 第一段**即脏：

```sql
-- 1) 脏路径清单(重复分类前缀)
SELECT category, material_path, COUNT(*) AS n
FROM vocabulary
WHERE material_path LIKE category || '/' || category || '/%'
GROUP BY category, material_path
ORDER BY category, n DESC;

-- 2) 连 source_book 一起被写脏的(移动链路 :429)
SELECT id, word, category, material_path, source_book
FROM vocabulary
WHERE source_book LIKE category || '/%';

-- 3) 受影响的词条总数 / 影响到的分类
SELECT category, COUNT(*) FROM vocabulary
WHERE material_path LIKE category || '/' || category || '/%'
GROUP BY category;
```

App 内可见症状（不用 SQL 也能判断）：词汇本「书籍」分类里如果出现一个**名为「书籍」的分组**、点开是「《Character》」这种子项，就是脏数据（`splitBookMaterialPath` 把 `书籍/书籍/《Character》` 解成 书=`书籍/书籍`、页=`《Character》`）。另外移动弹层里同一个书名出现两行也是判断依据。

数据库位置：`AppConstants.dbName = 'readflow.db'`（`constants.dart:117`），Android 上在 `/data/data/com.readflow.readflow/databases/`（`database.dart:56-58` `getDatabasesPath()`），需 adb/root 或先加导出入口；**建议直接在 App 内做一次性迁移**（见下），不必让用户导库。

## 修法

### 推荐（4 步，幂等、可测试）

**Step 1｜新增纯函数 `normalizeMaterialPath`（`lib/utils/material_group.dart`）**

```dart
/// 规范化"分类/材料"路径(纯函数):
/// - 去掉空段/首尾空白
/// - 折掉重复的分类前缀:`书籍/书籍/《X》` → `书籍/《X》`、`书籍/书籍/书籍/《X》` → `书籍/《X》`
/// - 强制单一分类前缀;材料名留在后续层级(教材/新概念英语/第2册 不动)
/// - 材料名为空 → `分类/未命名材料`(与 buildMaterialPath 一致)
String normalizeMaterialPath(String category, String raw) {
  final parts = raw.split('/').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (!parts.contains(category)) {
    // 跨分类/脏数据没带分类:整条当材料名,首段补分类
    return buildMaterialPath(category: category, name: parts.join('/'));
  }
  // 去掉开头的分类,再把"材料名里重复出现的分类"折掉:
  // 书籍/书籍/《X》 → parts[0]==parts[1]==category → 丢第一个
  while (parts.length > 1 && parts[0] == category && parts[1] == category) {
    parts.removeAt(0);
  }
  if (parts[0] != category) parts.insert(0, category);
  if (parts.length < 2) return buildMaterialPath(category: category, name: '');
  return '${parts[0]}/${parts.sublist(1).join('/')}';
}
```

**Step 2｜移动链路改用“完整路径”，不再拼名字（`my_materials_section.dart`）**

```dart
// _moveToExisting:选项先归一再去重(展示也用显示名,避免"书籍/"重复出现在标题里)
final choices = <String>{
  for (final p in paths) normalizeMaterialPath(widget.category, p),
}..removeWhere((p) => p == normalizeMaterialPath(widget.category, gPath));
// 推荐参数由 label 改成 groupPath(完整路径),才能正确排除"自己"
```
```dart
// _moveInto:直接写完整路径;source_book 只写"材料名"(去掉分类前缀)
Future<void> _moveInto(String targetPath, List<Vocabulary> items) async {
  final ids = items.map((v) => v.id).whereType<int>().toList();
  if (ids.isEmpty) return;
  final path = normalizeMaterialPath(widget.category, targetPath);
  final name = materialDisplayName(path, widget.category); // 书籍/《X》→《X》
  await context.read<VocabProvider>().moveVocabularies(
        ids,
        category: widget.category,
        materialPath: path,
        sourceBook: name,
      );
  ...
}
```
同时把 `_groupActions` 里的 `_moveToExisting(label: g.label, ...)` 改成传 `g.path`，并把 `_moveToExisting` 的过滤条件改成 `p != groupPath`（或 `normalizeMaterialPath(...) != normalizedGroupPath`），修掉“能把自己移给自己”。

**Step 3｜一次性迁移（`dbVersion 18 → 19`）**

- `lib/config/constants.dart:121` `dbVersion = 18` → `19`。
- `database.dart:520-618` `_onUpgrade` 末尾加：
  ```dart
  if (oldV < 19) { await _normalizeMaterialPaths(db); }
  ```
- 新增 `_normalizeMaterialPaths(Database db)`（照着 `_normalizeBookPaths`（`:775-809`）的单事务 + batch 写法）：
  ```dart
  static Future<void> _normalizeMaterialPaths(Database db) async {
    final rows = await db.query('vocabulary',
        columns: ['id', 'category', 'material_path', 'source_book'],
        where: "material_path IS NOT NULL AND material_path != ''");
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        final cat = (r['category'] as String?) ?? '其他';
        final path = (r['material_path'] as String?) ?? '';
        final fixed = normalizeMaterialPath(cat, path);
        final sb = (r['source_book'] as String?) ?? '';
        final fixedSb = materialDisplayName(fixed, cat);
        if (fixed != path || (sb.isNotEmpty && sb.contains('/') && sb != fixedSb)) {
          batch.update('vocabulary',
              {'material_path': fixed, 'source_book': sb.isEmpty ? sb : fixedSb},
              where: 'id = ?', whereArgs: [r['id']]);
        }
      }
      await batch.commit(noResult: true);
    });
  }
  ```
- **同时**在 `_onOpen` 自检里也跑一次（`:623-679`，幂等，防“半迁移库”永久坏在用户手机上——本仓库既有约定）。
- ⚠️ **不要复用 v8 的 `_normalizeBookPaths`（`:775-809`）**：它把 `parts[2..]` 当页码，会把 `书籍/书籍/《X》` 归成 `书籍/书籍` + `source_page=《X》`，越修越脏。新迁移必须按“重复分类前缀”单独判断（上面函数已按 category 折前缀）。
- 迁移不删行：`insertVocabularies` 是按 `word.toLowerCase()` 全库去重的（`database.dart:864-947`），正常情况同一词只有一行，UPDATE 不会产生重复行。**残余风险**：若历史上已有同 (word, category, path) 重复行，本迁移不合并（建议先只归一、不删，避免误伤复习状态 `word_review`）；如需彻底去重另起一轮，需按 word 合并 `occurrences_json` 并保留 id 最小行。

**Step 4｜给用户一个可感知的提示（可选）**
迁移后在设置/诊断里加一行“已自动合并 N 个重复材料分组”，避免用户以为数据被悄悄改了；也可在首次打开词汇本时弹一次一次性 SnackBar。

### 备选
- 备选 A（最小改动、不迁移）：只改 `_moveInto` 用完整路径 + 生成侧 `normalizeMaterialPath`，**旧脏数据留在库里**，用户会在移动弹层继续看到旧重复项，需要手动“解散分组→重新归入”——用户体验差，不推荐作为最终方案，可作热修第一版。
- 备选 B（只修 UI）：移动弹层展示时规范化、写库时用**已选路径规范化后的值**，不做迁移；脏数据仍然存在，只是不再新增。
- 备选 C：给 `material_path` 建独立 `material_groups` 表（id/parent_id/path），词汇只存 group_id —— 架构上最干净，但等于重做分组模型（读取/导出/备份/识别保存全链路），本 bug 不值得，留作以后大重构。

## 涉及文件与风险
- 必改：`lib/utils/material_group.dart`（+normalize 纯函数）、`lib/screens/input/widgets/my_materials_section.dart`（移动链路）、`lib/services/database.dart`（迁移 + 自检）、`lib/config/constants.dart`（dbVersion 19）。
- 测试：`test/material_group_test.dart`（已有 buildMaterialPath/groupMaterials 用例，追加 normalize 用例）、新增 `test/db_migration_v19_test.dart`（仿 `test/db_migration_v11_test.dart`）。
- 风险：中。① 迁移会改写用户已有路径字符串（幂等、单事务、可回滚；不改行数/掌握度/复习状态）；② 若用户**故意**建了同名两级路径（几乎不可能，因为生成侧从不允许），会被合并；③ `normalizeMaterialPath` 必须**不影响**合法的多级路径 `教材/新概念英语/第2册`（第 2 段 ≠ category，不折）；④ 书籍类 `source_book` 修复后，词汇本/导出/预填的显示会变回短书名。

## 回归测试建议
1. `normalizeMaterialPath` 纯函数 8 条：`书籍/书籍/《X》→书籍/《X》`、`书籍/书籍/书籍/《X》` 三折、`书籍/《X》` 幂等、`教材/新概念英语/第2册` 不动、`教材/教材/新概念英语/第2册`、空路径、无分类前缀的脏值、材料名自带斜杠（保持原语义）。
2. `groupMaterials`：同一批词混有 `书籍/《X》` 与 `书籍/书籍/《X》` 时，归一后只应产生**一个** `MaterialGroup`（可作为迁移后断言）。
3. DB 迁移测试：`database.dart` 插入脏行（含 `source_book=完整路径`、以及 `word_review` 关联行）→ 触发 `_onUpgrade`/`_onOpen` → 断言 `material_path`、`source_book` 已归一、词条数不变、`word_review` 行数不变（用 `DatabaseService.resetForTest()`，参考 `test/db_migration_v11_test.dart` 套路）。
4. 手动：新建一个干净分类 → 移动 1 个词到已有材料 → 再打开移动弹层：**不应出现重复前缀项**；移动到目标后目标分组词数 +N。

---

# Bug 3｜识图结果出现后追加图片，概率性闪退

## 现象
> "识图功能的识别结果里，在出现结果后追加图片会有概率闪退"。

## 入口与状态更新路径

1. 按钮：结果态图片行右侧「追加图片」（`process_chat.dart:1874-1921`，仅 `_phase == results` 显示）。
2. `_addMoreImages()`（`process_chat.dart:1648-1716`）：
   - 张数守卫：总上限 10、单次 4（`:1657-1667`）；
   - **`ImagePicker().pickMultiImage(imageQuality: 92, maxWidth: 2600, limit: limit)`**（`:1672-1676`）；
   - `setState`：`_streamStartIndex = _images.length`、`_images.addAll(newFiles)`、`_phase = connecting`、`_ensureImageKeys()`（`:1687-1698`）；
   - `_startStreaming()`（`:1700`）→ `extractVocabularyStream(_images.sublist(_streamStartIndex))`。
3. 预处理/发请求：`doubao_api.dart:461-498` `extractVocabularyStream` → `Future.wait(imageFiles.map((f) => _imageToDataUri(f)), eagerError: true)`（`:474-477`）→ `_imageToDataUri`（`:141-150`）→ **`VisionImagePrep.toDataUri(rawBytes)` 是同步纯 Dart，在 UI isolate 上跑**；`lib/services/vision_image.dart:78-130`。
4. 结果回写：`_onStreamDone`（`:720-950`）追加模式 `_results = [..._results, ...results]`（`:881-884`）。
5. **结果出现后自动跑的第二遍「高清分块复查」**：`_onStreamDone` 末尾 `unawaited(_startMissedPass())`（`:907-909`）；`_startMissedPass()`（`:652-718`）对 `_images` 每张图 `readAsBytes()` + `VisionImagePrep.tiles(bytes)`（`vision_image.dart:140-176`，内部同样整图解码、裁剪、再 JPEG 编码）。

## 根因假设（按概率排序）

### H1（最高置信，~60-70%）：追加入口的图片尺寸/内存峰值远大于首页入口，主线程同步解码 + 第二遍复查并发 → OOM / ANR 被系统杀（native 闪退，Dart 层抓不到日志）

**证据链（“同一功能两条入口参数不一致”——与 lead 给的历史线索完全吻合）：**

| 入口 | 代码 | 参数 |
|---|---|---|
| 首页拍照 | `input_home.dart:653-657` | `pickImage(imageQuality: 50, maxWidth: 1024)` |
| 首页相册 | `input_home.dart:678-682` | `pickMultiImage(imageQuality: 50, maxWidth: 1024, limit: ...)` |
| **结果页追加** | `process_chat.dart:1672-1676` | **`pickMultiImage(imageQuality: 92, maxWidth: 2600, limit: limit)`** |

像素量差 ≈ (2600/1024)² ≈ **6.4 倍**，JPEG 质量 92 vs 50 再放大请求体。v2.8 修复时把“与识图管线最长边一致（2600）”当成目标，却忘了首页那条一直只有 1024 —— 于是**首轮识别（1024 小图，正常）不会崩，追加（2600 大图）才有概率崩**，和用户描述的场景吻合。

**再叠加 v2.13 的新增开销（git `ae9a412` 新增，`vision_image.dart:51-71`）**：`prepare()` 里为自动转正调用 `detectRotation(raw)`，它**自己又 `img.decodeImage(raw)` 整图解码一次**（`vision_image.dart:53`），而 `prepare()` 自己已经解过（`:84`）→ 同一张图每次预处理 **整图解码 2 次**；`tiles()`（`:149,152`）同样再解一次，即第二遍复查每张图又解 1~2 次。全部是 `package:image` 的同步纯 Dart 代码，跑在 **UI isolate**。

粗估：2600×1950 RGBA ≈ 20MB/次解码；append 最多 4 张走 `Future.wait`（虽然 `_imageToDataUri` 内部是串行微任务，但 4 张的 base64/原图字节同时被持有、GC 未必及时回收），峰值轻松 >150MB；再叠加结果页已有的 10 张 `Image.file` 缩略图缓存（`cacheWidth` 见 `:982-987`）、结果列表 widget、`_contentText`，以及**时间窗高度重叠的第二遍复查**（用户“看到结果→马上点追加”几乎必然撞上 `_startMissedPass` 正在跑的十几秒）→ 中低端机 OOM 被杀 / 主线程长时间阻塞被 ANR 杀，用户看到的就是“卡一下闪退”。

**为什么 CrashLogger 没有记录（预期内）：** `lib/utils/crash_logger.dart:46-67` 只接管 `FlutterError.onError` 与 `PlatformDispatcher.instance.onError`（Dart 异常）；**native OOM/ANR 进程被杀不经过 Dart**，所以 `crash_log.txt` 里会是空的。这也解释了“反复修了还有”。

**验证方法：**
1. `adb logcat -b crash -b main | grep -iE "lowmemorykiller|OutOfMemory|FATAL EXCEPTION|ANR|kill"`；若看到 `lmkd`/`OutOfMemoryError`/进程被 kill 且无 Dart 栈 → 确认 H1。
2. Android 11+：`adb shell dumpsys activity exit-info com.readflow.readflow`，看 `REASON_LOW_MEMORY` / `REASON_ANR`。
3. 对照实验（无需改代码或只改 1 行）：
   a) 等顶部提示「高清复查已补 N 条」消失后再点追加 → 崩溃率应明显下降；
   b) 追加时只选 1 张 vs 选 4 张 → 随张数上升则确认内存问题；
   c) 临时把 `maxWidth` 改 1024 复测 → 应显著缓解；
   d) Android Studio Memory Profiler 观察 append 瞬间 Java/Dart 堆峰值。
4. 排除法：诊断信息页（我的 → 诊断信息）若能看到 Dart 栈，则不是 OOM，转 H2。

### H2（~20%）：追加与第二遍复查的状态竞态 / 异步异常（通常不会杀进程，但可能表现为卡死/红屏；**未证实**会闪退）
- `_addMoreImages` 没有取消/等待 `_startMissedPass`；两者都会 `setState` 改 `_results`（`:697` vs `:883`），`_selected` 是**索引集合**，`_results` 追加后索引语义可能错位；`_saveAndReturn`（`:1156-1163`）在 await 后按索引取 `_results[i]`，理论上有 RangeError 风险（会被 CrashLogger 记录）。
- `_startMissedPass` 在页面 pop 后仍有 `readAsBytes`/网络 await，靠 `mounted` 兜底（`:670,707`），未发现必然崩溃点。
- 验证：debug 包复现看红屏/日志；诊断信息页是否有 `RangeError/GlobalKey` 记录；把 `_missedPassRunning` 强制置 true（跳过第二遍）复测。
- 修法：追加时给第二遍复查发取消信号（`_missedPassCancelRequested`，在 `for (final imgIdx in targets)` 与每个 await 后检查），或 append 按钮在 `_missedPassRunning` 时禁用并提示“正在高清复查…”。

### H3（~10%）：插件/系统层（**未证实**）
`image_picker` 的 `limit` / EXIF / 大图在个别 ROM 上的 native 崩溃（tombstone）。验证：logcat `FATAL EXCEPTION` 看栈是否落在 `image_picker`/`libimagepipeline`；换单张、`requestFullMetadata: false` 对比。

### 已排除（v2.8 修过的旧因，源码已确认不再成立）
- **GlobalKey 全量重建**：`_ensureImageKeys()`（`:171-184`）已改为只补不重建，源码里没有 `_imageGroupKeys.clear()`；注释也写明原因。这不是本轮根因。
- **`_images[0]` 越界**：`_vocabFromMap` 已有空列表兜底（`:606-612`）。
- **无数量上限**：已有 10/4 上限（`:1646-1669`）。

## 修法

### 推荐（分两级，先止损再根治）

**P0 止损（1 文件，`process_chat.dart`，可当天发版）**
1. 追加尺寸与首页统一：`pickMultiImage(imageQuality: 85, maxWidth: 1600)`（或直接 1024/70，与首页完全一致）—— 最可能单点消除 OOM。
2. 追加前互斥：`if (_missedPassRunning) { 提示"正在高清复查，完成后再追加"; return; }`；或显式等待第二遍结束（`await _missedPassFuture`，把 `unawaited(_startMissedPass())` 改成保存 Future）。
3. 单次追加上限从 4 降到 2；`_addMoreImages` 加 in-flight 守卫（防连点二次 picker）。

**P1 根治（2-3 文件）**
4. 把图片预处理挪到后台 isolate：`VisionImagePrep.prepare/toDataUri/tiles` 都是纯函数，签名是 `Uint8List → Uint8List/String`，可直接：
   ```dart
   // doubao_api.dart _imageToDataUri
   final raw = await _readImageBytes(imageFile);
   final uri = await compute(_prepDataUriIsolate, raw); // 顶层/静态函数,纯 Dart 可跨 isolate
   ```
   并把 `Future.wait` 改为**串行**（`for (...) uris.add(await ...)`），让每张图的解码内存及时释放；`tiles()` 同理（或在首次 prepare 时顺手生成并缓存 tiles，避免第二遍重复解码）。
5. 第二遍复查改为“可取消 + 低优先级”：append 开始时取消；`tiles()` 只处理用户此刻关心的 1~2 张；或在 append 完成后再跑。
6. 释放策略：`_addMoreImages` 前 `imageCache.clear()`（缩略图 10 张的解码缓存对追加无意义，但清了会重新解码；收益需实测，列为可选）。

### 备选
- 备选 A（最小改动）：只做 P0 的 1+3，不动 isolate —— 改动 1 文件，风险最低，但只是把概率压低，极端机型/超大图仍可能崩。
- 备选 B：改用 `image_picker` 的 `imageQuality` 压低 + 自己 `compute` 缩放（不经 `VisionImagePrep` 的两次解码），性能最好但改动最大。
- 备选 C：追加前先做一次“内存可用性检查”（`ProcessInfo.currentRss`），不足则提示用户先保存退出再开新一轮 —— 治标，不推荐作为主方案。

## 涉及文件与风险
- 应急：`lib/screens/input/process_chat.dart`（picker 参数、互斥、上限、in-flight 守卫）。
- 根治：`lib/services/doubao_api.dart`（isolate 化 + 串行）、`lib/services/vision_image.dart`（如把 prepare+tiles 合成一次解码；新增 isolate 入口函数）、`process_chat.dart`（第二遍复查取消）。
- 风险：中。isolate 会多一次 `Uint8List` 拷贝（2~4MB/张，可接受），低端机上单张预处理可能慢 200~500ms 但 UI 不卡；`compute` 里 `debugPrint` 正常；注意 Web 端 `compute` 语义/测试环境需兼容（本项目主要 Android/iOS）。`image` 包纯 Dart，可在 isolate 用。

## 崩溃日志/让用户配合上传
- 机制：`lib/main.dart:19-21` 启动时 `await CrashLogger.install()`；`lib/utils/crash_logger.dart:46-67` 挂钩两个错误通道，`:69-102` 脱敏+截断后写盘，`:91-102` 超过 256KB 只留尾部。
- 落盘位置：`getApplicationDocumentsDirectory()/crash_log.txt`（`crash_logger.dart:49-54`），Android 为 `/data/user/0/com.readflow.readflow/app_flutter/crash_log.txt`（包名见 `android/app/build.gradle` `applicationId = "com.readflow.readflow"`）。
- 用户可取的方式：App 内「我的 → 诊断信息」弹层（`profile_home.dart:484-569`，`SelectableText` 可长按复制，末尾「── 崩溃日志 ──」段），让用户长按复制整页发来即可；也可以截图。诊断页同时包含 API 配置摘要（key 打码）与内容源状态。
- **局限（关键）**：native OOM/ANR 不会进这个文件。建议后续加：① 启动时读 Android `ApplicationExitInfo`（API 30+）把上次退出原因写进诊断页；② 在 `_addMoreImages`/`_startMissedPass` 前后记录 `ProcessInfo.currentRss` 峰值（debug 版写日志），让下一次复现能拿到内存曲线。这两条可以作为 P1 的一部分，也可先只给开发者用。

## 验证方式
1. 真机：全新页面 → 首轮识别出结果 → **立刻**点「追加图片」选 4 张大图（相册里 4000px 原图），重复 10 次；改前 vs 改后对比崩溃率。
2. `adb logcat` 抓 `lowmemorykiller/OutOfMemory/FATAL`；`dumpsys activity exit-info` 看退出原因。
3. 单测：`VisionImagePrep.prepare` 在 isolate 化后输入输出 byte 完全一致（纯函数，现有 `test/vision_*` 若有则复用；没有就加 3 条：正常图、超大图、非图片字节回退）；`_missedPassCancelRequested` 的纯逻辑可单测。
4. 回归：首轮识别（首页 1024 入口）不能被改坏——必须测“首页相册多图识别 → 结果正常”和“追加 1 张 → 结果追加正确、p1/p2 分组正确”。

## 待用户确认
- 机型/Android/iOS 版本、是否 release 包（`flutter build apk --release`）—— 决定能不能抓 logcat；
- 是否愿意配合：崩溃后立刻打开 App → 我的 → 诊断信息 → 长按复制发来（哪怕日志为空也是结论：“不是 Dart 异常”）；
- 应急体验代价是否接受：追加时若第二遍复查在跑需要等几秒、单次最多 2 张。

---

# Bug 4｜识图结果里的词汇卡片增加音标

## 需求
> "识图功能里的词汇卡片需要增加音标（在'词性'这个 UI 的旁边）"。

## 结论先行
**音标全链路早已打通，不需要 DB 迁移、不需要改提示词/解析层。唯一缺口是识图结果页「详细模式」卡片的 UI 没渲染音标。**

## 链路核对表（逐环 file:line）

| 环节 | 结论 | 证据 |
|---|---|---|
| ① 提示词要求模型返回音标 | ✅ 已有 | 识图主 prompt：`doubao_api.dart:247`（`phonetic_uk`/`phonetic_us` 字段格式）+ `:290`（"单词给词性，并同时给 phonetic_uk 与 phonetic_us"）；校准重识别 prompt：`:219`；AI 补全 `completeWordInfo` prompt：`:672-674`；`parseWordInfo` 解析：`:709-740` |
| ② 解析层保留 | ✅ 已有 | 多图 `items_by_image` 分支 `doubao_api.dart:1308-1311`；单图 `items` 分支 `:1337-1340`；本地校验层 `vision_guard.dart:259-270` 用 `{...item, ...}` 透传，不会丢字段 |
| ③ 映射进模型 | ✅ 已有 | `process_chat.dart:622-628`：`phonetic: r['phonetic']`、`phoneticUk: r['phonetic_uk'] ?? r['phonetic']`、`phoneticUs: ...` |
| ④ Vocabulary 字段/显示规则 | ✅ 已有 | `models/vocabulary.dart:19-23`（三个字段）、`:102-127` toMap/fromMap、`:222-245` `phoneticsUk/Us/hasPhonetic/displayPhonetic`（两边都有时拼 `英 /a/ · 美 /b/`，只有一边时不加标签） |
| ⑤ SQLite 列 | ✅ 已有（dbVersion 11 就加了，当前 18） | 建表 `database.dart:110-113`；迁移 `:540`、`:573-574`；启动自检 `:630-632`；`constants.dart:121 dbVersion = 18` → **无需 +1** |
| ⑥ 已有 5 处 UI | ✅ 已有 | 总览卡片 `word_list_tile.dart:189-202`；详情弹层 `word_detail_sheet.dart:77-88`；词汇本卡片 `vocab_card.dart:106-112`；阅读器查词面板 `word_action_sheet.dart:299-301`；编辑/手动添加弹窗 `process_chat.dart:2944,2988,3203-3400` |
| ⑦ **识图结果「详细模式」卡片** | ❌ **缺** | `process_chat.dart:2316-2497` `_buildDetailTile`：第二行只有 `word`/词性 chip（`:2428-2443`），没有音标 |

```dart
// process_chat.dart:2428-2443 —— 当前详细卡片第二行(只有类型 + 词性)
// 第二行：类型标签 + 词性
if (item.wordType != 'word' ||
    (item.partOfSpeech != null &&
        item.partOfSpeech!.isNotEmpty)) ...[
  const SizedBox(height: 4),
  Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      _typeChip(item.wordType, barColor),
      if (item.partOfSpeech != null &&
          item.partOfSpeech!.isNotEmpty)
        _typeChip(item.partOfSpeech!, theme.colorScheme.onSurfaceVariant),
    ],
  ),
],
```
（默认 `_displayMode = _DisplayMode.detailed`，`process_chat.dart:89` → 识图结果默认就是这张卡；总览模式的 `WordListTile` 反而**已经显示音标**。）

补充确认：识图结果不是“另一套临时结构”——`_results` 就是 `List<Vocabulary>`（`process_chat.dart:157-159` 附近字段、`:600-650` `_vocabFromMap`），音标字段一路带着，只是没画出来。

## 修法

### 推荐（1 文件，约 10 行）：在词性 chip 同一行 `Wrap` 里加音标
```dart
// process_chat.dart:2428 起，改条件 + 加一个 chip
final phonetic = item.displayPhonetic; // 已处理"英/美双显"与空值
if (item.wordType != 'word' ||
    (item.partOfSpeech?.isNotEmpty ?? false) ||
    phonetic != null) ...[
  const SizedBox(height: 4),
  Wrap(
    spacing: 6,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _typeChip(item.wordType, barColor),
      if (item.partOfSpeech?.isNotEmpty ?? false)
        _typeChip(item.partOfSpeech!, theme.colorScheme.onSurfaceVariant),
      if (phonetic != null)
        Container(                      // 与 _typeChip 同视觉,但不压缩/不省略斜杠
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withAlpha(18),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(phonetic,
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant)),
        ),
    ],
  ),
],
```
要点：
- 音标**不放进 `_typeChip`** 的原因：`_typeChip` 带 `maxLines:1 + ellipsis`（`:2499-2517`），“英 /ˈʃedjuːl/ · 美 /ˈskedʒuːl/” 会被截断；用同视觉的 `Container` + 不限行、`Wrap` 自动换到下一行。
- 只有一边音标时 `displayPhonetic` 只给那一套、不加“英/美”标签（`vocabulary.dart:231-245` 的既定规则），无需额外判断。
- 中文批注条目（`annotation_only`）通常没有音标，条件里 `phonetic != null` 自然不渲染。

### 备选
- 备选 A：把音标放在**词条标题下方**单独一行小字（与总览/详情页风格 100% 一致，视觉更稳），但不满足用户“在词性旁边”的字面要求。
- 备选 B：词性与音标合并成一个 chip（`n. /ˈx/`），更省空间，但信息密度高、长音标仍可能换行。
- 备选 C（若模型偶尔漏给音标，想“尽量都有”）：保存进词库时对缺音标的词批量调已有 `DoubaoApiService.completeWordInfo`（`:650-703`，手动添加弹窗已在用 `:3203-3400`）补齐；或词条编辑里手填（`:2944,2988`）。**不建议**为此再起一套缓存。

## 「补 DB 列 vs 存 Hive/JSON 缓存」判断

**本 bug 不需要选：DB 列早已存在（v2.0 dbVersion 11 加的），零迁移。** 但如果要从设计上回答“以后加类似字段该放哪”：

- **推荐补 DB 列（与现状一致）**。理由：
  1. 音标是词条的**稳定属性**，不是临时 UI 状态；`Vocabulary` 已是全 App 的一等模型。
  2. 已有大量读取方依赖 DB 字段：词汇本列表、复习队列（`drill_planner.dart:631,652` 用 `displayPhonetic`）、CSV/Anki 导出（`export_service.dart:65-66,98-99`）、完整备份（`backup_service.dart:353-355`）、保存去重时的“仅补空字段”逻辑（`database.dart:914-924` `fillIfEmpty('phonetic_uk'/'phonetic_us')`）。
  3. 放 Hive/JSON 会是**第二事实源**：导出/备份/复习都要额外合并，去重与“不覆盖用户修改”的语义要再实现一遍，极易变成下一个 Bug 2 式的“同一份数据两条链路两种解析”。
  4. 本仓库迁移机制成熟：`_ensureColumn` 幂等 + 启动自检 + 单测（`test/db_migration_v11_test.dart`），成本一次性。
- **只有以下情况才值得 `dbVersion + 1` 加列**：要记录“音标来源（模型/词典/人工校正）”“音标更新时间”或用新字段做筛选/排序。当前需求不需要。
- Hive/JSON 的合理用途：**缓存 AI 补全的临时结果**（例如模型一次返回但用户还没保存的那批词），或作为网络失败时的兜底；不作为词条长期存储。

## 涉及文件与风险
- 只改 `lib/screens/input/process_chat.dart`（`_buildDetailTile`，约 10 行）；测试 1 个文件。
- 风险：极低。纯渲染新增，不动数据链路；注意与 `_typeChip` 的视觉一致性、深色模式颜色（用 `theme.colorScheme.onSurfaceVariant`，已满足对比度要求）。
- 若用户说的卡片是**总览模式**（`WordListTile`）：那里已经显示音标（`word_list_tile.dart:189-202`），说明需求其实是“详细模式”或“音标没被模型返回”，需要用户截图确认（见下）。

## 验证方式
1. Widget 测试（新增 `test/vocab_detail_card_phonetic_test.dart`）：构造 `Vocabulary(word:'lazy', partOfSpeech:'adj.', phoneticUk:'/ˈleɪzi/', phoneticUs:'/ˈleɪzi/')` → pump 详细模式卡片 → 断言音标文本出现且与词性文本在同一 `Wrap` 内；三态（双/单/无）各一条。
2. 现有 `test/phonetic_and_blocklist_test.dart` 已覆盖 model 往返/老数据回填/解析层（`:16-50` 起），不需要重复。
3. 真机：识图 → 结果默认详细模式 → 卡片第二行应看到词性旁音标；总览/详情/词汇本三处不回归。
4. 若某词条无音标：确认模型是否真没返回（看 AI 原文/重识别一次）；若经常没有，再考虑备选 C 的补全策略。

## 待用户确认（歧义）
- 截图确认是「详细模式」（带 `word`/`n.` 小 chip、每张卡带释义/例句，默认）还是「总览模式」？若是总览模式，音标本就在词条下方（v1.5 起），需换描述。
- 音标显示偏好：默认 `displayPhonetic` = “英 /a/ · 美 /b/” 双显；用户是否只要一个主音标？

---

# 附：本轮未证实 / 待补充
1. Bug 1 真机“打开首帧是否已有 `scrollCtrl.hasClients`”未实测（静态无法证明），修法用 3 帧重试兜底。
2. Bug 3 的 OOM 判断基于代码路径 + 参数对比 + Flutter/Dart 解码模型的推断，**没有真机 logcat/内存曲线**；H2/H3 明确标“未证实”，需按上面的验证脚本落地。
3. Bug 2 迁移后“同词重复行”是否存在，取决于用户历史数据；迁移只做路径归一、不删行，建议先只读统计（用开头的 SQL）再决定是否做第二轮合并。
4. 本轮禁止 `flutter analyze/build/run`，所有结论为静态阅读；无源码改动（仅新增本文档）。
