import 'word_frequency.dart';

/// 词形还原("原型备注",v2.4,B2 用户要求):`taming` → `tame`。
///
/// 用户场景:生词本里全是 `running` / `studies` / `taken` 这种变形,背的时候
/// 需要一眼看到原型。展示成 `taming(tame)` 就够,不需要改库里存的东西。
///
/// 设计原则:
/// 1. **只在有把握时给原型** —— 用内嵌的 5 万词频表验证候选:
///    还原出来的 `tame` 必须本身是个真词(在词频表里),否则宁可不显示。
///    这挡住了"把 bus 还原成 bu""把 news 还原成 new"这类笑话。
/// 2. 纯函数、可单测(词频表用 `debugInject` 注入确定性词表)。
/// 3. 不猜短语/句子(有空格直接放弃),不猜专有名词(全大写放弃)。
class Lemma {
  Lemma._();

  /// 不规则动词/名词的小表(规则推导覆盖不到的常见词)
  static const Map<String, String> _irregular = {
    // be
    'am': 'be', 'is': 'be', 'are': 'be', 'was': 'be', 'were': 'be',
    'been': 'be', 'being': 'be',
    // 高频不规则动词
    'went': 'go', 'gone': 'go', 'goes': 'go',
    'did': 'do', 'done': 'do', 'does': 'do',
    'had': 'have', 'has': 'have',
    'made': 'make', 'took': 'take', 'taken': 'take',
    'came': 'come', 'got': 'get', 'gotten': 'get',
    'said': 'say', 'saw': 'see', 'seen': 'see',
    'gave': 'give', 'given': 'give', 'found': 'find',
    'thought': 'think', 'brought': 'bring', 'bought': 'buy',
    'felt': 'feel', 'kept': 'keep', 'left': 'leave',
    'lost': 'lose', 'met': 'meet', 'paid': 'pay',
    'ran': 'run', 'sold': 'sell',
    'sent': 'send', 'sat': 'sit', 'slept': 'sleep',
    'spoke': 'speak', 'spoken': 'speak', 'stood': 'stand',
    'taught': 'teach', 'told': 'tell', 'understood': 'understand',
    'wrote': 'write', 'written': 'write', 'won': 'win',
    'wore': 'wear', 'worn': 'wear', 'knew': 'know', 'known': 'know',
    'grew': 'grow', 'grown': 'grow', 'drew': 'draw', 'drawn': 'draw',
    'drove': 'drive', 'driven': 'drive', 'ate': 'eat', 'eaten': 'eat',
    'fell': 'fall', 'fallen': 'fall', 'hid': 'hide', 'hidden': 'hide',
    'held': 'hold', 'hurt': 'hurt', 'let': 'let', 'put': 'put',
    'read': 'read', 'rose': 'rise', 'risen': 'rise',
    'sang': 'sing', 'sung': 'sing', 'shut': 'shut',
    'spent': 'spend', 'swam': 'swim', 'swum': 'swim',
    'threw': 'throw', 'thrown': 'throw', 'began': 'begin',
    'begun': 'begin', 'broke': 'break', 'broken': 'break',
    'chose': 'choose', 'chosen': 'choose', 'forgot': 'forget',
    'forgotten': 'forget', 'lay': 'lie', 'laid': 'lay',
    // 不规则复数
    'children': 'child', 'men': 'man', 'women': 'woman',
    'teeth': 'tooth', 'feet': 'foot', 'mice': 'mouse',
    'geese': 'goose', 'people': 'person', 'lives': 'life',
    'knives': 'knife', 'wives': 'wife', 'leaves': 'leaf',
    'shelves': 'shelf', 'wolves': 'wolf', 'thieves': 'thief',
    'criteria': 'criterion', 'phenomena': 'phenomenon',
    'analyses': 'analysis', 'theses': 'thesis', 'crises': 'crisis',
    // 不规则比较级(用户可能一起收)
    'better': 'good', 'best': 'good', 'worse': 'bad', 'worst': 'bad',
  };

  /// 取出原型;没有把握时返回 null(界面就不显示括号备注)
  ///
  /// [isRealWord] 默认用内嵌词频表判断"候选是不是真词";测试可注入。
  static String? baseOf(
    String word, {
    bool Function(String candidate)? isRealWord,
  }) {
    final raw = word.trim();
    if (raw.isEmpty) return null;
    // 短语/句子不猜
    if (raw.contains(RegExp(r'\s'))) return null;
    // 专有名词/全大写缩写不猜(Apple/HTML)
    if (raw == raw.toUpperCase() && raw.length > 1) return null;
    // 带连字符/撇号/数字的词不猜(nature-versus-nurture、don't、p12)
    if (RegExp(r"[-'’\d]").hasMatch(raw)) return null;

    final w = raw.toLowerCase();
    final real = isRealWord ?? _isRealWord;

    // 不规则表优先(短词也照样给:children→child)
    final irregular = _irregular[w];
    if (irregular != null && irregular != w && real(irregular)) {
      return irregular;
    }

    // 太短的词不做规则推导(is→i? no)
    if (w.length < 5) return null;

    for (final candidate in _candidates(w)) {
      if (candidate == w) continue;
      if (candidate.length < 3) continue;
      if (real(candidate)) return candidate;
    }
    return null;
  }

  /// 规则候选(按"最可能"的顺序)
  static List<String> _candidates(String w) {
    final out = <String>[];
    // 复数/三单
    if (w.endsWith('ies')) {
      out.add('${w.substring(0, w.length - 3)}y'); // studies → study
    }
    if (w.endsWith('es')) {
      out.add(w.substring(0, w.length - 2)); // watches → watch
    }
    if (w.endsWith('s')) {
      out.add(w.substring(0, w.length - 1)); // apples → apple
    }
    // 进行时
    if (w.endsWith('ing')) {
      final stem = w.substring(0, w.length - 3);
      out.add('${stem}e'); // taking → take
      out.add(stem); // walking → walk
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        out.add(stem.substring(0, stem.length - 1)); // running → run
      }
      if (stem.endsWith('y')) out.add(stem); // studying → study
    }
    // 过去式/过去分词
    if (w.endsWith('ied')) {
      out.add('${w.substring(0, w.length - 3)}y'); // studied → study
    }
    if (w.endsWith('ed')) {
      final stem = w.substring(0, w.length - 2);
      out.add(stem); // walked → walk
      out.add('${stem}e'); // loved → love
      if (stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]) {
        out.add(stem.substring(0, stem.length - 1)); // stopped → stop
      }
    }
    return out;
  }

  static bool _isRealWord(String candidate) {
    // 词频表没加载时**不猜**(宁可没有备注,也不要给错原型)
    if (!WordFrequency.isLoaded) return false;
    return WordFrequency.rankOf(candidate) > 0;
  }
}
