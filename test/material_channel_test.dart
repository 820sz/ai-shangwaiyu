import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/material_channel.dart';
import 'package:readflow/services/material_taxonomy.dart';

/// 频道快照 / 保存关系存储的测试(方案 2 · 频道化的持久化层)。
///
/// 这层错法的特点都是"安静":
/// - 去重键写错 → "继续找更多"把同一篇堆两遍,界面看着像"结果变多";
/// - 脏快照没兜住 → 打开频道页白屏;
/// - 清空发现快照时顺手把"我的"关系清了 → 用户保存的材料莫名消失。
/// 所以测试重点锁这三类,以及 save/append/load/clear 的基本往返。
void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_material_channel_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    hiveDir.deleteSync(recursive: true);
  });

  /// 构造一条"UI 侧格式"的候选(camelCase 契约键)
  Map<String, Object?> cand(
    String url, {
    String title = '示例文章',
    String sourceLabel = 'NPR',
    String kind = 'news',
    String snippet = '摘要',
    String? imageUrl,
    int authority = 2,
    String? date,
    bool fromSearchApi = true,
  }) =>
      <String, Object?>{
        'title': title,
        'url': url,
        'sourceLabel': sourceLabel,
        'kind': kind,
        'snippet': snippet,
        'imageUrl': imageUrl,
        'authority': authority,
        'date': date,
        'fromSearchApi': fromSearchApi,
      };

  /// 保存关系的 key 是 store 内部布局,测试脏数据容错时要直接写 box
  String savedKeyOf(String channelId) =>
      '${MaterialChannelStore.boxKeyPrefix}$channelId@@saved';

  group('MaterialChannel 值对象', () {
    test('必填三项 + 其余默认值(UI 只传选中的子分类/需求即可)', () {
      const ch = MaterialChannel(
        id: 'topic:sci_tech',
        title: '按题材 · 科学与技术',
        direction: MaterialDirection.topic,
      );
      expect(ch.direction, MaterialDirection.topic);
      expect(ch.subtopicIds, isEmpty);
      expect(ch.queries, isEmpty);
      expect(ch.needText, isEmpty);
    });

    test('显式传入时原样保留(顺序即展示顺序)', () {
      const ch = MaterialChannel(
        id: 'scene:travel,daily',
        title: '按场景 · 出国旅游',
        direction: MaterialDirection.scene,
        subtopicIds: <String>['travel', 'daily'],
        queries: <String>['travel airport hotel', 'daily conversation'],
        needText: '想练出国旅游用的英语',
      );
      expect(ch.subtopicIds, <String>['travel', 'daily']);
      expect(ch.queries.last, 'daily conversation');
      expect(ch.needText, '想练出国旅游用的英语');
    });
  });

  group('normalizedUrlKey(去重键)', () {
    test('小写 + 去协议:http/https 混用的同一篇算一条', () {
      expect(
        normalizedUrlKey('https://www.npr.org/Story/1'),
        'www.npr.org/story/1',
      );
      expect(
        normalizedUrlKey('HTTP://WWW.NPR.ORG/story/1'),
        normalizedUrlKey('https://www.npr.org/Story/1'),
      );
    });

    test('去 utm_* 跟踪参数,真实参数保留', () {
      expect(
        normalizedUrlKey(
          'https://example.com/a?utm_source=x&id=7&UTM_Medium=y&utm_campaign=z',
        ),
        'example.com/a?id=7',
      );
      // 全是 utm 参数时连问号一起去掉
      expect(
        normalizedUrlKey('https://example.com/a?utm_source=x&utm_term=y'),
        'example.com/a',
      );
      expect(normalizedUrlKey('https://example.com/a?id=1&page=2'),
          'example.com/a?id=1&page=2');
    });

    test('去锚点(同一篇文章带 #section 不算两条)——契约之外的补强', () {
      expect(
        normalizedUrlKey('https://example.com/a#section-2'),
        'example.com/a',
      );
    });

    test('空串/空白归一为空(调用方据此判"没有 url")', () {
      expect(normalizedUrlKey(''), '');
      expect(normalizedUrlKey('   '), '');
    });
  });

  group('candidateJsonFromMap(入库前规整)', () {
    test('只留契约 9 个字段,正文/analysis 不存', () {
      final map = candidateJsonFromMap(<String, Object?>{
        ...cand(
          'https://example.com/a',
          date: '2026-11-01T08:00:00.000Z',
        ),
        'content': '很长的正文',
        'analysis': <String, Object?>{'cefr': 'B2'},
        'rerankScore': 1.5,
      });
      expect(map, isNotNull);
      expect(
        map!.keys.toSet(),
        <String>{
          'title',
          'url',
          'sourceLabel',
          'kind',
          'snippet',
          'imageUrl',
          'authority',
          'date',
          'fromSearchApi',
        },
      );
      expect(map.containsKey('content'), isFalse);
      expect(map['date'], '2026-11-01T08:00:00.000Z');
    });

    test('兼容 DiscoveredCandidate.toMap() 的 snake_case 键', () {
      // 真实来源:material_discovery.dart 的 DiscoveredCandidate.toMap()
      final map = candidateJsonFromMap(<String, Object?>{
        'title': 'The Science of Sleep',
        'url': 'https://example.com/sleep',
        'source': 'DeepSeek 搜索',
        'kind': 'article',
        'snippet': 'why we sleep',
        'image_url': 'https://example.com/cover.jpg',
        'authority': 3,
        'from_search_api': true,
      });
      expect(map, isNotNull);
      expect(map!['sourceLabel'], 'DeepSeek 搜索');
      expect(map['imageUrl'], 'https://example.com/cover.jpg');
      expect(map['fromSearchApi'], isTrue);
    });

    test('DateTime 日期 → ISO8601 字符串;坏日期 → null', () {
      final withDate = candidateJsonFromMap(<String, Object?>{
        ...cand('https://example.com/a'),
        'date': DateTime(2026, 11, 5, 12, 30),
      });
      expect(withDate!['date'], DateTime(2026, 11, 5, 12, 30).toIso8601String());

      final badDate = candidateJsonFromMap(<String, Object?>{
        ...cand('https://example.com/a'),
        'date': '不是时间',
      });
      expect(badDate!['date'], isNull);
    });

    test('缺省值:kind=article / authority=-1 / fromSearchApi=false / image=null', () {
      final map = candidateJsonFromMap(<String, Object?>{
        'url': 'https://example.com/a',
        'title': '  ',
      });
      expect(map!['title'], 'https://example.com/a', reason: '空标题回落 url');
      expect(map['kind'], 'article');
      expect(map['authority'], -1);
      expect(map['fromSearchApi'], isFalse);
      expect(map['imageUrl'], isNull);
      expect(map['snippet'], '');
    });

    test('没有 url 的条目返回 null(界面点不开,存了也没用)', () {
      expect(candidateJsonFromMap(<String, Object?>{'title': '无链接'}), isNull);
      expect(
        candidateJsonFromMap(<String, Object?>{'title': '空链接', 'url': '  '}),
        isNull,
      );
    });
  });

  group('candidateMapFromJson(读取容错)', () {
    test('JSON 字符串 / Map 两种形态都能还原', () {
      final fromMap = candidateMapFromJson(<String, Object?>{
        'title': 'T',
        'url': 'https://example.com/a',
      });
      final fromJson = candidateMapFromJson(
        '{"title":"T","url":"https://example.com/a","source_label":"来源"}',
      );
      expect(fromMap!['url'], 'https://example.com/a');
      expect(fromJson!['sourceLabel'], '来源');
      expect(fromJson['kind'], 'article');
    });

    test('脏数据一律 null,不抛', () {
      expect(candidateMapFromJson(null), isNull);
      expect(candidateMapFromJson(''), isNull);
      expect(candidateMapFromJson('不是 JSON'), isNull);
      expect(candidateMapFromJson(<Object?>[1, 2]), isNull);
      expect(candidateMapFromJson(42), isNull);
    });

    test('坏条目中的一个字段不代表整条无效:能救的字段照常解析', () {
      final map = candidateMapFromJson(<String, Object?>{
        'url': 'https://example.com/a',
        'authority': '3', // 历史上可能存成字符串
        'fromSearchApi': 'true',
      });
      expect(map!['authority'], 3);
      expect(map['fromSearchApi'], isTrue);
    });
  });

  group('channelSnapshotFromJson(快照解析)', () {
    test('完整表单往返', () {
      final snap = channelSnapshotFromJson(<String, Object?>{
        'items': <Object?>[
          cand('https://example.com/a', date: '2026-11-01T08:00:00.000Z'),
          '这条不是 map,应跳过',
          <String, Object?>{'title': '没链接的条目,应跳过'},
        ],
        'updated_at': '2026-11-05T12:00:00.000',
        'api_requests': 3,
        'cost_cny': 0.42,
        'queries_used': <Object?>['ai tools', '', null, 'ai tools', 'python'],
      });
      expect(snap, isNotNull);
      expect(snap!.items, hasLength(1), reason: '坏条目跳过而不是整份丢');
      expect(snap.items.single['url'], 'https://example.com/a');
      expect(snap.updatedAt, DateTime(2026, 11, 5, 12));
      expect(snap.apiRequests, 3);
      expect(snap.costCny, closeTo(0.42, 1e-9));
      expect(snap.queriesUsed, <String>['ai tools', 'python']);
      expect(snap.isEmpty, isFalse);
    });

    test('存成 JSON 字符串(真实 Hive 形态)也能解析', () {
      final snap = channelSnapshotFromJson(
        '{"items":[],"updated_at":"2026-11-05T12:00:00.000",'
        '"api_requests":"2","cost_cny":"0.5","queries_used":["a"]}',
      );
      expect(snap, isNotNull);
      expect(snap!.items, isEmpty);
      expect(snap.apiRequests, 2);
      expect(snap.costCny, closeTo(0.5, 1e-9));
    });

    test('没有有效 updated_at → null(快照无法排序/展示)', () {
      expect(
        channelSnapshotFromJson(<String, Object?>{'items': <Object?>[]}),
        isNull,
      );
      expect(
        channelSnapshotFromJson(
          <String, Object?>{'items': <Object?>[], 'updated_at': '不是时间'},
        ),
        isNull,
      );
    });

    test('脏数据/空串/非 map 一律 null,不抛', () {
      expect(channelSnapshotFromJson(null), isNull);
      expect(channelSnapshotFromJson(''), isNull);
      expect(channelSnapshotFromJson('不是 JSON'), isNull);
      expect(channelSnapshotFromJson(42), isNull);
      expect(channelSnapshotFromJson(<Object?>[1]), isNull);
    });

    test('items 不是列表 → 当空快照(不抛)', () {
      final snap = channelSnapshotFromJson(<String, Object?>{
        'items': '坏了',
        'updated_at': '2026-11-05T12:00:00.000',
      });
      expect(snap, isNotNull);
      expect(snap!.isEmpty, isTrue);
    });
  });

  group('saveRun / loadSnapshot', () {
    test('没存过的频道 → null', () async {
      expect(await MaterialChannelStore.loadSnapshot('topic:empty'), isNull);
    });

    test('save 后 load:字段、规范键、ISO 日期都在', () async {
      final before = DateTime.now();
      await MaterialChannelStore.saveRun(
        'topic:sci_tech',
        items: <Map<String, Object?>>[
          cand(
            'https://example.com/a?utm_source=x',
            title: '旧文章',
            date: '2026-11-01T08:00:00.000Z',
          ),
        ],
        apiRequests: 2,
        costCny: 0.12,
        queriesUsed: <String>['ai tools', 'ai tools', 'python'],
      );
      final snap = await MaterialChannelStore.loadSnapshot('topic:sci_tech');
      expect(snap, isNotNull);
      expect(snap!.items, hasLength(1));
      final item = snap.items.single;
      expect(item['title'], '旧文章');
      // 存的是原始 url(不去 utm)——归一化只用于去重键,不能改坏可打开的链接
      expect(item['url'], 'https://example.com/a?utm_source=x');
      expect(item['date'], '2026-11-01T08:00:00.000Z');
      expect(snap.updatedAt.isBefore(before), isFalse);
      expect(snap.apiRequests, 2);
      expect(snap.costCny, closeTo(0.12, 1e-9));
      expect(snap.queriesUsed, <String>['ai tools', 'python']);
    });

    test('存进的是带前缀的 Hive key(测试清理/诊断按前缀扫)', () async {
      await MaterialChannelStore.saveRun(
        'form:book',
        items: <Map<String, Object?>>[cand('https://example.com/b')],
        apiRequests: 0,
        costCny: 0,
        queriesUsed: const <String>[],
      );
      final box = Hive.box(AppConstants.hiveBoxSettings);
      expect(
        box.keys.map((k) => '$k'),
        contains('${MaterialChannelStore.boxKeyPrefix}form:book'),
      );
    });

    test('同一次 save 内按 URL 归一去重;无 url 条目丢弃', () async {
      await MaterialChannelStore.saveRun(
        'topic:dedupe',
        items: <Map<String, Object?>>[
          cand('https://example.com/a', title: '第一条'),
          cand('http://EXAMPLE.com/a?utm_source=x', title: '重复'),
          cand('https://example.com/b', title: 'B'),
          <String, Object?>{'title': '没有链接'},
        ],
        apiRequests: 0,
        costCny: 0,
        queriesUsed: const <String>[],
      );
      final snap = await MaterialChannelStore.loadSnapshot('topic:dedupe');
      expect(snap!.items.map((m) => m['title']), <String>['第一条', 'B']);
    });

    test('append=false 整体替换', () async {
      await MaterialChannelStore.saveRun(
        'topic:replace',
        items: <Map<String, Object?>>[
          cand('https://example.com/old', title: '旧'),
        ],
        apiRequests: 5,
        costCny: 0.5,
        queriesUsed: <String>['old'],
      );
      await MaterialChannelStore.saveRun(
        'topic:replace',
        items: <Map<String, Object?>>[
          cand('https://example.com/new', title: '新'),
        ],
        apiRequests: 1,
        costCny: 0.1,
        queriesUsed: <String>['new'],
      );
      final snap = await MaterialChannelStore.loadSnapshot('topic:replace');
      expect(snap!.items.single['title'], '新');
      expect(snap.apiRequests, 1);
      expect(snap.costCny, closeTo(0.1, 1e-9));
      expect(snap.queriesUsed, <String>['new']);
    });

    test('append=true:旧条目原序保留、新条目按 URL 归一追加、累计花费', () async {
      await MaterialChannelStore.saveRun(
        'topic:more',
        items: <Map<String, Object?>>[
          cand('https://example.com/a', title: 'A'),
          cand('https://example.com/b', title: 'B'),
        ],
        apiRequests: 2,
        costCny: 0.1,
        queriesUsed: <String>['ai tools'],
      );
      await MaterialChannelStore.saveRun(
        'topic:more',
        items: <Map<String, Object?>>[
          cand('https://example.com/c', title: 'C'),
          // 与旧 A 同一篇(http/大写/utm 不同),必须丢弃,且保留旧条目
          cand('http://EXAMPLE.com/a?utm_source=again', title: 'A 的重复'),
        ],
        apiRequests: 1,
        costCny: 0.05,
        queriesUsed: <String>['ai tools', 'python'],
        append: true,
      );
      final snap = await MaterialChannelStore.loadSnapshot('topic:more');
      expect(
        snap!.items.map((m) => m['title']),
        <String>['A', 'B', 'C'],
        reason: '追加不能把老结果顶乱,也不能重复堆同一篇',
      );
      expect(snap.apiRequests, 3, reason: '「继续找更多」要累计计费口径');
      expect(snap.costCny, closeTo(0.15, 1e-9));
      expect(snap.queriesUsed, <String>['ai tools', 'python']);
    });

    test('append=true 但没有旧快照 = 当首次存(不抛)', () async {
      await MaterialChannelStore.saveRun(
        'topic:no-old',
        items: <Map<String, Object?>>[cand('https://example.com/a')],
        apiRequests: 1,
        costCny: 0.01,
        queriesUsed: <String>['x'],
        append: true,
      );
      final snap = await MaterialChannelStore.loadSnapshot('topic:no-old');
      expect(snap!.items, hasLength(1));
      expect(snap.apiRequests, 1);
    });

    test('Hive 里是脏 JSON → load 返回 null,不抛', () async {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put('${MaterialChannelStore.boxKeyPrefix}topic:dirty', '不是 JSON');
      expect(
        await MaterialChannelStore.loadSnapshot('topic:dirty'),
        isNull,
      );
    });
  });

  group('clearSnapshot', () {
    test('只清发现快照,已保存的材料关系保留', () async {
      await MaterialChannelStore.saveRun(
        'topic:clear',
        items: <Map<String, Object?>>[cand('https://example.com/a')],
        apiRequests: 1,
        costCny: 0.01,
        queriesUsed: <String>['x'],
      );
      await MaterialChannelStore.addSavedMaterial('topic:clear', 7);
      await MaterialChannelStore.clearSnapshot('topic:clear');
      expect(await MaterialChannelStore.loadSnapshot('topic:clear'), isNull);
      expect(
        await MaterialChannelStore.savedMaterialIds('topic:clear'),
        <String>{'7'},
        reason: '用户清"这次发现结果"不该连"我的"一起丢',
      );
    });

    test('清没有的频道不抛', () async {
      await MaterialChannelStore.clearSnapshot('topic:none');
    });
  });

  group('savedMaterialIds / add / remove', () {
    test('空 → 空集合;返回 Set<String>(契约给 UI 用字符串判存)', () async {
      final ids = await MaterialChannelStore.savedMaterialIds('topic:s1');
      expect(ids, isEmpty);
      expect(ids, isA<Set<String>>());
    });

    test('add 幂等、remove 删除、可多次增删', () async {
      await MaterialChannelStore.addSavedMaterial('topic:s2', 12);
      await MaterialChannelStore.addSavedMaterial('topic:s2', 12);
      await MaterialChannelStore.addSavedMaterial('topic:s2', 3);
      var ids = await MaterialChannelStore.savedMaterialIds('topic:s2');
      expect(ids, <String>{'12', '3'});

      await MaterialChannelStore.removeSavedMaterial('topic:s2', 12);
      ids = await MaterialChannelStore.savedMaterialIds('topic:s2');
      expect(ids, <String>{'3'});

      // 删不存在的 id 无副作用
      await MaterialChannelStore.removeSavedMaterial('topic:s2', 99);
      expect(await MaterialChannelStore.savedMaterialIds('topic:s2'), <String>{'3'});
    });

    test('按频道隔离', () async {
      await MaterialChannelStore.addSavedMaterial('topic:iso1', 1);
      await MaterialChannelStore.addSavedMaterial('topic:iso2', 2);
      expect(
        await MaterialChannelStore.savedMaterialIds('topic:iso1'),
        <String>{'1'},
      );
      expect(
        await MaterialChannelStore.savedMaterialIds('topic:iso2'),
        <String>{'2'},
      );
    });

    test('Hive 里是脏数据/坏元素 → 容错(坏元素跳过,不抛)', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(savedKeyOf('topic:dirty1'), '不是 JSON');
      expect(
        await MaterialChannelStore.savedMaterialIds('topic:dirty1'),
        isEmpty,
      );

      await box.put(savedKeyOf('topic:dirty2'), '[1, "2", "坏", null, 3.0]');
      expect(
        await MaterialChannelStore.savedMaterialIds('topic:dirty2'),
        <String>{'1', '2', '3'},
      );

      // 坏数据不影响后续 add(读侧容错后照常重建)
      await MaterialChannelStore.addSavedMaterial('topic:dirty1', 9);
      expect(
        await MaterialChannelStore.savedMaterialIds('topic:dirty1'),
        <String>{'9'},
      );
    });
  });

  group('clearAllForTest', () {
    test('只清本 store 前缀的 key,不碰其它设置', () async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put('some_setting', '保留我');
      await MaterialChannelStore.saveRun(
        'topic:wipe1',
        items: <Map<String, Object?>>[cand('https://example.com/a')],
        apiRequests: 0,
        costCny: 0,
        queriesUsed: const <String>[],
      );
      await MaterialChannelStore.addSavedMaterial('topic:wipe1', 5);
      await MaterialChannelStore.addSavedMaterial('topic:wipe2', 6);

      await MaterialChannelStore.clearAllForTest();

      expect(await MaterialChannelStore.loadSnapshot('topic:wipe1'), isNull);
      expect(
        await MaterialChannelStore.savedMaterialIds('topic:wipe1'),
        isEmpty,
      );
      expect(
        await MaterialChannelStore.savedMaterialIds('topic:wipe2'),
        isEmpty,
      );
      expect(box.get('some_setting'), '保留我');
      expect(
        box.keys.map((k) => '$k').where(
              (k) => k.startsWith(MaterialChannelStore.boxKeyPrefix),
            ),
        isEmpty,
      );
    });
  });

  test('boxKeyPrefix 是契约值(备份/清理脚本按它扫 key)', () {
    expect(MaterialChannelStore.boxKeyPrefix, 'material_channel_');
  });
}
