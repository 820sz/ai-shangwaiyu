// 材料源真机前置自检(手工运行,不进 APK、不进 CI)。
//
// 为什么需要:网络探活(HTTP 200)不等于**我们的解析器能出条目** ——
// 源站改版、XML 命名空间变化、编码变化都会让"能连通但列表为空",
// 而那种失败在 App 里看起来跟"连不上"一模一样。这个脚本用**App 自己的
// MaterialSourceService** 跑一遍"列表 → 抓正文 → 切块",把真实结果打出来。
//
// 用法(在项目根目录):
//   dart run tool/probe_sources.dart            # 只跑列表
//   dart run tool/probe_sources.dart --full     # 列表 + 抓一篇正文并切块
//
// 注意:这是**纯 Dart** 脚本,不加载 assets/数据库 —— 只验证网络与解析层。

import 'dart:io';

import 'package:readflow/services/feed_parser.dart' show FeedItem;
import 'package:readflow/services/material_source.dart';

Future<void> main(List<String> args) async {
  final full = args.contains('--full');
  stdout.writeln('== 材料源自检 (full=$full) ==');
  final service = MaterialSourceService.instance;

  for (final source in MaterialSourceService.sources) {
    final sw = Stopwatch()..start();
    try {
      final items = await service.listItems(source.id, limit: 3);
      sw.stop();
      final reachable = MaterialSourceService.measuredReachable.contains(source.id)
          ? '实测可达'
          : '实测不可达';
      if (items.isEmpty) {
        stdout.writeln('${source.id.padRight(11)} 空列表(!)  ${sw.elapsedMilliseconds}ms  '
            '[$reachable]');
        continue;
      }
      stdout.writeln('${source.id.padRight(11)} OK ${items.length} 条  '
          '${sw.elapsedMilliseconds}ms  [$reachable]');
      for (final it in items) {
        final title = it.title.length > 56 ? '${it.title.substring(0, 56)}…' : it.title;
        stdout.writeln('    · ${title.isEmpty ? "(无标题)" : title}');
        stdout.writeln('      ${it.link}');
      }
      if (full && source.id != 'gutenberg') {
        await _probeDocument(service, source, items.first);
      }
    } catch (e) {
      sw.stop();
      stdout.writeln('${source.id.padRight(11)} FAIL ${sw.elapsedMilliseconds}ms  '
          '${_short('$e')}');
    }
  }
  exit(0);
}

Future<void> _probeDocument(
  MaterialSourceService service,
  MaterialSource source,
  FeedItem item,
) async {
  final sw = Stopwatch()..start();
  try {
    final doc = await service.fetchDocument(source.id, url: item.link);
    sw.stop();
    final words = doc.plainText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    stdout.writeln('    ↳ 正文 OK  ${sw.elapsedMilliseconds}ms  '
        'chunks=${doc.chunks.length} words=$words  title=${_short(doc.title, 40)}');
  } catch (e) {
    sw.stop();
    stdout.writeln('    ↳ 正文 FAIL ${sw.elapsedMilliseconds}ms  ${_short('$e')}');
  }
}

String _short(String s, [int max = 110]) {
  final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}
