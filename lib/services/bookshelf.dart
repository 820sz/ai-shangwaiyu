/// 书架的数据模型与**纯函数**(v2.10,用户 10/4 第 4/5 条)。
///
/// 分工(为什么这么切):
/// - `services/database.dart` 只管 SQL(它已经写好,本任务不允许改);
/// - 本文件把 `bookshelfItems()` 的**行**变成界面能直接用的 [BookshelfBook],
///   并给出书脊尺寸/配色这类**纯函数** —— 纯函数不碰 BuildContext、不碰数据库,
///   所以能单测(见 `test/bookshelf_test.dart`),书架"每层几本""书脊什么色"
///   这种最容易在改版里悄悄歪掉的规则才有闸门兜着。
/// - 画的部分在 `widgets/bookshelf_view.dart`,本文件只出数据与度量。
library;

import 'dart:ui' show Color;

/// 书架上的**一本书**(书架页/书脊控件只认这个模型)。
///
/// 字段与 `DatabaseService.bookshelfItems()` 的列一一对应,但**不保留原始 Map**:
/// SQL 行是动态类型的(SQLite 的 REAL 列可能返回 int、TEXT 列可能返回 null),
/// 让界面层到处写 `as num?` 才是脏数据的源头 —— 统一在 [fromRow] 里洗一次。
class BookshelfBook {
  /// materials.id(打开阅读器要用它)
  final int materialId;

  /// 展示用标题:**已经是中文优先**(库里 COALESCE(title_cn, title),见数据层注释)
  final String title;

  /// 英文原标题(中文标题底下那行小字)
  final String titleEn;

  /// 材料种类(book/news/paper/podcast/wiki/article)→ 取图标
  final String kind;

  /// 来源 id(bbc_le / gutenberg / arxiv …)→ 取口音/来源名
  final String source;

  /// 阅读进度:**统一成 0~100**
  ///
  /// 为什么要在这一层归一:库里 `material_progress.percent` 有两套口径 ——
  /// 数据层测试写的是 0.5(比例),而用户看到的永远是"读了 50%"。
  /// 归一放在**入口一处**,界面就不必每次猜;见 [_percentOf]。
  final double percent;

  /// 累计阅读分钟
  final int minutes;

  /// 词数(元信息用)
  final int wordCount;

  /// CEFR 难度(A1~C2,可为空串)→ `MaterialLevel.of()`
  final String cefr;

  /// 是否读完(库里有 finished_at,或进度到 100%)
  final bool finished;

  /// 用户备注(加书架时写的,可为空)
  final String note;

  /// 加入书架的时间(脏数据时为 null,界面不显示这行)
  final DateTime? addedAt;

  /// 最近一次阅读/加入的时间(排序用)
  final DateTime? updatedAt;

  /// 摆放顺序(slot:越小越靠左靠上)
  final int slot;

  /// 已拾取生词数(长按弹层的元信息)
  final int pickedWords;

  const BookshelfBook({
    required this.materialId,
    required this.title,
    this.titleEn = '',
    this.kind = 'article',
    this.source = '',
    this.percent = 0,
    this.minutes = 0,
    this.wordCount = 0,
    this.cefr = '',
    this.finished = false,
    this.note = '',
    this.addedAt,
    this.updatedAt,
    this.slot = 0,
    this.pickedWords = 0,
  });

  /// 阅读进度 → 0~1(书脊上的书签带直接用)
  double get progress => spineProgress(percent);

  /// 是否"在读"(翻开过、还没读完)—— 顶部统计的"在读"用这个口径
  bool get reading => !finished && percent > 0;

  /// 是否**一次都没翻开**(放上书架但还没读过)
  bool get untouched => !finished && percent <= 0;

  /// 副标题:英文原名;**与中文标题相同时不重复显示**
  /// (库里 title 已经中文化,英文名单独一行才不啰嗦)
  String get subtitle {
    final en = titleEn.trim();
    if (en.isEmpty) return '';
    return en == title.trim() ? '' : en;
  }

  /// 造一个"只有标题"的书(测试与预览用,避免每个用例都写全字段)。
  /// 进度到 100 就当读完 —— 免得用例里写 `sample(percent: 100)` 却忘了 finished
  /// 这种坑(真实数据由 [fromRow] 按 percent/finished_at 判定,口径一致)。
  factory BookshelfBook.sample({
    required int materialId,
    required String title,
    double percent = 0,
    int minutes = 0,
    String kind = 'article',
    bool finished = false,
  }) =>
      BookshelfBook(
        materialId: materialId,
        title: title,
        kind: kind,
        percent: percent,
        minutes: minutes,
        finished: finished || percent >= 100,
      );

