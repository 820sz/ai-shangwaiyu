import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/doubao_api.dart';

/// 模型能力判断回归测试(v1.3.0 问题 0/5;v2.6 按 DeepSeek V4.1 更新):
/// - isVisionCandidate:主槽位只列"能吃图"的模型
/// - shouldSendDetailFlag:detail 字段豆包/Ark 与 **DeepSeek 官方多模态**都发
///   (2026-09-10 V4.1-Flash 上线后官方支持 low/high/original/auto)
/// - modelSupportsImages:豆包系全支持;DeepSeek 仅官方多模态名单;未知厂商默认否
void main() {
  group('isVisionCandidate — 主槽位视觉模型过滤(v1.3.0-2 用户实测"一堆乱模型")', () {
    test('保留:vision 模型 + 豆包 seed 系 + DeepSeek 官方多模态', () {
      expect(isVisionCandidate('deepseek-v4-flash-vision-exp'), isTrue);
      expect(isVisionCandidate('deepseek-flash'), isTrue, reason: 'V4.1-Flash');
      expect(isVisionCandidate('deepseek-v4-flash'), isTrue,
          reason: '旧名,官方路由到 V4.1-Flash');
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

    test('隐藏:方舟原 DS 转售文本模型(与官方 DS 多模态不同名)', () {
      expect(isVisionCandidate('deepseek-v4-flash-ga-260731'), isFalse,
          reason: 'v2.6:不能因为名字里有 flash 就当成多模态');
      expect(isVisionCandidate('deepseek-v4-pro-260425'), isFalse);
      expect(isVisionCandidate('deepseek-v4-pro-ga-260813'), isFalse);
      expect(isVisionCandidate('deepseek-r1-250120'), isFalse);
      expect(isVisionCandidate('deepseek-r1-distill-qwen-32b-250120'), isFalse);
      expect(isVisionCandidate('deepseek-v3-1-250821'), isFalse);
    });
  });

  group('shouldSendDetailFlag', () {
    test('豆包系全部发送 detail', () {
      for (final m in [
        'doubao-seed-2-1-turbo-260628',
        'doubao-seed-2-0-lite-260428',
        'doubao-seed-1-6-vision-250815',
        'doubao-seed-evolving',
      ]) {
        expect(shouldSendDetailFlag(m), isTrue, reason: m);
      }
    });

    test('DeepSeek 官方多模态发送 detail(v2.6 修正:以前一律不发)', () {
      expect(shouldSendDetailFlag('deepseek-flash'), isTrue);
      expect(shouldSendDetailFlag('deepseek-v4-flash-vision-exp'), isTrue);
    });

    test('对方舟转售的 DS 文本模型不发(它不接受图片)', () {
      expect(shouldSendDetailFlag('deepseek-v4-flash-ga-260731'), isFalse);
      expect(shouldSendDetailFlag('deepseek-v4-pro'), isFalse);
    });

    test('其他兼容模型不发送 detail', () {
      expect(shouldSendDetailFlag('gpt-4o'), isFalse);
    });

    test('识别场景一律要高清(v2.6:low 会把整页压到 512×512)', () {
      expect(recognitionDetailLevel('doubao-seed-2-1-turbo-260628',
          calibrate: false), 'high');
      expect(recognitionDetailLevel('deepseek-flash', calibrate: false), 'high');
      expect(recognitionDetailLevel('deepseek-flash', calibrate: true), 'high');
      expect(recognitionDetailLevel('gpt-4o', calibrate: false), isNull);
    });
  });

  group('modelSupportsImages', () {
    test('豆包系支持图片', () {
      expect(modelSupportsImages('doubao-seed-2-1-turbo-260628'), isTrue);
      expect(modelSupportsImages('doubao-seed-2-0-lite-260428'), isTrue);
    });

    test('DeepSeek 官方多模态支持图片(V4.1-Flash)', () {
      expect(modelSupportsImages('deepseek-v4-flash-vision-exp'), isTrue);
      expect(modelSupportsImages('deepseek-flash'), isTrue);
      expect(modelSupportsImages('deepseek-v4-flash'), isTrue);
    });

    test('DeepSeek 纯文本模型不支持图片', () {
      expect(modelSupportsImages('deepseek-v4-pro'), isFalse);
      expect(modelSupportsImages('deepseek-v4-flash-ga-260731'), isFalse);
    });

    test('未知厂商默认不带图(稳妥,避免 400 双倍耗时)', () {
      expect(modelSupportsImages('gpt-4o'), isFalse);
      expect(modelSupportsImages('some-unknown-model'), isFalse);
    });
  });

  group('followUp 最后一条 user 消息组装(多模态/纯文本)', () {
    final parts = DoubaoApiService.buildFollowUpLastUserContent(
      question: '这页讲了什么?',
      imageDataUris: ['data:image/png;base64,AAAA'],
      model: 'deepseek-flash',
    ) as List<dynamic>;

    test('带图 → content parts 含 image_url + text(只有问题,无重复上下文)', () {
      expect(parts, hasLength(2));
      expect(parts[0]['type'], 'image_url');
      expect(parts[0]['image_url']['url'], 'data:image/png;base64,AAAA');
      expect(parts[0]['image_url']['detail'], 'high'); // v2.6:追问也要高清
      expect(parts[1]['type'], 'text');
      expect(parts[1]['text'], '用户提问：这页讲了什么?');
    });

    test('豆包系带图 → 同样发 detail: high', () {
      final doubaoParts = DoubaoApiService.buildFollowUpLastUserContent(
        question: 'q',
        imageDataUris: ['data:image/png;base64,AAAA'],
        model: 'doubao-seed-2-1-turbo-260628',
      ) as List<dynamic>;
      expect(doubaoParts[0]['image_url']['detail'], 'high');
    });

    test('无图 → 纯问题文本', () {
      final text = DoubaoApiService.buildFollowUpLastUserContent(
        question: '这页讲了什么?',
        imageDataUris: null,
        model: 'deepseek-v4-pro',
      );
      expect(text, isA<String>());
      expect(text, '用户提问：这页讲了什么?');
    });
  });
}
