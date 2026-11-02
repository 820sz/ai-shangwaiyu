/// 阅读器翻译单元 + 一轮翻译的进度状态机(v2.13.1)。
///
/// 背景(用户 2026-11-01 原话:「里面的文章阅读器的翻译功能永远没法用,翻译进度
/// 永远是死的」):阅读器的正文是按 **2500 词一块**入库的(`chunkByWords`),
/// 旧实现把「块」当成「段」——
/// - 进度分母 = 本轮入队块数,典型文章只有 1 块 → 进度条永远 0/1,字面意义上
///   的「死条」;而且完成时先把分母清零再渲染,100% 那一帧根本没机会出现;
/// - 一次请求把整块(最多 6000 词)当「1 段」发出去,模型按空行回 N 段,
///   调用方只声明 1 段 → 段数对不上 → 只"抢救"第一段译文,note 还被静默丢弃;
/// - 界面上「段下译文」也就只能一块一段,做不到逐段英中对照。
///
/// 所以翻译的最小单元必须是**真段落**(空行分隔)。本文件负责三件纯逻辑:
/// 1. [splitUnits]:把正文块拆成段落单元(超长段再按句子/空格二次切);
/// 2. [chunkFirstUnitIndices]:块下标 → 单元下标的映射(可见性判断 / 续读跳转);
/// 3. [TranslationRunState]:一轮翻译的进度状态机(可单测 —— 旧实现"100% 帧被
///    清零吞掉"正是没有可测状态机的代价)。
library;

/// 一个翻译单元:正文里的**一个真段落**。
class ReaderUnit {
  /// 来源正文块下标(`material_content.chunk_index`;块仍是加载/进度/AI 内容块
  /// 的单位,只有"翻译"的最小单元换成了段落)。
  final int chunkIndex;

  /// 在该块内的第几个自然段(0-based)。超长段被二次切分时,各片段共用同一
  /// [paraIndex] —— 它们原本就是同一段。
  final int paraIndex;

  /// 这一段原文(已 trim;二次切分的片段不含首尾分隔空白)。
  final String text;

  const ReaderUnit({
    required this.chunkIndex,
    required this.paraIndex,
    required this.text,
  });

  @override
  String toString() =>
      'ReaderUnit(chunk=$chunkIndex, para=$paraIndex, ${text.length}字)';
}

/// 单个翻译单元的字符上限:一个请求只发一段。
///
/// 600 字符≈100 词,翻译 3~10 秒;失败/超时只影响这一段。超过就二次切,
/// 避免个别超长段把单请求拖过 45 秒超时(长材料"永远失败"的次要原因)。
const int kReaderUnitMaxChars = 600;