  /// **脏数据必须容错** —— 这个函数是 SQL 行进入界面的唯一闸门。
  ///
  /// 为什么一个字都不能抛:书架是"用户攒了很久的资产",任何一行字段类型不对
  /// (老库缺列、TEXT 里写着 'null'、percent 存成字符串)都不该让整页书架白屏。
  /// 缺字段 → 用默认值;类型不对 → 尽力解析;实在解析不出 → 默认值。
  static BookshelfBook fromRow(Map<String, Object?> row) {
    final percent = _percentOf(row['percent']);
    final finishedAt = _asString(row['finished_at']).trim();
    return BookshelfBook(
      materialId: _asInt(row['material_id']),
      // 中文优先:库里已经 COALESCE 过,这里再兜一道(万一有人直接喂原始 materials 行)
      title: _pickTitle(row),
      titleEn: _asString(row['title_en']),
      kind: _kindOf(row['kind']),
      source: _asString(row['source']),
      percent: percent,
      minutes: _asInt(row['minutes']),
      wordCount: _asInt(row['word_count']),
      cefr: _asString(row['cefr']).toUpperCase(),
      // 读完的两种口径都要认:有完成时间,或进度已经到 100
      finished: finishedAt.isNotEmpty || percent >= 100,
      note: _asString(row['note']),
      addedAt: _asDate(row['added_at']),
      updatedAt: _asDate(row['updated_at']),
      slot: _asInt(row['slot']),
      pickedWords: _asInt(row['picked_words']),
    );
  }

  /// 标题取值顺序:中文译名 → 展示标题(title,库里已中文化)→ 英文原名 → 兜底文案
  static String _pickTitle(Map<String, Object?> row) {
    for (final key in ['title_cn', 'title', 'title_en']) {
      final t = _asString(row[key]).trim();
      if (t.isNotEmpty && t.toLowerCase() != 'null') return t;
    }
    return '未命名材料';
  }

  /// 进度归一:统一成 0~100。
  ///
  /// 库里两套口径都可能出现:比例(0.5)与百分数(50)。
  /// 判据:0~1 之间(含 1)**一律当比例**——因为库里写比例是主要口径
  /// (`upsertMaterialProgress(percent: 0.5)` 是数据层测试的既定用法),
  /// 而"读了 1% 却存成 1.0"这种极端值不值得为它牺牲主要口径的正确性。
  /// 负数/超过 100 一律夹紧,`null`/非数字按 0(**没读过**),绝不抛。
  static double _percentOf(Object? value) {
    final raw = _asDouble(value);
    if (raw.isNaN || raw.isInfinite) return 0;
    if (raw <= 0) return 0;
    final pct = raw <= 1 ? raw * 100 : raw;
    return pct.clamp(0, 100).toDouble();
  }

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static double _asDouble(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0;
    return 0;
  }

  static String _asString(Object? v) => v is String ? v : (v == null ? '' : '$v');

  /// 时间字段容错:解析不出就 null(界面据此隐藏那一行,而不是显示 1970)
  static DateTime? _asDate(Object? v) {
    if (v is DateTime) return v;
    if (v is int) {
      // 秒级/毫秒级时间戳都认(库里有历史数据是 int)
      return DateTime.fromMillisecondsSinceEpoch(v < 100000000000 ? v * 1000 : v);
    }
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
    return null;
  }

  /// 种类归一:只认这几种(与 `MaterialLibrary.kindLabel` 同一套口径),
  /// 认不出的(老数据、脏字符串、甚至一个数字)一律当 article ——
  /// 界面按 article 取图标,不会出现空图标或 "123" 这种鬼东西
  static const Set<String> _knownKinds = {
    'book', 'news', 'paper', 'podcast', 'wiki', 'article',
  };

  static String _kindOf(Object? v) {
    final k = _asString(v).trim().toLowerCase();
    return _knownKinds.contains(k) ? k : 'article';
  }
}

/// 书架顶部那三四个数字(用户要求"别做成一堆小字")
class BookshelfStats {
  /// 共几本
  final int total;

  /// 读完几本
  final int finished;

  /// 在读几本(翻开过、没读完)
  final int reading;

  /// 还没翻开过几本
  final int untouched;

  /// 合计阅读分钟
  final int minutes;

  const BookshelfStats({
    this.total = 0,
    this.finished = 0,
    this.reading = 0,
    this.untouched = 0,
    this.minutes = 0,
    this._percentSum = 0,
  });

  static const BookshelfStats empty = BookshelfStats();

  /// 在读那些书的进度之和(只用来算平均进度;读完的按 100 计)
  final double _percentSum;

  /// 整架平均进度(0~100;空架子 = 0)
  double get avgPercent =>
      total == 0 ? 0 : (finished * 100 + _percentSum) / total;

