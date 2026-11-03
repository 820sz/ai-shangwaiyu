/// 基调探索渲图用的字体加载(仅测试/预览用,不进 App)。
///
/// 为什么字体是"基调"的一半:衬线 vs 无衬线 vs 等宽,直接决定"这是杂志 /
/// 工具 / 报刊"。本机可用、且覆盖中文的字体只有几套,这里按用途分开注册,
/// 屏幕上就不会出现方框:
/// - [kSans]  Noto Sans SC(正文/现代方向)
/// - [kSerif] Noto Serif SC(中文衬线)
/// - [kSerifLatin] Georgia(拉丁衬线;中文回落到 [kSerif])
/// - [kMono]  Consolas(等宽标签/数字;中文回落到 [kSans])
library;

import 'dart:io';

import 'package:flutter/services.dart';

const String kSans = 'ProbeSans';
const String kSerif = 'ProbeSerif';
const String kSerifLatin = 'ProbeSerifLatin';
const String kMono = 'ProbeMono';

Future<ByteData?> _readFont(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return ByteData.sublistView(file.readAsBytesSync());
  } catch (_) {
    return null;
  }
}

Future<void> _loadFamily(String family, List<String> candidates) async {
  final loader = FontLoader(family);
  var added = 0;
  for (final path in candidates) {
    final bytes = await _readFont(path);
    if (bytes == null) continue;
    loader.addFont(Future<ByteData>.value(bytes));
    added++;
  }
  if (added == 0) return;
  try {
    await loader.load();
  } catch (_) {
    // 字体损坏时宁可少一套字体,也不要整个渲图管线挂掉
  }
}

/// 注册预览字体(重复调用无副作用)。
Future<void> loadProbeFonts() async {
  await _loadFamily(kSans, <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ]);
  await _loadFamily(kSerif, <String>[
    r'C:\Windows\Fonts\NotoSerifSC-VF.ttf',
    r'C:\Windows\Fonts\simsunb.ttf',
  ]);
  await _loadFamily(kSerifLatin, <String>[
    r'C:\Windows\Fonts\georgia.ttf',
    r'C:\Windows\Fonts\georgiab.ttf',
  ]);
  await _loadFamily(kMono, <String>[
    r'C:\Windows\Fonts\consola.ttf',
    r'C:\Windows\Fonts\consolab.ttf',
  ]);
  // 主题里的默认字体族是 Roboto:不注册的话,任何没显式指定字体的文字
  // (Material 内部文本)在预览里会变成方框。
  await _loadFamily('Roboto', <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ]);
}

/// flutter_test 默认不加载 MaterialIcons:不加载的话预览里所有图标都是方框。
Future<void> loadProbeIcons() async {
  const candidates = <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      await loader.load();
      return;
    } catch (_) {
      // 换下一个候选路径
    }
  }
}
