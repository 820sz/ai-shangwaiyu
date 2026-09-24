import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/screens/input/widgets/quick_replies.dart';

/// 快捷回复测试(v2.4,B1)。
///
/// 用户要的是"追问界面里几个待定的快捷回复(英英词典;梳理内容;……)"。
/// 这里锁三件事:**按钮短、问题清楚、不越权**(快捷回复只提问,不替用户下结论)。
void main() {
  test('默认那一排包含用户点名的两项,且不超过一屏能点完的数量', () {
    final labels = QuickReplies.defaults.map((r) => r.label).toList();
    expect(labels, contains('英英词典'));
    expect(labels, contains('梳理内容'));
    expect(labels.length, lessThanOrEqualTo(6), reason: '一排太多就没人点了');
    expect(labels.toSet().length, labels.length, reason: '标签不能重复');
  });

  test('按钮文字短(≤6 字),问题文字清楚(≥10 字)', () {
    for (final r in QuickReplies.defaults) {
      expect(r.label.length, lessThanOrEqualTo(6), reason: r.label);
      expect(r.prompt.length, greaterThanOrEqualTo(10), reason: r.label);
      expect(r.prompt.trim(), r.prompt, reason: '${r.label}: 问题首尾不该有空白');
    }
  });

  test('英英词典:要求英文释义(不是把中文释义换个说法)', () {
    final r = QuickReplies.defaults.firstWhere((x) => x.label == '英英词典');
    expect(r.prompt, contains('英文释义'));
    expect(r.prompt, contains('English'));
    expect(r.prompt, contains('例句'));
  });

  test('考我一下:先说"不要给答案" —— 否则等于用户直接看答案', () {
    final r = QuickReplies.defaults.firstWhere((x) => x.label == '考我一下');
    expect(r.prompt, contains('不要给答案'));
    expect(r.prompt, contains('批改'));
  });

  test('逐句翻译:要求通顺、不逐词硬译(对应用户反馈的"生硬翻译")', () {
    final r = QuickReplies.defaults.firstWhere((x) => x.label == '逐句翻译');
    expect(r.prompt, contains('不要逐词硬译'));
    expect(r.prompt, contains('对照'));
  });

  test('梳理内容:要结构化笔记,不要复述原文', () {
    final r = QuickReplies.defaults.firstWhere((x) => x.label == '梳理内容');
    expect(r.prompt, contains('主旨'));
    expect(r.prompt, contains('不要复述原文'));
  });
}