  /// 合计读了多久的人话(用户看的是"读了多久",不是"多少分钟"的裸数字)
  ///
  /// 规则:不足 1 小时 → "N 分钟";否则 "H 小时 M 分"(M=0 时省略)。
  String get minutesLabel {
    if (minutes <= 0) return '0 分钟';
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h 小时' : '$h 小时 $m 分';
  }

  /// 由书列表算统计(**纯函数**,界面与测试共用同一份口径)
  static BookshelfStats statsOf(List<BookshelfBook> books) {
    var finished = 0;
    var reading = 0;
    var untouched = 0;
    var minutes = 0;
    var percentSum = 0.0;
    for (final b in books) {
      minutes += b.minutes;
      if (b.finished) {
        finished++;
      } else if (b.percent > 0) {
        reading++;
        percentSum += b.percent;
      } else {
        untouched++;
      }
    }
    return BookshelfStats(
      total: books.length,
      finished: finished,
      reading: reading,
      untouched: untouched,
      minutes: minutes,
      percentSum: percentSum,
    );
  }
}

/// 书脊(立着的那本书)的尺寸 —— 界面与测试共用,避免"改了一处忘了另一处"
class SpineMetrics {
  SpineMetrics._();

  /// 书脊宽度。真机上按书位宽度算([spineWidthForSlot]),这两个值是**夹紧边界**:
  /// - 下限 30:比这窄就认不出是"一本书"(变成一根色条);
  /// - 上限 48:再宽就"一本书顶半层架子"了(上限比常见书脊略宽一点,
  ///   是为了让**手机(360)上一排 6 本刚好占满整层**,不会缩在左边留一大块空)。
  static const double minWidth = 30;
  static const double maxWidth = 48;

  /// 书脊高度(用户要求 110~130)
  static const double height = 122;

  /// 书位宽度:一层要放 n 本时,每本占的横向空间不能小于它
  /// (52 ≈ 360 的手机上"6 本一排"正好占满;再窄就该新起一层了)
  static const double slotWidth = 52;

  /// 一个书位里,书脊到书位边缘的留白(合起来就是书与书的间隙,约 4~8)
  static const double slotInset = 4;

  /// 搁板本身(那块木头)的厚度
  static const double plankThickness = 10;

  /// 搁板下方阴影的高度(让书"站"在板子上,而不是浮着)
  static const double plankShadow = 8;

  /// 一层书架的总高(书 + 搁板 + 阴影)
  static const double shelfHeight = height + plankThickness + plankShadow;

  /// 层与层之间留多少(不贴着,像真书架的格子)
  static const double rowSpacing = 18;

  /// 书架页面左右边距(与 Insets.page 一致)+ 书架木框内边距
  static const double framePadding = 10;
}

/// 一层搁板最多放几本 —— **按屏宽算**(用户:"一层放 5~7 本,超过就新起一层")。
///
/// 为什么要有上下限 3~7:
/// - 下限 3:再窄的屏也不该出现"一层一两本"这种稀疏到不像书架的排布;
/// - 上限 7:**平板/横屏上一排十几本,书脊会变成一根根细条**(失去书的比例),
///   而且用户要的是"留白等着被放满",一排塞满反而没有"还能放"的余味。
/// 取整用 floor:剩下的宽度宁可留白。
int booksPerShelf(double width) {
  if (width.isNaN || width.isInfinite || width <= 0) return 5;
  final usable = width - SpineMetrics.framePadding * 2;
  final n = (usable / SpineMetrics.slotWidth).floor();
  return n.clamp(3, 7);
}

/// 给定一个书位的宽度,算出书脊该多宽(夹在 [SpineMetrics.minWidth]~[SpineMetrics.maxWidth])。
///
/// **为什么不做成写死的 34**:一层几本是按屏宽算的,书脊宽度也必须跟着屏宽走 ——
/// 否则小屏上一排书缩在左边、右边空一大块(用户要的"一排书"就散了),
/// 大屏上又会因为 34 太窄而像一排书签。书位宽 → 书脊宽,视觉上才是"书摆满这层架子"。
double spineWidthForSlot(double slotWidth) {
  if (slotWidth.isNaN || slotWidth.isInfinite || slotWidth <= 0) {
    return SpineMetrics.minWidth;
  }
  return (slotWidth - SpineMetrics.slotInset * 2)
      .clamp(SpineMetrics.minWidth, SpineMetrics.maxWidth)
      .toDouble();
}

/// 0~100 的进度 → 0~1(夹紧;NaN/null 由调用方 [BookshelfBook.fromRow] 处理过)
double spineProgress(double percent) {
  if (percent.isNaN) return 0;
  final p = percent / 100;
  if (p <= 0) return 0;
  if (p >= 1) return 1;
  return p;
}

