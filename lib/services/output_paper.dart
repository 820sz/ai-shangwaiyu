/// 输出板块 · **真题卷面身份**(年份 / 月份 / 套数 / 来源站点)。
///
/// 为什么单独一层:用户 2026-11-06 点名"练习材料没标来源/年份/套数"。
/// 数据库 `exercise_sets` 早就有 `paper_year` / `paper_label` 两列
/// (`lib/services/database.dart` 建表处),但**写入端以前把 paper_label 写成空串**,
/// 而检索结果里的页面标题/站点名/发布时间在出题链路里被直接丢弃。
///
/// 这一层的纪律(与出题层同源):
/// 1. **只从真实来源抽**:检索结果的标题、URL、页面首段、站点名;
///    模型一律不许编造"某年真题"标签;
/// 2. **抽不到就留空**:不猜年份、不猜套数;UI 退回显示"来源站点 + 抓取日期";
/// 3. **纯函数、不联网、不读库**:单测直接覆盖(`test/output_paper_meta_test.dart`)。
library;

/// 一份真题卷的身份(只放"能确认的事实",字段可空)。
class PaperMeta {
  /// 考试年份(如 2023);null = 来源里没写
  final int? year;

  /// 考试月份(1~12);null = 来源里没写
  final int? month;

  /// 第几套(1~20);null = 来源里没写
  final int? setNo;

  /// 来源站点名(如「中国教育考试网」;未知时是 URL host)
  final String siteName;

  /// 来源页面 URL(第一条有效来源)
  final String sourceUrl;

  /// 来源页面标题(原始,便于排查/展示)
  final String pageTitle;

  const PaperMeta({
    this.year,
    this.month,
    this.setNo,
    this.siteName = '',
    this.sourceUrl = '',
    this.pageTitle = '',
  });

  /// 完全没抽到卷面信息(只剩站点/URL 也是常态)
  bool get isEmpty => year == null && month == null && setNo == null;

  /// 一行展示:「2023 年 12 月 · 第 1 套」(缺项自动省略,不留空槽)
  String get label {
    final parts = <String>[];
    if (year != null) {
      parts.add(month == null ? '$year 年' : '$year 年 $month 月');
    }
    if (setNo != null) parts.add('第 $setNo 套');
    return parts.join(' · ');
  }

  /// 标题里用的紧凑写法:「2023 年 12 月第 1 套」/「2023 年」/「」(不猜)
  String get plainLabel {
    final buffer = StringBuffer();
    if (year != null) buffer.write('$year 年');
    if (month != null) buffer.write(' $month 月');
    if (setNo != null) buffer.write('第 $setNo 套');
    return buffer.toString().trim();
  }

  /// 卡片角标用:「2023.12」/「2023」/「」
  String get compactLabel {
    if (year == null) return '';
    if (month == null) return '$year';
    return '$year.${month.toString().padLeft(2, '0')}';
  }

  PaperMeta copyWith({
    int? year,
    int? month,
    int? setNo,
    String? siteName,
    String? sourceUrl,
    String? pageTitle,
  }) =>
      PaperMeta(
        year: year ?? this.year,
        month: month ?? this.month,
        setNo: setNo ?? this.setNo,
        siteName: siteName ?? this.siteName,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        pageTitle: pageTitle ?? this.pageTitle,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'year': year,
        'month': month,
        'set_no': setNo,
        'site_name': siteName,
        'source_url': sourceUrl,
        'page_title': pageTitle,
      };

  static PaperMeta? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return PaperMeta(
      year: _asInt(raw['year']),
      month: _asInt(raw['month']),
      setNo: _asInt(raw['set_no'] ?? raw['set'] ?? raw['setNo']),
      siteName: '${raw['site_name'] ?? raw['siteName'] ?? ''}'.trim(),
      sourceUrl: '${raw['source_url'] ?? raw['sourceUrl'] ?? ''}'.trim(),
      pageTitle: '${raw['page_title'] ?? raw['pageTitle'] ?? ''}'.trim(),
    );
  }

  @override
  String toString() =>
      'PaperMeta($year/$month/第$setNo套, site=$siteName, url=$sourceUrl)';
}

