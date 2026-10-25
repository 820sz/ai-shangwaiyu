import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';

/// 写译批改的用户设置(v2.13,用户 2026-10-20 第 3 条):
/// **预设提示词**可查看/修改/恢复默认,**思考强度**可选,且下次进来自动带回。
///
/// 为什么单独收一个类:
/// - 提示词是"发给模型的口径",散在页面里迟早和 API 层的默认值漂移 ——
///   这里只保留一份 [defaultPrompt],API 层与设置页都从这里取;
/// - 思考档位必须按**批改实际使用的模型族**取表(豆包 2 档 / DeepSeek 4 档),
///   不能复用识图或追问的档位(那两条链路各自有独立存储);
/// - 页面只读这里,不直接碰 Hive key,日后换存储只改一处。
class WritingReviewSettings {
  WritingReviewSettings._();

  /// 默认批改提示词(**唯一一份**)。
  ///
  /// 内容纪律(每条都对应界面上会出问题的地方):
  /// - 固定 JSON 结构:页面靠 score/issues/error_summary/correction/summary 渲染,
  ///   少一个字段用户就看不到对应区块;
  /// - `original` 必须照抄原文:结果页的每条错误都要能定位到用户写的那一句,
  ///   也是「点错误追问」时带给 AI 的上下文;
  /// - `error_summary` 四个键固定,缺键时界面按类渲染会留白。
  ///
  /// 用户改过就整段替换(不拼接),所以这里写的是"一份完整可用的提示词",
  /// 而不是只写几条风格要求。
  static const String defaultPrompt =
      '''你是一名严谨耐心的英语写作老师。请批改用户提交的英文写作，返回 JSON：
{"score":整数0-100,"correction":"修改后的完整英文（保留原意，标点拼写语法修正）",
"issues":[{"original":"原文片段","correction":"修改后","type":"词汇|语法|表达优化|其他","reason":"错误原因与中文解释"}],
"error_summary":{"词汇":"这一类问题的汇总（没有则空串）","语法":"...","表达优化":"...","其他":"..."},
"summary":"总体评语（中文，60字内）"}。
要求：
1. issues 覆盖影响正确性与表达质量的错误；同类小错可以合并成一条，但 original 必须是能直接在原文中定位的片段（照抄，不要改写）；
2. type 只能取「词汇 / 语法 / 表达优化 / 其他」之一；
3. error_summary 必须四个键齐全，用中文总结每一类错误的共性问题与改进方向（每条 40 字内），没有该类错误就留空字符串；
4. 不输出 JSON 以外的任何内容。''';

  /// 默认思考档位:保持改造前的行为(不思考,快且省钱),用户可主动调高。
  static const String defaultThinking = 'disabled';

  static Box get _box => Hive.box(AppConstants.hiveBoxSettings);

  /// 当前生效的提示词:没自定义过 → 默认;自定义过 → 用户副本。
  /// 读取失败(测试环境没开 Hive / 数据损坏)一律回默认,绝不把页面打崩。
  static String prompt() {
    try {
      final raw = _box.get(AppConstants.keyWritingReviewPrompt);
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    } catch (e) {
      debugPrint('ReadFlow 读取写译批改提示词失败(用默认): $e');
    }
    return defaultPrompt;
  }

  /// 用户是否改过提示词(设置入口上要显示「默认 / 已自定义」)。
  static bool get isPromptCustomized =>
      prompt().trim() != defaultPrompt.trim();

  /// 保存提示词。传空/全空白、或内容与默认一致 → **删除**自定义副本,
  /// 等价于恢复默认(而不是把一份默认文本写进 Hive —— 那会冻结旧版本,
  /// 以后 App 更新默认提示词时这些用户永远收不到)。
  ///
  /// 返回是否写入成功:设置页要据此提示用户,不能"看起来保存了其实没存"。
  static Future<bool> savePrompt(String value) async {
    final text = value.trim();
    try {
      if (text.isEmpty || text == defaultPrompt.trim()) {
        await _box.delete(AppConstants.keyWritingReviewPrompt);
      } else {
        await _box.put(AppConstants.keyWritingReviewPrompt, text);
      }
      return true;
    } catch (e) {
      debugPrint('ReadFlow 保存写译批改提示词失败: $e');
      return false;
    }
  }

  /// 恢复默认提示词(等价于 [savePrompt] 传空串)。
  static Future<bool> restoreDefaultPrompt() => savePrompt('');

  /// 当前模型的合法思考档位表;未知/空模型名时按豆包族兜底(与 API 默认一致)。
  static Map<String, String> thinkingOptionsFor(String model) =>
      AppConstants.thinkingOptionsFor(
        model.trim().isEmpty ? AppConstants.doubaoVisionModel : model,
      );

  /// 当前生效的思考档位。
  ///
  /// [model] 是**批改实际使用的模型**:档位表随模型族变化(豆包只有
  /// 不思考/低,DeepSeek 有 low/high/max)。存量值在新模型下不合法时
  /// 回默认,而不是把非法枚举发给官方 API(会直接 400)。
  static String thinkingFor(String model) {
    final options = thinkingOptionsFor(model);
    try {
      final raw = _box.get(AppConstants.keyWritingReviewThinking);
      if (raw is String && options.containsKey(raw)) return raw;
    } catch (e) {
      debugPrint('ReadFlow 读取写译批改思考档位失败(用默认): $e');
    }
    return defaultThinking;
  }

  /// 保存思考档位;只写档位表里的值(防手滑/旧数据写进非法值)。
  /// 返回是否写入成功。
  static Future<bool> setThinking(String model, String level) async {
    final allowed = thinkingOptionsFor(model).keys.toSet();
    if (!allowed.contains(level)) {
      debugPrint('ReadFlow 写译批改思考档位非法,忽略: $level');
      return false;
    }
    try {
      await _box.put(AppConstants.keyWritingReviewThinking, level);
      return true;
    } catch (e) {
      debugPrint('ReadFlow 保存写译批改思考档位失败: $e');
      return false;
    }
  }

  /// 档位的显示名(找不到就原样显示,避免出现空白)。
  static String thinkingLabel(String model, String level) =>
      thinkingOptionsFor(model)[level] ?? level;
}
