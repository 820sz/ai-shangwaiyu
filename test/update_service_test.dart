import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/services/update_service.dart';

void main() {
  group('compareVersions', () {
    test('21 > 20', () {
      expect(UpdateService.compareVersions('1.2.21', '1.2.20'), greaterThan(0));
    });

    test('带 v 前缀和 build 号', () {
      expect(UpdateService.compareVersions('v1.2.21', '1.2.20+30'), greaterThan(0));
      // v1.9.0(审查 P2-9):build 号必须参与比较 —— 旧实现把它丢掉,
      // 这条断言曾经把缺陷固化成"期望相等",导致"只升 build 号的修复版"
      // 用户永远收不到。
      expect(
        UpdateService.compareVersions('1.2.20+30', '1.2.20+29'),
        greaterThan(0),
      );
      expect(UpdateService.compareVersions('1.2.20+29', '1.2.20+30'), lessThan(0));
      expect(UpdateService.compareVersions('1.2.20+30', '1.2.20+30'), 0);
      // 主版本更高时 build 号不影响结论
      expect(UpdateService.compareVersions('1.9.0+1', '1.8.0+99'), greaterThan(0));
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

  // v3(2026-11-01 用户):更新说明必须是"1、2、3"的清单,
  // 不是把 markdown 汇报文原样丢给用户看。
  group('parseReleaseNotesForDisplay — 更新说明归一成编号清单', () {
    test('新格式:只取「更新内容」小节、去掉编号与 markdown', () {
      const body = '''
# ReadFlow v2.14.0

> 本版按用户 11/01 的清单落地。

## 更新内容

1. **识图追问抽屉**现在会记住你上次看到的位置。
2. 移动词汇时不再重复新建分类。
3. 更新说明改成能看到懂的编号清单。

## 技术细节

- 迁移到 dbVersion 19。
- flutter analyze 0 error。
''';
      final notes = UpdateService.parseReleaseNotesForDisplay(body);
      expect(notes.length, 3);
      expect(notes[0], '识图追问抽屉现在会记住你上次看到的位置');
      expect(notes[1], '移动词汇时不再重复新建分类');
      expect(notes[2], '更新说明改成能看到懂的编号清单');
      // 「技术细节」小节不进用户弹窗
      expect(notes.join('\n'), isNot(contains('dbVersion')));
      expect(notes.join('\n'), isNot(contains('flutter analyze')));
    });

    test('老格式(无「更新内容」小节):收集顶层列表项,跳过验证小节', () {
      const body = '''
# ReadFlow v2.13.0

## 一、鲸鱼尾

- 素材就是你给的那张图,做成了透明底 + 可染主题色。
- 尾巴会轻摆 + 轻微上浮,像在划水。

## 二、识图

1. 横置图现在会自动转正再送模型。
2. 下划线批注加了专项提示词。

## 验证

- `flutter analyze`:0 error / 0 warning
- 相关测试:247 通过
''';
      final notes = UpdateService.parseReleaseNotesForDisplay(body);
      expect(notes.length, 4);
      expect(notes.first, contains('素材就是你给的那张图'));
      expect(notes.join('\n'), contains('横置图现在会自动转正再送模型'));
      expect(notes.join('\n'), isNot(contains('flutter analyze')));
      expect(notes.join('\n'), isNot(contains('247 通过')));
    });

    test('markdown 粗体/反引号/链接被清理成纯文本', () {
      const body = '''
## 更新内容
1. **闪退**修好了(见 [issue](https://example.com/a))。
2. 新增 `深色模式` 开关。
''';
      final notes = UpdateService.parseReleaseNotesForDisplay(body);
      expect(notes.length, 2);
      expect(notes[0], '闪退修好了(见 issue)');
      expect(notes[1], '新增 深色模式 开关');
    });

    test('空正文返回空清单', () {
      expect(UpdateService.parseReleaseNotesForDisplay(''), isEmpty);
      expect(UpdateService.parseReleaseNotesForDisplay('   \n\n'), isEmpty);
    });

    test('maxItems 上限生效', () {
      final body = StringBuffer('## 更新内容\n');
      for (var i = 1; i <= 12; i++) {
        body.writeln('$i. 第 $i 条更新');
      }
      final notes = UpdateService.parseReleaseNotesForDisplay(
        body.toString(),
        maxItems: 5,
      );
      expect(notes.length, 5);
      expect(notes.first, '第 1 条更新');
    });

    test('没有列表项时兜底取第一段正文的前两句', () {
      const body = '这一版修复了几个问题。也顺手优化了排版。剩下的下次再说。';
      final notes = UpdateService.parseReleaseNotesForDisplay(body);
      expect(notes, isNotEmpty);
      expect(notes.first, '这一版修复了几个问题');
    });
  });

  group('isAutoCheckDue — 自动检查每天最多一次', () {
    final now = DateTime(2026, 11, 1, 12);

    test('没查过 → 该查', () {
      expect(UpdateService.isAutoCheckDue(null, now), isTrue);
    });

    test('12 小时前查过 → 不用查', () {
      final last = now.subtract(const Duration(hours: 12)).millisecondsSinceEpoch;
      expect(UpdateService.isAutoCheckDue(last, now), isFalse);
    });

    test('25 小时前查过 → 该查', () {
      final last = now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch;
      expect(UpdateService.isAutoCheckDue(last, now), isTrue);
    });

    test('时钟回拨(时间戳在未来)→ 该查,不吞', () {
      final future = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
      expect(UpdateService.isAutoCheckDue(future, now), isTrue);
    });
  });
}
