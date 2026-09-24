import 'package:flutter/material.dart';

/// 追问界面的**快捷回复**(v2.4,B1 用户要求)。
///
/// 用户原话:"英英词典的部分,不需要太多笔墨,我只有在个别词才会用到,
/// 改为选用(也就是追问界面里,提供几个待定的快捷回复 —— 英英词典;梳理内容;……)"。
///
/// 设计取舍:
/// - 快捷回复发的是**提问**,不是固定答案 —— 模型仍会结合当前材料/识别结果回答,
///   所以"英英词典"拿到的是**这个词在这个语境下**的英文解释,而不是词典搬运;
/// - 文案短、动词开头,点一下就走;不放太多(一排 4~5 个,能一屏点完);
/// - [prompt] 是真正发出去的内容,[label] 是按钮上的字 —— 两者分开,
///   才能"按钮很短、问题很清楚"。
class QuickReply {
  /// 按钮上的字
  final String label;

  /// 实际发给 AI 的问题
  final String prompt;

  const QuickReply({required this.label, required this.prompt});
}

class QuickReplies {
  QuickReplies._();

  /// 默认那一排(顺序 = 展示顺序)
  static const List<QuickReply> defaults = [
    QuickReply(
      label: '英英词典',
      prompt: '用英英词典的方式解释上面内容里的关键词:给出英文释义(English definition)、'
          '词性,以及一个英文例句。如果内容里有多个关键词,挑最值得记的 3-5 个,'
          '每个都用英文解释,不要只说中文。',
    ),
    QuickReply(
      label: '梳理内容',
      prompt: '把上面的内容梳理成一份便于复习的结构化笔记:主旨一句话、'
          '分点要点、值得记的表达(附中文)、以及我该重点掌握的地方。'
          '用中文写,条理清楚,不要复述原文。',
    ),
    QuickReply(
      label: '逐句翻译',
      prompt: '把上面的英文内容逐句翻译成中文,每句一行(英文 + 中文对照),'
          '翻译要通顺、符合中文表达习惯,不要逐词硬译。',
    ),
    QuickReply(
      label: '考我一下',
      prompt: '根据上面的内容出 3 道小测题考我(2 道理解题 + 1 道用词填空),'
          '先只给题目、不要给答案;我回答后再批改并解释。',
    ),
    QuickReply(
      label: '换个简单说法',
      prompt: '把上面内容里较难的句子用更简单的英文重说一遍(保持原意),'
          '并指出难点在哪里(语法结构或固定搭配)。',
    ),
  ];
}

/// 一排快捷回复按钮(横向滚动,点一下即发送)
class QuickReplyBar extends StatelessWidget {
  final void Function(String prompt) onPick;
  final bool enabled;
  final List<QuickReply> replies;

  const QuickReplyBar({
    super.key,
    required this.onPick,
    this.enabled = true,
    this.replies = QuickReplies.defaults,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: replies.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final r = replies[i];
          return ActionChip(
            avatar: Icon(
              _iconOf(r.label),
              size: 15,
              color: theme.colorScheme.primary,
            ),
            label: Text(r.label, style: const TextStyle(fontSize: 12)),
            onPressed: enabled ? () => onPick(r.prompt) : null,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        },
      ),
    );
  }

  /// 按钮图标跟着语义走(不用 emoji:字号/基线在不同机型上会跳)
  static IconData _iconOf(String label) => switch (label) {
        '英英词典' => Icons.menu_book_outlined,
        '梳理内容' => Icons.checklist_outlined,
        '逐句翻译' => Icons.translate_outlined,
        '考我一下' => Icons.quiz_outlined,
        '换个简单说法' => Icons.emoji_objects_outlined,
        _ => Icons.bolt_outlined,
      };
}
