import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/exercise.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/api_endpoint.dart';
import 'package:readflow/services/base_api.dart';
import 'package:readflow/services/doubao_api.dart';
import 'package:readflow/utils/review_deck.dart';

/// v1.9.0 回归测试 —— 覆盖审查报告里"已错过一次"的每一类缺陷。
void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_v19_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    hiveDir.deleteSync(recursive: true);
  });

  group('SSE 解析(P1-2:中文跨包 / CRLF / 多行 data / 上限)', () {
    // ⚠️ v1.9.1 真机回归:流必须是 **Stream<Uint8List>**(dio 的响应流就是这个
    // 运行时类型)。用 Stream<List<int>> 造流会把这条路径测绿,而真机上
    // `utf8.decoder`(StreamTransformer<List<int>, String>)会被运行时类型检查
    // 拒绝:type 'Utf8Decoder' is not a subtype of type
    // 'StreamTransformer<Uint8List, String>' —— v1.9.0 就是这么把识图打挂的。
    Future<List<SseChunk>> parse(List<Uint8List> chunks) =>
        DoubaoApiService.parseSseStream(
          Stream<Uint8List>.fromIterable(chunks),
        ).toList();

    Uint8List frame(String text, {bool reasoning = false}) {
      final key = reasoning ? 'reasoning_content' : 'content';
      final payload = jsonEncode({
        'choices': [
          {
            'delta': {key: text},
          },
        ],
      });
      return utf8.encode('data: $payload\n\n');
    }

    test('中文被切在两个 TCP 包之间 → 不再解成乱码', () async {
      final full = frame('扭转，改变');
      final cut = full.length ~/ 2; // 故意切在多字节字符中间
      final chunks = await parse([full.sublist(0, cut), full.sublist(cut)]);
      expect(chunks.length, 1);
      expect(chunks.first.text, '扭转，改变'); // 旧实现会得到 U+FFFD
      expect(chunks.first.text.contains('\uFFFD'), isFalse);
    });

    test('CRLF 分帧也能解析(旧实现只认 \\n\\n)', () async {
      final payload = jsonEncode({
        'choices': [
          {
            'delta': {'content': 'hello'},
          },
        ],
      });
      final bytes = utf8.encode('data: $payload\r\n\r\n');
      final chunks = await parse([bytes]);
      expect(chunks.single.text, 'hello');
    });

    test('一个事件多条 data: → 拼接后解析', () async {
      final payload = jsonEncode({
        'choices': [
          {
            'delta': {'content': 'joined'},
          },
        ],
      });
      final half = payload.length ~/ 2;
      final bytes = utf8.encode(
        'data: ${payload.substring(0, half)}\ndata: ${payload.substring(half)}\n\n',
      );
      final chunks = await parse([bytes]);
      expect(chunks.single.text, 'joined');
    });

    test('[DONE] 与空事件被忽略,reasoning/content 分流', () async {
      final chunks = await parse([
        frame('thinking', reasoning: true),
        frame('answer'),
        utf8.encode('data: [DONE]\n\n'),
      ]);
      expect(chunks.length, 2);
      expect(chunks[0].isReasoning, isTrue);
      expect(chunks[1].isReasoning, isFalse);
    });

    test('全是无法解析的帧 → 抛出可诊断错误(不再静默 0 输出)', () async {
      expect(
        () => parse([utf8.encode('data: not-json\n\n')]),
        throwsA(isA<Exception>()),
      );
    });

    // ── v1.9.1 真机回归(用户实测"识图直接用不了了") ──
    test('回归:dio 真实流类型 StreamController<Uint8List> 不再抛类型错', () async {
      // 真机报错:type 'Utf8Decoder' is not a subtype of type
      // 'StreamTransformer<Uint8List, String>' of 'streamTransformer'
      final ctrl = StreamController<Uint8List>();
      final done = DoubaoApiService.parseSseStream(ctrl.stream).toList();
      ctrl.add(
        utf8.encode(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'ok'},
              },
            ],
          })}\n\n',
        ),
      );
      await ctrl.close();
      final chunks = await done;
      expect(chunks.single.text, 'ok');
    });

    test('回归:非 SSE 端点返回的整块 JSON 也不因类型转换炸(单块 Uint8List)', () async {
      // 与上面同源:真实链路里 chunk 可能只有一块,类型仍是 Uint8List
      final chunks = await parse([frame('单块')]);
      expect(chunks.single.text, '单块');
    });
  });

  group('降级策略(P1-4:一次到位,不做无意义重发)', () {
    test('同时去掉 reasoning_effort 并关闭 thinking', () {
      final out = BaseApiService.degradeOnce({
        'model': 'x',
        'reasoning_effort': 'max',
        'thinking': {'type': 'enabled'},
      });
      expect(out, isNotNull);
      expect(out!.containsKey('reasoning_effort'), isFalse);
      expect(out['thinking'], {'type': 'disabled'});
    });

    test('没有可降级字段 → 返回 null(调用方直接失败,不重发)', () {
      expect(BaseApiService.degradeOnce({'model': 'x'}), isNull);
    });
  });

  group('请求体按端点族构建(P2-19:方舟上的 deepseek 模型不再错判)', () {
    test('DS 官方:省略 max_tokens/temperature,流式带 stream_options', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(AppConstants.keyDoubaoBaseUrl, AppConstants.deepseekBaseUrl);
      await box.put(AppConstants.keyDoubaoModel, 'deepseek-v4-flash-vision-exp');
      await box.put(AppConstants.keyDoubaoThinking, 'disabled');
      final body = BaseApiService.buildChatBody(
        cfg: ApiEndpointConfig.primary,
        stream: true,
        messages: const [],
      );
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
      expect(body['stream_options'], {'include_usage': true});
    });

    test('方舟端点 + deepseek 模型名:显式 max_tokens,且不发 stream_options', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(AppConstants.keyDoubaoBaseUrl, 'https://ark.cn-beijing.volces.com/api/v3');
      await box.put(AppConstants.keyDoubaoModel, 'deepseek-v3-1-250821');
      await box.put(AppConstants.keyDoubaoThinking, 'disabled');
      final body = BaseApiService.buildChatBody(
        cfg: ApiEndpointConfig.primary,
        stream: true,
        messages: const [],
      );
      expect(body['max_tokens'], 4096);
      expect(body.containsKey('stream_options'), isFalse);
      expect(ApiEndpointConfig.primary.isDeepSeekOfficial, isFalse);
    });
  });

  group('写译批改解析(P2-17:围栏外带说明文字 / score 归一)', () {
    test('前置说明 + ```json 围栏 → 仍能解析', () {
      final r = DoubaoApiService.parseWritingReview(
        '好的，我来批改这份作文：\n```json\n{"score":88,"correction":"ok","issues":[]}\n```\n以上。',
      );
      expect(r['score'], '88');
      expect(r['correction'], 'ok');
    });

    test('score 归一:85分 → 85,超界截断,缺失给空串', () {
      expect(
        DoubaoApiService.parseWritingReview('{"score":"85分"}')['score'],
        '85',
      );
      expect(
        DoubaoApiService.parseWritingReview('{"score":120}')['score'],
        '100',
      );
      expect(DoubaoApiService.parseWritingReview('{}')['score'], '');
    });
  });

  group('识别结果解析(P2-15/A14:围栏与夹带说明文字)', () {
    test('围栏后还有文字 → 仍能解析', () {
      final items = DoubaoApiService.parseResponse(
        '```json\n{"items":[{"word":"spin","translation":"扭转"}]}\n```\n以上是识别结果',
      );
      expect(items.single['word'], 'spin');
    });

    test('解析失败时异常不携带全文(只报长度)', () {
      try {
        DoubaoApiService.parseResponse('这不是 JSON，' * 50);
        fail('应当抛异常');
      } catch (e) {
        expect(e.toString().length < 200, isTrue);
        expect(e.toString().contains('这不是 JSON'), isFalse);
      }
    });
  });

  group('截断清洗(P2-16:合法带点词不被误替换)', () {
    test('etc... 保持原样(词与释义不错配)', () {
      expect(
        DoubaoApiService.cleanTruncatedWord(
          'etc...',
          'word',
          'etc... you know the rest of it.',
        ),
        'etc...',
      );
    });

    test('单词被截断仍回退整句(原有行为保留)', () {
      expect(
        DoubaoApiService.cleanTruncatedWord(
          'understand…',
          'word',
          'You must understand the rules.',
        ),
        'You must understand the rules.',
      );
    });
  });

  group('复习进度(P1-5:标记与断点一起存)', () {
    Vocabulary v(int id, String word) =>
        Vocabulary(id: id, word: word, translation: 'x');

    test('marks / lastId 往返后仍可读', () {
      final p = ReviewProgress(
        deckIds: const [1, 2, 3],
        index: 1,
        countMastered: 1,
        countLearning: 0,
        countNew: 1,
        filterLevel: -1,
        filterDays: 0,
        flipped: false,
        updatedAt: DateTime(2026, 9, 19),
        marks: const {1: 2, 2: 0},
        lastId: 2,
      );
      final back = ReviewProgress.fromJson(p.toJson());
      expect(back.marks, {1: 2, 2: 0});
      expect(back.lastId, 2);
    });

    test('续看按断点词 id 定位,而不是保存时的下标', () {
      final current = [v(1, 'a'), v(2, 'b'), v(3, 'c')];
      final p = ReviewProgress(
        deckIds: const [1, 2, 3],
        index: 0, // 旧下标指向 a
        countMastered: 0,
        countLearning: 0,
        countNew: 0,
        filterLevel: -1,
        filterDays: 0,
        flipped: false,
        updatedAt: DateTime(2026, 9, 19),
        lastId: 3, // 断点是 c
      );
      final restored = restoreDeck(current, p);
      expect(restored.index, 2); // 落在 c,而不是 a
    });
  });

  group('练习答案编码(P2-3:JSON 取代 ||| 拼串)', () {
    test('往返一致,且答案里含 ||| 也不错位', () {
      final encoded = Exercise.encodeAnswers(['a|||b', '', 'c']);
      expect(encoded.startsWith('['), isTrue);
      expect(Exercise.decodeAnswers(encoded), ['a|||b', '', 'c']);
    });

    test('兼容历史 ||| 数据', () {
      expect(Exercise.decodeAnswers('hello|||world'), ['hello', 'world']);
      expect(Exercise.decodeAnswers(null), isEmpty);
    });
  });
}
