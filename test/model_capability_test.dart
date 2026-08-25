import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/doubao_api.dart';

/// 模型能力判断回归测试(v1.3.0 问题 0/5):
/// - shouldSendDetailFlag:detail 字段仅豆包/Ark 系发送(DeepSeek 不认未知字段)
/// - modelSupportsImages:豆包系全支持;DeepSeek 仅 vision 系列;未知厂商默认否
void main() {
  group('isVisionCandidate — 主槽位视觉模型过滤(v1.3.0-2 用户实测"一堆乱模型")', () {
    test('保留:vision 模型 + 豆包 seed 系', () {
      expect(isVisionCandidate('deepseek-v4-flash-vision-exp'), isTrue);
      expect(isVisionCandidate('doubao-seed-2-1-turbo-260628'), isTrue);
      expect(isVisionCandidate('doubao-seed-2-0-lite-260428'), isTrue);
      expect(isVisionCandidate('doubao-seed-1-6-vision-250815'), isTrue);
      expect(isVisionCandidate('doubao-seed-1-6-250615'), isTrue); // 新一代系保留
    });

    test('隐藏:方舟老文本模型(用户没开通的一堆)', () {
      expect(isVisionCandidate('doubao-1-5-lite-32k-250115'), isFalse);
      expect(isVisionCandidate('doubao-1-5-pro-256k-250115'), isFalse);
      expect(isVisionCandidate('doubao-1-5-pro-32k-250115'), isFalse);
      expect(isVisionCandidate('doubao-1-5-pro-32k-character-250228'), isFalse);
      expect(isVisionCandidate('doubao-1-5-pro-32k-character-250715'), isFalse);
    });

    test('隐藏:方舟原 DS 转售文本模型(与官方 DS 视觉不同名)', () {
      expect(isVisionCandidate('deepseek-v4-flash-ga-260731'), isFalse);
      expect(isVisionCandidate('deepseek-v4-pro-260425'), isFalse);
      expect(isVisionCandidate('deepseek-v4-pro-ga-260813'), isFalse);
      expect(isVisionCandidate('deepseek-r1-250120'), isFalse);
      expect(isVisionCandidate('deepseek-r1-distill-qwen-32b-250120'), isFalse);
      expect(isVisionCandidate('deepseek-v3-1-250821'), isFalse);
    });
  });

  group('shouldSendDetailFlag', () {    test('豆包系全部发送 detail', () {
      for (final m in [
        'doubao-seed-2-1-turbo-260628',
        'doubao-seed-2-0-lite-260428',
        'doubao-seed-1-6-vision-250815',
        'doubao-seed-evolving',
      ]) {
        expect(shouldSendDetailFlag(m), isTrue, reason: m);
      }
    });

    test('DeepSeek 视觉模型不发送 detail', () {
      expect(shouldSendDetailFlag('deepseek-v4-flash-vision-exp'), isFalse);
    });

    test('其他兼容模型不发送 detail', () {
      expect(shouldSendDetailFlag('gpt-4o'), isFalse);
    });
  });

  group('modelSupportsImages', () {
    test('豆包系支持图片', () {
      expect(modelSupportsImages('doubao-seed-2-1-turbo-260628'), isTrue);
      expect(modelSupportsImages('doubao-seed-2-0-lite-260428'), isTrue);
    });

    test('DeepSeek vision 系列支持图片', () {
      expect(modelSupportsImages('deepseek-v4-flash-vision-exp'), isTrue);
    });

    test('DeepSeek 纯文本模型不支持图片', () {
      expect(modelSupportsImages('deepseek-v4-flash'), isFalse);
      expect(modelSupportsImages('deepseek-v4-pro'), isFalse);
    });

    test('未知厂商默认不带图(稳妥,避免 400 双倍耗时)', () {
      expect(modelSupportsImages('gpt-4o'), isFalse);
      expect(modelSupportsImages('some-unknown-model'), isFalse);
    });
  });

  group('followUp 用户消息组装(多模态/纯文本)', () {
    final parts = DoubaoApiService.buildFollowUpUserContent(
      context: '词汇上下文',
      question: '这页讲了什么?',
      imageDataUris: ['data:image/png;base64,AAAA'],
      model: 'deepseek-v4-flash-vision-exp',
    ) as List<dynamic>;

    test('带图 → content parts 含 image_url + text', () {
      expect(parts, hasLength(2));
      expect(parts[0]['type'], 'image_url');
      expect(parts[0]['image_url']['url'], 'data:image/png;base64,AAAA');
      expect(parts[0]['image_url']['detail'], isNull); // DS 不发 detail
      expect(parts[1]['type'], 'text');
      expect(parts[1]['text'], contains('这页讲了什么'));
      expect(parts[1]['text'], contains('词汇上下文'));
    });

    test('豆包系带图 → 发 detail: low', () {
      final doubaoParts = DoubaoApiService.buildFollowUpUserContent(
        context: 'c',
        question: 'q',
        imageDataUris: ['data:image/png;base64,AAAA'],
        model: 'doubao-seed-2-1-turbo-260628',
      ) as List<dynamic>;
      expect(doubaoParts[0]['image_url']['detail'], 'low');
    });

    test('无图 → 纯文本字符串(副槽位文本模型兼容)', () {
      final text = DoubaoApiService.buildFollowUpUserContent(
        context: '词汇上下文',
        question: '这页讲了什么?',
        imageDataUris: null,
        model: 'deepseek-v4-flash',
      );
      expect(text, isA<String>());
      expect(text, contains('词汇上下文\n\n用户提问：这页讲了什么?'));
    });
  });
}
