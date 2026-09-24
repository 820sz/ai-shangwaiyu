import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/material_source.dart';
import 'package:readflow/services/material_source_status.dart';

/// 内容源可用性记忆的测试(2026-09-24 用户实测"材料中心没法用"后新增)。
///
/// 这组测试锁的是三件**很容易改错、改错了用户就会看到失败第一屏**的事:
/// 1. 默认源必须是实测可达的(不能再退回"列表第一个 = BBC");
/// 2. 记住成功/失败后,"下次落在哪个源"的选择规则;
/// 3. 记录本身要能容错(脏 JSON / 坏字段不能让材料中心打不开)。
void main() {
  group('默认源', () {
    test('默认源是实测可达的 NPR,且它在源清单里', () {
      expect(MaterialSourceService.defaultSourceId, 'npr');
      expect(
        MaterialSourceService.sourceOf(MaterialSourceService.defaultSourceId),
        isNotNull,
      );
    });

    test('默认源不能是"列表第一个"(旧 bug:第一个是 BBC,大陆必超时)', () {
      expect(
        MaterialSourceService.sources.first.id,
        isNot(MaterialSourceService.defaultSourceId),
        reason: '如果哪天把默认源改回列表首项,这条会红 —— 除非实测证明它可达',
      );
    });

    test('实测可达清单里的 id 都是真实存在的源(防止打错字导致标记失效)', () {
      for (final id in MaterialSourceService.measuredReachable) {
        expect(MaterialSourceService.sourceOf(id), isNotNull, reason: id);
      }
    });
  });

  group('SourceHealth 解析与文案', () {
    test('正常往返', () {
      final h = SourceHealth(ok: false, at: DateTime(2026, 9, 24, 10), message: '超时');
      final parsed = SourceHealth.parse(h.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.ok, isFalse);
      expect(parsed.message, '超时');
      expect(parsed.at, DateTime(2026, 9, 24, 10));
    });

    test('脏数据当"没记录"(返回 null),不抛异常', () {
      expect(SourceHealth.parse(null), isNull);
      expect(SourceHealth.parse('not a map'), isNull);
      expect(SourceHealth.parse({'ok': 'yes', 'at': '2026-01-01'}), isNull);
      expect(SourceHealth.parse({'ok': true, 'at': '不是时间'}), isNull);
      expect(SourceHealth.parse({'ok': true}), isNull);
    });

    test('label 给人话时间(刚刚 / 分钟 / 小时 / 天)', () {
      final now = DateTime(2026, 9, 24, 12);
      expect(
        SourceHealth(ok: true, at: now.subtract(const Duration(seconds: 20)))
            .label(now),
        '最近可用 · 刚刚',
      );
      expect(
        SourceHealth(ok: true, at: now.subtract(const Duration(minutes: 5)))
            .label(now),
        '最近可用 · 5 分钟前',
      );
      expect(
        SourceHealth(ok: false, at: now.subtract(const Duration(hours: 3)))
            .label(now),
        '上次失败 · 3 小时前',
      );
      expect(
        SourceHealth(ok: false, at: now.subtract(const Duration(days: 2)))
            .label(now),
        '上次失败 · 2 天前',
      );
    });

    test('失败原因截断:HTML 错误页那种长文本不进界面', () {
      final long = 'x' * 500;
      final short = MaterialSourceStatus.shorten(long);
      expect(short.length, lessThanOrEqualTo(121));
      expect(short.endsWith('…'), isTrue);
      expect(
        MaterialSourceStatus.shorten('  多个   空白\n换行  '),
        '多个 空白 换行',
      );
      // 短文案原样保留
      expect(MaterialSourceStatus.shorten('连接超时'), '连接超时');
    });
  });

  group('下次落在哪个源', () {
    final ids = [for (final s in MaterialSourceService.sources) s.id];

    test('没有任何记录 → 用默认源', () {
      expect(
        MaterialSourceStatus.preferredSourceId(
          knownIds: ids,
          fallback: MaterialSourceService.defaultSourceId,
          all: const {},
        ),
        'npr',
      );
    });

    test('只认"成功过"的源:失败记录再多也不选它', () {
      final all = {
        'bbc_le': SourceHealth(ok: false, at: DateTime(2026, 9, 24, 9)),
        'gutenberg': SourceHealth(ok: true, at: DateTime(2026, 9, 20)),
      };
      expect(
        MaterialSourceStatus.preferredSourceId(
          knownIds: ids,
          fallback: 'npr',
          all: all,
        ),
        'gutenberg',
      );
    });

    test('多个成功过 → 取最近成功的那个', () {
      final all = {
        'arxiv': SourceHealth(ok: true, at: DateTime(2026, 9, 22)),
        'gutenberg': SourceHealth(ok: true, at: DateTime(2026, 9, 24, 8)),
      };
      expect(
        MaterialSourceStatus.preferredSourceId(
          knownIds: ids,
          fallback: 'npr',
          all: all,
        ),
        'gutenberg',
      );
    });

    test('记录里的源已被删除(id 不在清单里)→ 退回默认源,不会选中一个不存在的源', () {
      final all = {
        'removed_source': SourceHealth(ok: true, at: DateTime(2026, 9, 24)),
      };
      expect(
        MaterialSourceStatus.preferredSourceId(
          knownIds: ids,
          fallback: 'npr',
          all: all,
        ),
        'npr',
      );
    });
  });

  group('诊断页整表(用户截图就能定性"材料中心为什么打不开")', () {
    final now = DateTime(2026, 9, 24, 12);
    final sources = MaterialSourceService.sources;

    test('每个源一行,带标记与结论', () {
      final lines = MaterialSourceStatus.summaryLines(
        sources: sources,
        state: {
          'npr': SourceHealth(ok: true, at: now.subtract(const Duration(minutes: 3))),
          'bbc_le': SourceHealth(
            ok: false,
            at: now.subtract(const Duration(hours: 2)),
            message: '网络中断:HandshakeException',
          ),
        },
        now: now,
      );
      final text = lines.join('\n');
      expect(lines.first, isEmpty, reason: '段落前留空行');
      expect(text, contains('── 材料源(最近一次可用性) ──'));
      expect(text, contains('✔ npr         最近可用 · 3 分钟前'));
      expect(text, contains('✖ bbc_le      上次失败 · 2 小时前 —— 网络中断:HandshakeException'));
      // 每个源都必须出现,不能只列试过的(否则用户不知道还有哪些可选)
      for (final s in sources) {
        expect(text.contains(' ${s.id} '), isTrue, reason: '缺了 ${s.id}');
      }
    });

    test('没试过的源也列出来,并区分"实测可达"与未知', () {
      final text = MaterialSourceStatus.summaryLines(
        sources: sources,
        state: const {},
        now: now,
      ).join('\n');
      expect(text, contains('— npr         还没试过(实测可达)'));
      expect(text, contains('— bbc_le      还没试过'));
      expect(text, isNot(contains('最近可用')));
    });
  });
}