/// 从**真实来源**抽卷面身份(纯函数,不猜)。
///
/// 输入优先级:标题 > URL > 页面首段(只取前 400 字符,避免正文里的年份误伤)。
/// - [title] 检索结果的页面标题(最可靠:「2023年12月大学英语四级真题第1套」);
/// - [url] 来源链接(有些站点把年份月份写在路径里);
/// - [pageText] 抓到的页面正文(抬头常写「2023年12月」);
/// - [siteName] 检索结果给的站点名(缺失时按域名映射);
/// - [publishedAt] 暂不参与年份推断(发布时间 ≠ 考试时间,不能拿来自欺)。
PaperMeta parsePaperMeta({
  String url = '',
  String title = '',
  String pageText = '',
  String siteName = '',
  DateTime? publishedAt,
}) {
  final titleText = _normalizeDigits(title);
  final urlText = _normalizeDigits(_decodeUrl(url));
  final pageHead = _normalizeDigits(
    pageText.length <= 400 ? pageText : pageText.substring(0, 400),
  );

  int? year;
  int? month;

  // ①「2023 年 12 月」/「2023年12月17日」
  final ym = _yearMonthPattern.firstMatch(titleText) ??
      _yearMonthPattern.firstMatch(urlText) ??
      _yearMonthPattern.firstMatch(pageHead);
  if (ym != null) {
    year = int.tryParse(ym.group(1)!);
    final m = int.tryParse(ym.group(2)!);
    if (m != null && m >= 1 && m <= 12) month = m;
  }

  // ②「2023.12」/「2023-12」/「2023/12」(URL 路径里常见)
  if (year == null) {
    final ym2 = _yearMonthPattern2.firstMatch(titleText) ??
        _yearMonthPattern2.firstMatch(urlText) ??
        _yearMonthPattern2.firstMatch(pageHead);
    if (ym2 != null) {
      year = int.tryParse(ym2.group(1)!);
      final m = int.tryParse(ym2.group(2)!);
      if (m != null && m >= 1 && m <= 12) month = m;
    }
  }

  // ③「December 2023」/「2023 December」(英文站点)
  if (year == null) {
    final en = _yearMonthEnPattern.firstMatch(titleText) ??
        _yearMonthEnPattern.firstMatch(urlText) ??
        _yearMonthEnPattern.firstMatch(pageHead) ??
        _monthYearEnPattern.firstMatch(titleText) ??
        _monthYearEnPattern.firstMatch(urlText) ??
        _monthYearEnPattern.firstMatch(pageHead);
    if (en != null) {
      // 两个正则分组顺序不同(年在前 / 月在前):按"哪组是数字"归一
      final g1 = en.group(1)!;
      final g2 = en.group(2)!;
      final g1Year = int.tryParse(g1);
      year = g1Year ?? int.tryParse(g2);
      month = _monthOfEnglish(g1Year == null ? g1 : g2);
    }
  }

  // ④ 只认「20xx 年」;不认裸数字(避免把 120 词/第 3 页误当年份)
  if (year == null) {
    final y = _yearOnlyPattern.firstMatch(titleText) ??
        _yearOnlyPattern.firstMatch(urlText) ??
        _yearOnlyPattern.firstMatch(pageHead);
    if (y != null) year = int.tryParse(y.group(1)!);
  }
  if (year != null && (year < 2000 || year > 2100)) {
    year = null;
    month = null;
  }

  // ⑤ 套数:「第 1 套」/「第一套」/「set 2」/「paper 3」
  int? setNo;
  final zh = _setCnPattern.firstMatch(titleText) ??
      _setCnPattern.firstMatch(pageHead) ??
      _setCnPattern.firstMatch(urlText);
  if (zh != null) {
    setNo = _parseSetNumber(zh.group(1)!);
  }
  if (setNo == null) {
    final en = _setEnPattern.firstMatch(titleText) ??
        _setEnPattern.firstMatch(urlText) ??
        _setEnPattern.firstMatch(pageHead);
    if (en != null) setNo = int.tryParse(en.group(1)!);
  }
  if (setNo != null && (setNo < 1 || setNo > 20)) setNo = null;

  final site = siteName.trim().isNotEmpty ? siteName.trim() : siteLabelOf(url);
  return PaperMeta(
    year: year,
    month: month,
    setNo: setNo,
    siteName: site,
    sourceUrl: url.trim(),
    pageTitle: title.trim(),
  );
}

/// 合并多页来源的卷面信息:**按字段取第一个能确认的值**,不投票、不猜。
///
/// 一页抓不到年份不代表整套没有:检索通常抓到 1~3 页,取第一条命中的来源。
PaperMeta mergePaperMeta(List<PaperMeta> metas) {
  int? year;
  int? month;
  int? setNo;
  var siteName = '';
  var sourceUrl = '';
  var pageTitle = '';
  for (final meta in metas) {
    year ??= meta.year;
    month ??= meta.month;
    setNo ??= meta.setNo;
    if (siteName.isEmpty) siteName = meta.siteName;
    if (sourceUrl.isEmpty) sourceUrl = meta.sourceUrl;
    if (pageTitle.isEmpty) pageTitle = meta.pageTitle;
  }
  return PaperMeta(
    year: year,
    month: month,
    setNo: setNo,
    siteName: siteName,
    sourceUrl: sourceUrl,
    pageTitle: pageTitle,
  );
}