/// 把正文块拆成翻译单元(纯函数,可单测)。
///
/// 规则:
/// - 按**空行**拆真段落(`\n\s*\n`;模型/入库文本可能有 `\r\n` 或行尾空格);
/// - 每段 trim 后为空 → 丢弃(空行不是段);
/// - 某段超过 [maxChars] → 先按句末标点打包,单句仍超长再按空格硬切;
/// - **顺序保持**:单元顺序 = 原文阅读顺序;`chunkIndex/paraIndex` 可反查来源;
/// - 内容不丢:切分只在空白处断开,把片段拼回去与原文只差空白。
///
/// 边界:整块都是空白的块不会产生单元(阅读器会为"全文没有任何文字"的极端
/// 材料做兜底,见 `material_reader_screen._load`)。
List<ReaderUnit> splitUnits(
  List<Map<String, Object?>> chunks, {
  int maxChars = kReaderUnitMaxChars,
}) {
  final limit = maxChars < 40 ? 40 : maxChars; // 防御:过小会把词切成碎片
  final units = <ReaderUnit>[];
  for (var ci = 0; ci < chunks.length; ci++) {
    final raw = '${chunks[ci]['text'] ?? ''}';
    final paragraphs = raw
        .split(RegExp(r'\r?\n[ \t\r]*\r?\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    for (var pi = 0; pi < paragraphs.length; pi++) {
      final p = paragraphs[pi];
      if (p.length <= limit) {
        units.add(ReaderUnit(chunkIndex: ci, paraIndex: pi, text: p));
        continue;
      }
      for (final piece in _splitLongParagraph(p, limit)) {
        units.add(ReaderUnit(chunkIndex: ci, paraIndex: pi, text: piece));
      }
    }
  }
  return units;
}

/// 块下标 → 该块**第一个翻译单元**的下标(长度 = [chunkCount])。
///
/// 用途:① "可见块 → 可见单元"展开与续读跳转;② 块没有任何非空段时也不越界 ——
/// 指向"下一个有段落的块"的首个单元,末尾则指向 `units.length`。
List<int> chunkFirstUnitIndices(List<ReaderUnit> units, int chunkCount) {
  final out = List<int>.filled(chunkCount < 0 ? 0 : chunkCount, -1);
  for (var i = 0; i < units.length; i++) {
    final ci = units[i].chunkIndex;
    if (ci >= 0 && ci < out.length && out[ci] < 0) out[ci] = i;
  }
  var next = units.length;
  for (var ci = out.length - 1; ci >= 0; ci--) {
    if (out[ci] >= 0) {
      next = out[ci];
    } else {
      out[ci] = next;
    }
  }
  return out;
}

/// 一轮翻译的进度状态机(纯逻辑,可单测)。
///
/// 为什么必须独立成类:旧实现把 `_runTotal/_runDone` 散在 State 里,
/// "最后一段完成后先清零、再 setState" → `1/1 = 100%` 那一帧**从来没有被
/// 渲染过**,用户看到的进度条永远是 0%。顺序类 bug 只有可单测的状态机锁得住。
///
/// 语义:
/// - 分母 = 本轮真正入队的**单元数**(典型文章 6~10,不再是"块数"恒 1);
/// - 每完成/失败/取消一个单元都算"已处理" → +1(界面上"已完成"= 有结果了);
/// - 全部处理完后 [markFinished] 先把分子补到分母(界面能渲染 100%),
///   由调用方延时 [clear] 收尾 —— "先让用户看见 100%,再收条"。
class TranslationRunState {
  int _total = 0;
  int _done = 0;
  DateTime? _startedAt;

  /// 本轮单元总数(0 = 当前没有一轮翻译)
  int get total => _total;

  /// 已处理单元数(夹紧在 [0, total],显示层不用再防负数)
  int get done => _done > _total ? _total : _done;

  /// 计时起点(进度条"已用时"用),null = 没有进行中的一轮
  DateTime? get startedAt => _startedAt;

  /// 是否有一轮翻译(界面据此显示进度条)
  bool get visible => _total > 0;

  /// 进度值 0.0~1.0(分母为 0 时返回 0,不产生 NaN)
  double get progress => _total <= 0 ? 0 : done / _total;

  /// 本轮是否已全部处理完(分子追平分母)
  bool get finished => _total > 0 && done >= _total;

  /// 开新一轮:上一轮已空闲时调用,重置分子/计时并以 [count] 个单元起算。
  void begin(int count, {DateTime? now}) {
    _total = count < 0 ? 0 : count;
    _done = 0;
    _startedAt = _total > 0 ? (now ?? DateTime.now()) : null;
  }

  /// 同一轮里继续追加单元(随读随翻 / 继续翻后文 / 整章)。
  ///
  /// 若当前没有一轮(上一轮已收尾),等价于 [begin] —— 不要拿旧分母继续加。
  void add(int count, {DateTime? now}) {
    final n = count < 0 ? 0 : count;
    if (n == 0) return;
    if (_total == 0) {
      begin(n, now: now);
    } else {
      _total += n;
    }
  }

  /// 处理完一个单元(成功/失败/取消都算"已处理",不会重复 +1 超过总数)。
  void completeOne() {
    if (_total > 0 && _done < _total) _done += 1;
  }

  /// 收尾:把分子补满,让界面**先渲染一帧 100%**(这是本类存在的核心原因)。
  void markFinished() {
    if (_total > 0) _done = _total;
  }

  /// 清空(收条):进度条消失,回到"随读随翻"的常态文案。
  void clear() {
    _total = 0;
    _done = 0;
    _startedAt = null;
  }
}

// ═══════════════ 内部:超长段二次切分 ═══════════════

/// 超长段 → 多个 ≤[limit] 的片段(纯函数)。
///
/// 先按句末标点断句并尽量打包,单句仍超长才按空格硬切 —— 保证:
/// ① 片段都不超过上限(单请求可控);② 不切断单词(硬切点只在空格);
/// ③ 非空白字符一个不丢(测试锁定)。
List<String> _splitLongParagraph(String p, int limit) {
  final pieces = <String>[];
  final buf = StringBuffer();
  void flush() {
    final s = buf.toString().trim();
    if (s.isNotEmpty) pieces.add(s);
    buf.clear();
  }

  for (final sentence in _splitSentences(p)) {
    if (buf.length + sentence.length <= limit) {
      buf.write(sentence);
      continue;
    }
    flush();
    if (sentence.length <= limit) {
      buf.write(sentence);
      continue;
    }
    // 单句超长:按空格硬切成 ≤limit 的块(切点前的部分先落,余下继续)
    var rest = sentence.trimLeft();
    while (rest.length > limit) {
      final cut = _lastSpaceAt(rest, limit);
      if (cut <= 0) {
        // 整段没有空格(URL/无空格长词):只能按字符硬切,保证不超上限
        pieces.add(rest.substring(0, limit));
        rest = rest.substring(limit);
      } else {
        pieces.add(rest.substring(0, cut).trim());
        rest = rest.substring(cut).trimLeft();
      }
    }
    if (rest.isNotEmpty) buf.write(rest);
  }
  flush();
  return pieces;
}

/// 按句末标点(+可选的收尾引号/括号)断句;返回的片段保留原标点。
///
/// 不用正则 lookbehind:不同平台/版本的 RegExp 行为不完全一致,
/// 手写扫描可解释、可测,且只在"标点后跟空白"处断(尽力避免切断 `Mr.` /
/// `3.14` 这类——切错了也只是片段粒度粗一点,不影响正确性)。
List<String> _splitSentences(String text) {
  final out = <String>[];
  var start = 0;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (ch == '.' || ch == '!' || ch == '?' || ch == '。' || ch == '！' || ch == '？') {
      var j = i + 1;
      // 标点后紧跟的引号/括号算同一句
      while (j < text.length && '"\u201d)\u300d】'.contains(text[j])) {
        j++;
      }
      if (j >= text.length || _isSpace(text[j])) {
        out.add(text.substring(start, j));
        // 跳过断句处的空白,下一句从非空白开始
        while (j < text.length && _isSpace(text[j])) {
          j++;
        }
        start = j;
        i = j;
        continue;
      }
    }
    i++;
  }
  if (start < text.length) out.add(text.substring(start));
  return out;
}

bool _isSpace(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r';

/// 在 [limit] 之前(含)找最后一个空格的位置;没找到返回 -1。
int _lastSpaceAt(String s, int limit) {
  final end = limit < s.length ? limit : s.length;
  for (var i = end; i > 0; i--) {
    if (s[i - 1] == ' ') return i;
  }
  return -1;
}
