import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 界面文案闸门(静态扫描 lib/screens 与 lib/widgets)。
///
/// 为什么需要它:AI 生成内容会渲染 Markdown(flutter_markdown),但**普通 Text
/// 不会** —— 把 `**重点**` 写进界面文案,用户看到的就是两个字面星号。
/// 这个 bug 在 v2.5 的走查里一次抓到 7 处(材料中心、方向页、听写页、备份页×3、
/// 外观页、小组件页),全是同一类疏忽,所以固化成闸门。
///
/// **只查字符串字面量,不查注释**:`/// 依据**学习画像**推荐` 是 Dart 文档注释里
/// 的 Markdown 强调,本来就该这么写,也永远不会显示给用户。
///
/// 边界:
/// - 只扫界面层(`lib/screens`、`lib/widgets`);`lib/services` 里的提示词
///   (发给模型的 system prompt)用 `**` 强调是**合理**的,不在扫描范围;
/// - 允许列表里必须写清理由,不做整体豁免。
void main() {
  /// 判断某一行里 `**` 是否落在字符串字面量中。
  ///
  /// 做法:数 `**` 之前出现的引号个数 —— 奇数说明"此刻正在字符串里"。
  /// 单行字符串与相邻字面量拼接(每行各带引号)都适用;纯注释行直接跳过。
  bool isInStringLiteral(String line, int index) {
    var quotes = 0;
    for (var i = 0; i < index; i++) {
      final ch = line[i];
      if (ch == "'" || ch == '"') quotes++;
    }
    return quotes.isOdd;
  }

  test('界面文案里不出现 Markdown 星号(Text 不渲染 Markdown,用户会看到 ** )', () {
    final pattern = RegExp(r'\*\*');
    final allowed = <String>[
      // 目前没有需要豁免的行 —— 真要加,必须写明"为什么这里显示星号是对的"
    ];

    final offenders = <String>[];
    for (final dir in ['lib/screens', 'lib/widgets']) {
      final root = Directory(dir);
      expect(root.existsSync(), isTrue, reason: '测试必须从项目根目录运行');
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          // 纯注释行(/// 或 //)不查
          if (trimmed.startsWith('//')) continue;
          for (final m in pattern.allMatches(line)) {
            if (!isInStringLiteral(line, m.start)) continue;
            if (allowed.any(line.contains)) continue;
            offenders.add('$path:${i + 1}  ${line.trim()}');
            break; // 一行只报一次
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些文案在界面上会显示成字面星号(Text 不渲染 Markdown)。\n'
          '要么去掉星号,要么用「」做强调:\n${offenders.join('\n')}',
    );
  });
}
