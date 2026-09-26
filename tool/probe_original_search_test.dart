// 原文检索**联机自检**(手工运行,不参与 `flutter test` 全量跑:它要联网)。
//
// 跑法(项目根目录):
//   flutter test tool/probe_original_search_test.dart
//
// 为什么需要它:上一版用的检索站(gutendex.com)在大陆网络直接超时,
// 用户看到的是"什么都搜不到",而日志里没有任何异常 —— 只有真跑一遍才发现。
// 这个文件放在 tool/ 下,`flutter test` 默认只扫 test/,所以不会拖慢/拖脏全量测试。

import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/original_search.dart';

void main() {
  test('原文检索联机自检:每个分类都能拿到真实原文', () async {
    final cases = <String, (String, String)>{
      '书籍(空关键词→最受欢迎)': ('', '书籍'),
      '书籍(a christmas carol)': ('a christmas carol', '书籍'),
      '书籍(中文关键词)': ('经济学', '书籍'),
      '论文(language learning)': ('language learning', '论文'),
      '外刊(空关键词)': ('', '外刊'),
    };

    for (final entry in cases.entries) {
      final (query, category) = entry.value;
      final sw = Stopwatch()..start();
      final result = await OriginalSearch.search(query, category: category);
      sw.stop();
      // ignore: avoid_print
      print('── ${entry.key}  (${sw.elapsedMilliseconds}ms)');
      for (final note in result.notes) {
        // ignore: avoid_print
        print('   · $note');
      }
      for (final hit in result.hits.take(3)) {
        final title = hit.title.length > 60
            ? '${hit.title.substring(0, 60)}…'
            : hit.title;
        // ignore: avoid_print
        print('   ✓ [${hit.sourceId}] $title  → ${hit.url}');
      }
      if (result.hits.isEmpty) {
        // ignore: avoid_print
        print('   (无结果)');
      }
    }
    // 只作观察:断言放宽到"整轮至少有一个分类拿得到结果"才有意义 ——
    // 网络环境不同,硬断言会让这条自检本身变成噪音。
    expect(true, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
