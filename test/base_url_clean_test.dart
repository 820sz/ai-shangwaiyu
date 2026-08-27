import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/api_endpoint.dart';

/// Base URL 清洗回归测试(v1.3.2):
/// 用户真机从聊天/笔记粘贴 Base URL 时带 全角冒号/空格/换行/BOM,
/// Dio 抛 "Illegal scheme character (at character 5)" → 识别失败(截图实锤)。
void main() {
  group('cleanBaseUrl', () {
    test('正常 URL 原样保留', () {
      expect(
        ApiEndpointConfig.cleanBaseUrl('https://api.deepseek.com'),
        'https://api.deepseek.com',
      );
    });

    test('全角冒号 → 半角(用户实锤场景)', () {
      expect(
        ApiEndpointConfig.cleanBaseUrl('https：//api.deepseek.com'),
        'https://api.deepseek.com',
      );
    });

    test('尾部换行/空格 → 清除', () {
      expect(
        ApiEndpointConfig.cleanBaseUrl('https://api.deepseek.com \n'),
        'https://api.deepseek.com',
      );
    });

    test('内部空白(粘贴折行)→ 清除', () {
      expect(
        ApiEndpointConfig.cleanBaseUrl('https://api.deepseek.com\n/chat'),
        'https://api.deepseek.com/chat',
      );
    });

    test('BOM/全角斜杠 → 替换', () {
      expect(
        ApiEndpointConfig.cleanBaseUrl('\uFEFFhttps：//api.deepseek。com'),
        'https://api.deepseek。com',
      );
    });
  });

  group('normalizedBaseUrl', () {
    test('合法 → 返回清洗值', () {
      expect(
        ApiEndpointConfig.normalizedBaseUrl('https：//api.deepseek.com'),
        'https://api.deepseek.com',
      );
    });

    test('http:// → 归一 https://(云端 301/302 重定向导致 Dio 报错)', () {
      expect(
        ApiEndpointConfig.normalizedBaseUrl('http://api.deepseek.com'),
        'https://api.deepseek.com',
      );
      expect(
        ApiEndpointConfig.normalizedBaseUrl('http://ark.cn-beijing.volces.com'),
        'https://ark.cn-beijing.volces.com',
      );
    });

    test('空 → null(走默认端点)', () {
      expect(ApiEndpointConfig.normalizedBaseUrl(''), isNull);
      expect(ApiEndpointConfig.normalizedBaseUrl('   '), isNull);
    });

    test('非 http/https 开头(如 api.deepseek.com)= null(不合法)', () {
      expect(ApiEndpointConfig.normalizedBaseUrl('api.deepseek.com'), isNull);
      expect(ApiEndpointConfig.normalizedBaseUrl('ftp://x.com'), isNull);
    });
  });
}
