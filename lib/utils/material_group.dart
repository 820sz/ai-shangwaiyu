import '../models/vocabulary.dart';

/// 材料分组(v1.6.0):「我的学习材料」按层级展示。
///
/// 规则:
/// - 书籍:一本 = 一个文件夹(一级),页码/章节 = 子分类(二级)。
///   路径只到书(`书籍/《X》`),页码存 source_page;旧数据
///   `书籍/《X》/p16 p17` 由 [splitBookMaterialPath] 兼容解析。
/// - 教材/外刊/碎片文章/其他:沿用整条 material_path 作为一级分组
///   (这些分类的层级本身有意义,如 `教材/新概念英语/第2册`)。
class MaterialGroup {
  /// 一级分组 key(materialPath 或书路径)
  final String path;

  /// 一级显示名(去掉主分类前缀)
  final String label;

  /// 二级分组(页/章/单元) → 词条;空 Map = 无二级
  final Map<String, List<Vocabulary>> subgroups;

  const MaterialGroup({
    required this.path,
    required this.label,
    required this.subgroups,
  });

  int get totalCount =>
      subgroups.isEmpty
          ? 0
          : subgroups.values.fold(0, (sum, list) => sum + list.length);
}

/// 去掉主分类前缀的显示名:`书籍/《X》/p3` → `《X》/p3`
String materialDisplayName(String path, String category) {
  final prefix = '$category/';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

/// 拆分书籍材料路径(纯函数,可单测):
/// - `书籍/《X》/p16 p17` → (书路径 `书籍/《X》`, 页码 `p16 p17`)
/// - `书籍/《X》`         → (书路径 `书籍/《X》`, 页码 null)
/// - 非书籍前缀/空路径    → 原样返回,页码 null
({String bookPath, String? page}) splitBookMaterialPath(String path) {
  final parts = path
      .split('/')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.length < 2 || parts[0] != '书籍') {
    return (bookPath: path.trim(), page: null);
  }
  final bookPath = '${parts[0]}/${parts[1]}';
  if (parts.length < 3) return (bookPath: bookPath, page: null);
  final page = parts.sublist(2).join('/');
  return (bookPath: bookPath, page: page.isEmpty ? null : page);
}

/// 页码/章节排序 key:取首个数字,让 p2 排在 p10 前面;
/// 无数字的排最后(按字典序)。
int pageSortKey(String label) {
  final m = RegExp(r'\d+').firstMatch(label);
  if (m == null) return 1000000;
  return int.tryParse(m.group(0)!) ?? 1000000;
}

/// 构造"分类 / 材料名"两级路径(纯函数,v2.4)。
///
/// 为什么强制两级:分组逻辑([groupMaterials])按 `material_path` 归类,
/// 只有一级(如 `书籍`)或空路径都会掉进「未归类」—— 用户手动把词归到
/// 「书籍」却看到它还在「未归类」,就是这么来的(A6 用户实测)。
/// 名字为空时落一个明确的分组名,而不是留空或拼出伪路径。
String buildMaterialPath({required String category, required String name}) {
  final trimmed = name.trim();
  return '$category/${trimmed.isEmpty ? '未命名材料' : trimmed}';
}

/// 分组(纯函数,可单测)
List<MaterialGroup> groupMaterials(
  List<Vocabulary> items, {
  required String category,
}) {
  final isBook = category == '书籍';
  final bookOrder = <String>[];
  final bookPages = <String, Map<String, List<Vocabulary>>>{};

  for (final v in items) {
    final rawPath = (v.materialPath ?? '').trim();
    final String groupPath;
    final String? pageLabel;
    if (isBook) {
      if (rawPath.isEmpty) {
        groupPath = '未归类';
        pageLabel = (v.sourcePage ?? '').trim().isEmpty
            ? '未标页码'
            : v.sourcePage!.trim();
      } else {
        final split = splitBookMaterialPath(rawPath);
        groupPath = split.bookPath;
        final page = (v.sourcePage ?? '').trim().isNotEmpty
            ? v.sourcePage!.trim()
            : split.page;
        pageLabel = (page == null || page.isEmpty) ? '未标页码' : page;
      }
    } else {
      groupPath = rawPath.isEmpty ? '未归类' : rawPath;
      pageLabel = null;
    }

    if (!bookPages.containsKey(groupPath)) {
      bookPages[groupPath] = {};
      bookOrder.add(groupPath);
    }
    final pages = bookPages[groupPath]!;
    final subKey = pageLabel ?? '';
    pages.putIfAbsent(subKey, () => []);
    pages[subKey]!.add(v);
  }

  // 排序:未归类最后,其余按显示名字典序
  bookOrder.sort((a, b) {
    if (a == '未归类') return 1;
    if (b == '未归类') return -1;
    return a.compareTo(b);
  });

  return bookOrder.map((path) {
    final pages = bookPages[path]!;
    final sortedKeys = pages.keys.toList()
      ..sort((a, b) {
        final ka = pageSortKey(a), kb = pageSortKey(b);
        if (ka != kb) return ka.compareTo(kb);
        return a.compareTo(b);
      });
    return MaterialGroup(
      path: path,
      label: path == '未归类' ? '未归类' : materialDisplayName(path, category),
      subgroups: {for (final k in sortedKeys) k: pages[k]!},
    );
  }).toList();
}
