import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import '../models/material_recommendation.dart';
import '../models/vocabulary.dart';

/// 学习画像存取(v1.8.0):Hive 持久化 + 从词库推断建议值。
class LearnerProfileStore {
  static const String key = 'learner_profile';

  static Box get _box => Hive.box(AppConstants.hiveBoxSettings);

  static LearnerProfile load() {
    try {
      final raw = _box.get(key);
      if (raw is Map) {
        return LearnerProfile.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    return const LearnerProfile();
  }

  static Future<void> save(LearnerProfile profile) async {
    await _box.put(key, profile.toJson());
  }

  /// 从词库推断画像建议(纯函数,可单测):
  /// 词汇量 → 水平档;来源书籍/分类 → 兴趣题材。
  /// 只填空字段——用户已填的内容不覆盖。
  static LearnerProfile suggestFromVocab(
    List<Vocabulary> vocab, {
    LearnerProfile base = const LearnerProfile(),
  }) {
    if (vocab.isEmpty) return base;

    // 水平:按收录词量粗估(词汇量是最直接的证据)
    final count = vocab.length;
    final String level;
    if (count < 50) {
      level = '入门（A1-A2）';
    } else if (count < 150) {
      level = '初级（A2-B1）';
    } else if (count < 400) {
      level = '中级（B1-B2）';
    } else if (count < 800) {
      level = '中高级（B2-C1）';
    } else {
      level = '高级（C1-C2）';
    }

    // 兴趣:从来源书籍/分类关键词猜题材
    final interests = <String>{...base.interests};
    final haystack = vocab
        .take(300)
        .map((v) => '${v.sourceBook ?? ''} ${v.category ?? ''}')
        .join(' ')
        .toLowerCase();
    void addIf(bool hit, String interest) {
      if (hit) interests.add(interest);
    }

    addIf(
      RegExp(r'news|economist|times|guardian|bbc|外刊|新闻').hasMatch(haystack),
      '新闻时事',
    );
    addIf(
      RegExp(r'science|nature|tech|科普|科技|physics|biology').hasMatch(haystack),
      '科普科技',
    );
    addIf(
      RegExp(r'business|econom|finance|财经|商业').hasMatch(haystack),
      '商业财经',
    );
    addIf(
      RegExp(r'novel|fiction|harry|story|小说|文学|character').hasMatch(haystack),
      '小说故事',
    );
    addIf(
      RegExp(r'history|culture|历史|文化').hasMatch(haystack),
      '历史文化',
    );
    addIf(
      RegExp(r'fitness|growth|habit|成长|心理').hasMatch(haystack),
      '个人成长',
    );

    return base.copyWith(
      level: base.level.isEmpty ? level : base.level,
      interests: interests.toList(),
    );
  }
}
