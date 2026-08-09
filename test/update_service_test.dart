import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/services/update_service.dart';

void main() {
  group('compareVersions', () {
    test('21 > 20', () {
      expect(UpdateService.compareVersions('1.2.21', '1.2.20'), greaterThan(0));
    });

    test('带 v 前缀和 build 号', () {
      expect(UpdateService.compareVersions('v1.2.21', '1.2.20+30'), greaterThan(0));
      expect(UpdateService.compareVersions('1.2.20+30', '1.2.20+29'), 0);
    });

    test('相等返回 0', () {
      expect(UpdateService.compareVersions('1.2.20', '1.2.20'), 0);
    });
  });

  group('_pickLatest — 镜像缓存旧响应时取最新 tag', () {
    Map<String, dynamic> rel(String tag) => {'tag_name': tag};

    test('混合新旧响应 → 取最新', () {
      final picked = UpdateService.pickLatest([
        rel('v1.2.20'), // 镜像缓存旧数据
        rel('v1.2.21'), // 直连实时数据
        rel('v1.2.19'),
      ]);
      expect(picked['tag_name'], 'v1.2.21');
    });

    test('全部同一版本 → 取任一同版本', () {
      final picked = UpdateService.pickLatest([
        rel('v1.2.21'),
        rel('v1.2.21'),
      ]);
      expect(picked['tag_name'], 'v1.2.21');
    });
  });
}