/// 来源站点名(检索结果的 `site_name` 缺失时按域名映射;未知就显示 host)。
String siteLabelOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return '';
  var host = uri.host.trim().toLowerCase();
  if (host.isEmpty) return '';
  if (host.startsWith('www.')) host = host.substring(4);

  for (final entry in _knownSites.entries) {
    if (host == entry.key || host.endsWith('.${entry.key}')) {
      return entry.value;
    }
  }
  return host;
}

/// 考试类型的**短标签**(UI 角标用;长名见 `examLabelFor`)
String examShortLabelFor(String examType) {
  return switch (examType.trim().toLowerCase()) {
    'cet4' => 'CET-4',
    'cet6' => 'CET-6',
    'kaoyan' => '考研',
    'ielts' => '雅思',
    'toefl' => '托福',
    'nce' => '新概念',
    _ => '通用',
  };
}

/// 统一的「来源行」:等级 · 年份套数 · 来源站点 · 校对状态(缺项不留空槽)。
///
/// 三处共用(题库卡 / 答题页 / 历史还原),保证用户看到的来源口径一致。
String examSourceLine({
  required String examType,
  int? paperYear,
  String paperLabel = '',
  String sourceSite = '',
  String verifyStatus = '',
  bool withExam = true,
}) {
  final parts = <String>[];
  if (withExam && examType.trim().isNotEmpty && examType.trim() != 'none') {
    parts.add(examShortLabelFor(examType));
  }
  final paper = paperLabel.trim();
  if (paper.isNotEmpty) {
    parts.add(paper);
  } else if (paperYear != null) {
    parts.add('$paperYear 年');
  }
  final site = sourceSite.trim();
  if (site.isNotEmpty) parts.add(site);
  final verify = verifyStatus.trim().toLowerCase();
  if (verify == 'pending') {
    parts.add('待校对');
  } else if (verify == 'verified') {
    parts.add('已校对');
  }
  return parts.join(' · ');
}

/// 从题组的 `license_note`(出题时写入的来源说明)里取第一个 URL,
/// 再映射成来源站点名。没有 URL → 空串(UI 不显示空槽)。
///
/// 为什么从 note 里取而不是加列:DB 只允许复用现有列(本轮不许加列),
/// 而 `license_note` 本来就完整保存了抓取 URL 列表。
String siteOfLicenseNote(String licenseNote) {
  final note = licenseNote.trim();
  if (note.isEmpty) return '';
  final match = RegExp(r'https?://[^\s,，、;；)）]+').firstMatch(note);
  if (match == null) return '';
  return siteLabelOf(match.group(0)!);
}

/// 从"标题 + 来源说明"里**推断**考试等级(老数据回填用;显式操作、不隐式迁移)。
///
/// 只认明确写法:四级/CET-4 → cet4;六级/CET-6 → cet6;考研/雅思/托福/新概念同理。
/// 「四六级」区分不了四还是六 → null(回填时保持原值,不猜)。
String? inferExamTypeFromText({String title = '', String note = ''}) {
  final text = '$title $note';
  if (text.trim().isEmpty) return null;
  // 「四六级」是泛化写法:含「六级」子串但不是"六级考生",不能据此判 cet6
  final genericCet = text.contains('四六级') || text.contains('四、六级');
  final upper = text.toUpperCase();
  if (RegExp(r'CET[\s\-]?6|BAND[\s\-]?6').hasMatch(upper)) return 'cet6';
  if (RegExp(r'CET[\s\-]?4|BAND[\s\-]?4').hasMatch(upper)) return 'cet4';
  if (!genericCet && text.contains('六级')) return 'cet6';
  if (!genericCet && text.contains('四级')) return 'cet4';
  if (RegExp(r'考研|kaoyan', caseSensitive: false).hasMatch(text)) {
    return 'kaoyan';
  }
  if (RegExp(r'雅思|IELTS', caseSensitive: false).hasMatch(text)) {
    return 'ielts';
  }
  if (RegExp(r'托福|TOEFL', caseSensitive: false).hasMatch(text)) {
    return 'toefl';
  }
  if (RegExp(r'新概念|NCE|New\s*Concept', caseSensitive: false)
      .hasMatch(text)) {
    return 'nce';
  }
  return null;
}