/// 书架固定的**纸感低饱和配色盘**(书脊专用)。
///
/// 为什么不用 `MaterialCover.paletteFor`:那套是给**封面**用的(斜向渐变、
/// 明度跨度大,贴在书脊上会一排都"发亮");书脊要的是"一排纸书立在暗色架上"
/// ——明度压得更低、饱和度更小,而且**与深色主题的架子对比度更好**。
/// 也正因为不用网络封面图:书脊是 34×122 的窄条,任何图贴上去都只剩一团噪点,
/// 真正的封面留给"长按 → 查看封面"那张大图。
const List<List<Color>> spinePaletteColors = [
  [Color(0xFF6E5844), Color(0xFF8A7057)], // 牛皮纸
  [Color(0xFF4C5F58), Color(0xFF68807A)], // 苔绿
  [Color(0xFF5A566F), Color(0xFF7A7593)], // 雾紫
  [Color(0xFF6B4E4E), Color(0xFF8A6868)], // 陶土红
  [Color(0xFF44586E), Color(0xFF617A94)], // 藏青
  [Color(0xFF6B6046), Color(0xFF8C7F5F)], // 亚麻黄
  [Color(0xFF4E5560), Color(0xFF6C7480)], // 石墨灰
  [Color(0xFF5E4A5A), Color(0xFF80657C)], // 陈酒紫
];

/// 按标题取书脊配色(纯函数,**同一本书永远同一色**)。
///
/// 为什么不用 `String.hashCode`:Dart 的字符串 hashCode 在不同进程/不同 run 里
/// 不保证一致(书架每次冷启动都可能换色,用户会觉得"我的书被人动过")。
/// 这里用与 `MaterialCover.paletteFor` 同一套**可复现的乘法哈希**,
/// 并跳过空白字符,避免"标题只差一个空格就换色"。
List<Color> spinePalette(String title) {
  final seed = title.trim();
  if (seed.isEmpty) return spinePaletteColors.first;
  var h = 0;
  for (final r in seed.runes) {
    h = (h * 31 + r) % 1000003; // 大质数取模:够散且可复现
  }
  return spinePaletteColors[h % spinePaletteColors.length];
}

/// 压在某个底色上的**可读文字色**(书脊、封面卡上的标题都用它)。
///
/// 为什么需要:配色盘里有几档是偏亮的亚麻/苔绿,写死白色会糊在底上
/// (对比度不足 3:1);按底色亮度二选一,两种底都读得清 —— 而且这是纯计算,
/// 不必为每一本书提前挑字色。
Color readableOn(Color background) => background.computeLuminance() > 0.52
    ? const Color(0xFF231F1A)
    : const Color(0xFFF3EEE4);

/// 书脊上那几个字(纯函数)。
///
/// 规则(两条都来自"别把词切断"):
/// - **中文优先**:标题里 CJK 字符 ≥ 2 个 → 取最前面 4 个 CJK 字
///   (中文按字排版,取前 4 字不算"切词",反倒是书脊上唯一读得懂的形式);
/// - 否则取**第一个有意义的英文单词**(跳过 the/a/of 这类虚词),
///   单词整体保留、超长截到 8 字符 —— 绝不从单词中间断开。
///
/// [vertical] 只影响**是否按"书脊朝向"取字**这一处语义:横排展示(长按弹层、
/// 未来书架"平放"视图)时可以多给一个字,竖排书脊受高度限制取少一点。
String spineLabel(String title, {required bool vertical}) {
  // 书名号/引号去掉:书脊上的字越干净越好读(注意用双引号 raw 串,
  // 单引号字符在双引号串里不需要转义,否则 r'...\'...' 会变成非法正则)
  final clean = title
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r"""[《》「」【】"“”'’]"""), '')
      .trim();
  if (clean.isEmpty) return '书';

  final cjk = RegExp(r'[\u4e00-\u9fff]');
  final cjkChars = clean.runes
      .map(String.fromCharCode)
      .where(cjk.hasMatch)
      .toList();
  final maxCjk = vertical ? 4 : 5;
  if (cjkChars.length >= 2) return cjkChars.take(maxCjk).join();

  final words = clean
      .split(RegExp(r'[\s\-_/·]+'))
      .map((w) => w.replaceAll(RegExp(r'''[^\w\u4e00-\u9fff]'''), ''))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '书';
  final word = words.firstWhere(
    (w) => !_stopWords.contains(w.toLowerCase()),
    orElse: () => words.first,
  );
  return word.length <= 8 ? word : word.substring(0, 8);
}

/// 英文虚词:书脊上最该省掉的就是它们("The Great Gatsby" 该显示 Great)
const Set<String> _stopWords = {
  'the', 'a', 'an', 'of', 'on', 'in', 'to', 'and', 'or', 'for', 'with', 'at',
  'by', 'from', 'is', 'are', 'as', 'how', 'why', 'what',
};
