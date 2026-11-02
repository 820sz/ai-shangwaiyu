import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 识图链路**架构约束闸门**(B0-3,2026-11-01)。
///
/// ## 为什么用"扫描源码"而不是行为测试
/// "结果出现后追加图片概率闪退"的根因不是某一行写错,而是三件事叠加:
/// 1. 同一功能两条入口的压缩参数不一致(首页 1024/q50 vs 追加 2600/q92,像素≈6.4 倍);
/// 2. 多图预处理用 `Future.wait` 并发解码(峰值 = 张数 × 单张解码量);
/// 3. 结果出现后自动跑的「高清分块复查」与新图预处理同时在整图解码。
/// 最后是 **native OOM/ANR 被系统杀**,Dart 层 CrashLogger 抓不到,真机也难稳定复现。
/// 所以这里把"架构约束"固化成源码闸门:谁再往图片预处理里加并发、或者把参数
/// 改回大图,这个测试先红 —— 比等下一次用户闪退再来查便宜得多。
///
/// 做法参考 `test/theme_test.dart` / `test/ui_copy_lint_test.dart` 的硬编码闸门:
/// 读源码 + 断言子串/结构,不做运行时模拟。找不到标记直接 fail(方法改名/删除时
/// 闸门必须一起更新,不能静默放行)。
void main() {
  /// 从项目根读 `lib/` 下源码(与 ui_copy_lint_test 同约定:flutter test 的 CWD = 项目根)
  String readLib(String relativePath) {
    final file = File(relativePath);
    expect(
      file.existsSync(),
      isTrue,
      reason: '测试必须从项目根目录运行,读不到 $relativePath',
    );
    return file.readAsStringSync().replaceAll('\r\n', '\n');
  }

  /// 截取"从 [start] 标记开始、到 [end] 标记之前"的一段源码。
  /// 找不到任一个标记就 fail —— 闸门靠标记定位,标记消失说明结构变了。
  String sectionOf(String src, String start, String end) {
    final from = src.indexOf(start);
    expect(from, greaterThanOrEqualTo(0), reason: '找不到起始标记: $start');
    final to = src.indexOf(end, from + start.length);
    expect(to, greaterThan(from), reason: '找不到结束标记: $end(位于 $start 之后)');
    return src.substring(from, to);
  }

  /// 去掉注释行(`//` 与 `///`)后的**纯代码**:闸门只查真实代码。
  ///
  /// 为什么必须剥注释:根因说明里写着"旧实现用 Future.wait 并发解码",
  /// 不剥的话闸门会被自己的注释误报(与 ui_copy_lint_test 只查字符串字面量
  /// 同一原则:注释永远不会被执行)。
  String codeOnly(String source) => source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  group('doubao_api:多图预处理必须串行 + 走后台 isolate(B0-3 闸门)', () {
    late String api;

    setUpAll(() => api = readLib('lib/services/doubao_api.dart'));

    /// 三个"多图入口"的源码段(已剥注释,只留真实代码)。用方法下一个方法的
    /// 文档注释当边界,避免把整个文件扫进去导致误判。
    Map<String, String> multiImageSections() => {
          'extractFullTextStream': codeOnly(sectionOf(
            api,
            'Stream<SseChunk> extractFullTextStream(',
            '/// **单词语境讲解**',
          )),
          'extractVocabularyStream': codeOnly(sectionOf(
            api,
            'Stream<SseChunk> extractVocabularyStream(',
            '/// **第二遍',
          )),
          'imageDataUrisFor': codeOnly(sectionOf(
            api,
            'Future<List<String>> imageDataUrisFor(',
            '// ── 写译批改',
          )),
        };

    test('三个多图入口里不得出现 Future.wait(并发解码/编码)→ 必须串行', () {
      final offenders = <String>[];
      multiImageSections().forEach((name, body) {
        if (body.contains('Future.wait')) {
          offenders.add(name);
        }
      });
      expect(
        offenders,
        isEmpty,
        reason: '这些方法又用 Future.wait 并发处理多图了:$offenders\n'
            '并发会让峰值内存 = 张数 × 单张解码量(12MP 图 RGBA ≈20MB),'
            '这就是"追加图片概率闪退"的直接原因。改成 for 循环逐张 await。',
      );
    });

    test('三个多图入口必须逐张 await _imageToDataUri(串行正向断言)', () {
      multiImageSections().forEach((name, body) {
        expect(
          body.contains('await _imageToDataUri('),
          isTrue,
          reason: '$name 没有逐张 await _imageToDataUri —— 预处理可能被并发或绕过',
        );
      });
    });

    test('_imageToDataUri 必须走后台 isolate(compute),不能直接同步 toDataUri', () {
      final body = codeOnly(sectionOf(
        api,
        'Future<String> _imageToDataUri(',
        '/// 通过文件头魔数检测图片 MIME 类型',
      ));
      expect(
        body.contains('toDataUriInBackground('),
        isTrue,
        reason: '识图预处理必须在后台 isolate 里做(整图解码 ≈20MB/张跑 UI isolate '
            '会卡死主线程 → ANR)。只允许"isolate 失败后的主 isolate 兜底"调用 '
            'VisionImagePrep.toDataUri。',
      );
    });
  });

  group('三条识图入口的压缩参数必须一致(B0-3 闸门)', () {
    // 规则:1600 / q85(2026-11-01 lead 决策)。
    // 首页拍照 + 相册 + 结果页追加 = 三条入口;任意一条被改回 1024/q50 或
    // 2600/q92 都算回归 —— "两条入口参数不一致"正是本 bug 的根因之一。
    const expectedMaxWidth = 'maxWidth: 1600';
    const expectedQuality = 'imageQuality: 85';

    void expectUnifiedParams(String entry, String body) {
      expect(body.contains(expectedMaxWidth), isTrue,
          reason: '$entry 的 maxWidth 必须与其它入口统一为 1600(见 B0-3)');
      expect(body.contains(expectedQuality), isTrue,
          reason: '$entry 的 imageQuality 必须与其它入口统一为 85(见 B0-3)');
    }

    test('input_home:拍照与相册两个入口都是 1600/q85', () {
      final home = readLib('lib/screens/input/input_home.dart');
      expectUnifiedParams(
        '首页拍照(_takePhoto)',
        sectionOf(home, 'Future<void> _takePhoto()', 'Future<void> _pickFromGallery()'),
      );
      expectUnifiedParams(
        '首页相册(_pickFromGallery)',
        sectionOf(home, 'Future<void> _pickFromGallery()', '/// 调用系统裁剪界面'),
      );
    });

    test('process_chat:追加图片入口也是 1600/q85', () {
      final chat = readLib('lib/screens/input/process_chat.dart');
      expectUnifiedParams(
        '结果页追加(_addMoreImages)',
        sectionOf(chat, 'Future<void> _addMoreImages()', '/// **方向不对?旋转重试**'),
      );
    });
  });

  group('追加与第二遍高清复查不得并发整图解码(B0-3 闸门)', () {
    late String chat;

    setUpAll(() => chat = readLib('lib/screens/input/process_chat.dart'));

    test('追加/旋转/重识别前必须调用 _waitMissedPassExit 让复查先退出', () {
      final addMore = codeOnly(sectionOf(
        chat,
        'Future<void> _addMoreImages()',
        '/// **方向不对?旋转重试**',
      ));
      expect(
        addMore.contains('await _waitMissedPassExit()'),
        isTrue,
        reason: '追加前必须先让第二遍高清复查退出(两者都是整图解码,并发 = OOM)。',
      );
      final rotate = codeOnly(sectionOf(
        chat,
        'Future<void> _rotateAndRetry()',
        'Future<void> _waitMissedPassExit()',
      ));
      expect(rotate.contains('await _waitMissedPassExit()'), isTrue,
          reason: '旋转重试同样是整批整图解码,必须先让复查退出。');
    });

    test('第二遍复查必须带取消信号检查(每个 await 后都能尽早退出)', () {
      final missed = codeOnly(sectionOf(
        chat,
        'Future<void> _startMissedPass()',
        'void _onStreamDone()',
      ));
      expect(
        missed.contains('_missedPassCancelRequested'),
        isTrue,
        reason: '复查没有取消信号 → 追加时无法让它让路,会与追加并发解码(OOM 回归)。',
      );
      // 至少 3 处检查:循环开头、readAsBytes 之后、切块/请求之后
      expect(
        RegExp(r'_missedPassCancelRequested').allMatches(missed).length,
        greaterThanOrEqualTo(3),
        reason: '取消信号检查太少:复查可能在多个 await 之间继续解码。',
      );
    });
  });
}