/// 把「4 / 四级 / CET4」这一类自由写法归一成 `cet4`(识别不出返回 null)。
///
/// 与 `output_source.dart` 的 `targetExamOf` 同口径(那里是"多选目标→一个主考试",
/// 这里是"单串→等级"),两处都只认明确写法,不猜。
String? examTypeOfText(String raw) {
  final s = raw
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\-_/]+'), '')
      .trim();
  if (s.isEmpty) return null;
  if (s.contains('六级') || s.contains('cet6') || s.contains('band6')) {
    return 'cet6';
  }
  if (s.contains('四级') || s.contains('cet4') || s.contains('band4')) {
    return 'cet4';
  }
  if (s.contains('考研') || s.contains('kaoyan')) return 'kaoyan';
  if (s.contains('雅思') || s.contains('ielts')) return 'ielts';
  if (s.contains('托福') || s.contains('toefl')) return 'toefl';
  if (s.contains('新概念') || s.contains('nce')) return 'nce';
  // 「四六级」区分不了四还是六 —— 返回 null(由调用方按"通用"处理,不擅自猜)
  return null;
}

// ═══════════════════════════════════════════════════════════════════
// 内部:正则与映射(全部不依赖外部状态)
// ═══════════════════════════════════════════════════════════════════

final RegExp _yearMonthPattern = RegExp(r'(20[0-9]{2})\s*年\s*([0-9]{1,2})\s*月');
final RegExp _yearMonthPattern2 =
    RegExp(r'(20[0-9]{2})[.\-_/]\s*([0-9]{1,2})(?:[.\-_/]\s*[0-9]{1,2})?');
final RegExp _yearMonthEnPattern = RegExp(
  r'(20[0-9]{2})\s*(january|february|march|april|may|june|july|august|september|october|november|december)',
  caseSensitive: false,
);
// 「December 2023」:英文站点常见月在前、年在后(两个正则分组顺序保持一致)
final RegExp _monthYearEnPattern = RegExp(
  r'(january|february|march|april|may|june|july|august|september|october|november|december)\s*,?\s*(20[0-9]{2})',
  caseSensitive: false,
);
final RegExp _yearOnlyPattern = RegExp(r'(20[0-9]{2})\s*年');
final RegExp _setCnPattern = RegExp(r'第\s*([0-9]{1,2}|[一二三四五六七八九十]{1,3})\s*套');
final RegExp _setEnPattern =
    RegExp(r'(?:set|paper|volume)\s*[-_ ]?([0-9]{1,2})', caseSensitive: false);

const Map<String, String> _knownSites = <String, String>{
  'neea.edu.cn': '中国教育考试网',
  'chsi.com.cn': '学信网',
  'eol.cn': '中国教育在线',
  'koolearn.com': '新东方在线',
  'xdf.cn': '新东方',
  'kaoyan.com': '考研帮',
  'exam8.com': '考试吧',
  '51test.net': '无忧考网',
  'zhihu.com': '知乎',
  '163.com': '网易',
  'sina.com.cn': '新浪',
  'qq.com': '腾讯网',
  'sohu.com': '搜狐',
  'people.com.cn': '人民网',
  'xinhuanet.com': '新华网',
  'gutenberg.org': 'Project Gutenberg',
  'wikipedia.org': 'Wikipedia',
};

int? _asInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw');
}

/// 全角数字 → 半角(中文页面里「２０２３」并不罕见)
String _normalizeDigits(String input) {
  if (input.isEmpty) return input;
  final buffer = StringBuffer();
  for (final unit in input.codeUnits) {
    if (unit >= 0xFF10 && unit <= 0xFF19) {
      buffer.writeCharCode(unit - 0xFF10 + 0x30);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// URL 解码(百分号编码里可能藏着中文年份标注)
String _decodeUrl(String url) {
  final text = url.trim();
  if (text.isEmpty) return text;
  try {
    return Uri.decodeFull(text);
  } catch (_) {
    return text;
  }
}

const Map<String, int> _englishMonths = <String, int>{
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
};

int? _monthOfEnglish(String raw) => _englishMonths[raw.toLowerCase()];

/// 中文数字 → int(只覆盖套数会用到的 1~99;识别不出返回 null)
int? _parseSetNumber(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final asInt = int.tryParse(text);
  if (asInt != null) return asInt;
  const digits = <String, int>{
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (text == '十') return 10;
  if (text.length == 1) return digits[text];
  // 十一 / 十二 / 二十 / 二十一
  if (text.startsWith('十') && text.length == 2) {
    final rest = digits[text.substring(1)];
    return rest == null ? null : 10 + rest;
  }
  final tenIndex = text.indexOf('十');
  if (tenIndex > 0) {
    final tens = digits[text.substring(0, tenIndex)];
    final ones = tenIndex == text.length - 1
        ? 0
        : digits[text.substring(tenIndex + 1)];
    if (tens == null || ones == null) return null;
    return tens * 10 + ones;
  }
  return null;
}
