import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learner_model.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/export_service.dart';
import 'package:readflow/services/fsrs.dart';

/// 导出与备份的回归测试。
///
/// 这类代码出错的方式很具体:CSV 少转义一个引号 → Excel 里整表错列;
/// 备份漏写复习状态 → 用户换机后几百个词的复习进度归零。
/// 所以断言压在**格式细节**与**往返一致性**上。
void main() {
  Vocabulary v(
    int id,
    String word, {
    String? translation,
    int mastery = 0,
    String? book,
    String? category,
    String? phoneticUk,
    String? phoneticUs,
    String type = 'word',
  }) =>
      Vocabulary(
        id: id,
        word: word,
        translation: translation,
        masteryLevel: mastery,
        sourceBook: book,
        category: category,
        phoneticUk: phoneticUk,
        phoneticUs: phoneticUs,
        wordType: type,
        createdAt: DateTime(2026, 9, 20, 10, 30),
      );

  FsrsCard card({int dueInDays = 3, double stability = 12.5, int reps = 2, int lapses = 1}) =>
      FsrsCard(
        stability: stability,
        difficulty: 5.5,
        due: DateTime.now().add(Duration(days: dueInDays)),
        lastReview: DateTime.now().subtract(const Duration(days: 1)),
        reps: reps,
        lapses: lapses,
        lastRating: FsrsRating.good,
      );

  group('生词本 CSV', () {
    test('表头齐全,行数与词数一致,带 BOM 便于 Excel 显示中文', () {
      final csv = ExportService.vocabCsv([
        v(1, 'alpha', translation: '第一个'),
        v(2, 'beta', translation: '第二个'),
      ]);
      expect(csv.startsWith(ExportService.utf8Bom), isTrue);
      final lines = csv.substring(1).trim().split('\n');
      expect(lines.length, 3, reason: '表头 + 2 行');
      expect(lines.first, contains('单词'));
      expect(lines.first, contains('英式音标'));
      expect(lines[1], contains('alpha'));
      expect(lines[1], contains('第一个'));
    });

    test('含逗号/引号/换行的释义被正确转义(否则 Excel 整表错列)', () {
      final csv = ExportService.vocabCsv(
        [v(1, 'tricky', translation: 'a, b "quoted" and\nnewline')],
        withBom: false,
      );
      final line = csv.split('\n').skip(1).join('\n');
      expect(line, contains('"a, b ""quoted"" and\nnewline"'));
    });

    test('带复习状态列:过期/今天/未来三种说法', () {
      final csv = ExportService.vocabCsv(
        [
          v(1, 'overdue'),
          v(2, 'today'),
          v(3, 'later'),
          v(4, 'never'),
        ],
        cards: {
          1: card(dueInDays: -3),
          2: card(dueInDays: 0),
          3: card(dueInDays: 5),
        },
        withBom: false,
      );
      expect(csv, contains('已过期 3 天'));
      expect(csv, contains('今天到期'));
      expect(csv, contains('5 天后到期'));
      expect(csv, contains('未复习'));
    });

    test('双音标分别导出(缺失时回退到单音标)', () {
      final csv = ExportService.vocabCsv(
        [
          v(1, 'both', phoneticUk: 'ʃedjuːl', phoneticUs: 'skedʒuːl'),
          v(2, 'onlyuk', phoneticUk: 'wɔːtə'),
          v(3, 'legacy'),
        ],
        withBom: false,
      );
      expect(csv, contains('ʃedjuːl'));
      expect(csv, contains('skedʒuːl'));
      expect(csv, contains('wɔːtə'));
    });

    test('空词库只输出表头,不抛异常', () {
      final csv = ExportService.vocabCsv(const [], withBom: false);
      expect(csv.trim().split('\n').length, 1);
    });
  });

  group('Anki TSV', () {
    test('三列:正面 \\t 背面 \\t 标签;换行换成 <br>', () {
      final tsv = ExportService.vocabAnkiTsv([
        v(
          1,
          'vocabulary',
          translation: '词汇\n词汇量',
          category: '雅思',
          mastery: 2,
        ),
      ]);
      final cols = tsv.trim().split('\t');
      expect(cols.length, 3);
      expect(cols[0], 'vocabulary');
      expect(cols[1], contains('词汇<br>词汇量'), reason: '不能出现裸换行,否则 Anki 会拆行');
      expect(cols[1], isNot(contains('\n')));
      expect(cols[2], contains('readflow'));
      expect(cols[2], contains('已掌握'));
      expect(cols[2], contains('雅思'));
    });

    test('多词多条,一行一条', () {
      final tsv = ExportService.vocabAnkiTsv([
        v(1, 'a'),
        v(2, 'b'),
        v(3, 'c'),
      ]);
      expect(tsv.trim().split('\n').length, 3);
    });
  });

  group('完整备份 JSON', () {
    String makeBackup() => ExportService.backupJson(
          vocab: [
            v(1, 'alpha', translation: '第一个', phoneticUk: 'x', mastery: 1),
            v(2, 'beta', translation: '第二个', mastery: 2),
          ],
          cards: {1: card(dueInDays: 2), 2: card(dueInDays: -1, stability: 30)},
          model: LearnerModel(
            dailyMinutes: ProfileField<int>(value: 40, source: ProfileSource.self),
            maxNewWords: ProfileField<int>(value: 10, source: ProfileSource.self),
          ),
          settings: const {'tts_accent': 'uk'},
          now: DateTime(2026, 9, 23, 12),
        );

    test('包含版本号、时间、计数与设置白名单,且不含 API Key', () {
      final json = makeBackup();
      expect(json, contains('"version": 1'));
      expect(json, contains('"app": "readflow"'));
      expect(json, contains('2026-09-23T12:00:00.000'));
      expect(json, contains('tts_accent'));
      expect(json.toLowerCase(), isNot(contains('api_key')));
      expect(json.toLowerCase(), isNot(contains('sk-')));
    });

    test('往返一致:词条、双音标、复习状态、画像都能读回', () {
      final data = ExportService.parseBackup(makeBackup());
      expect(data.ok, isTrue);
      expect(data.vocab.length, 2);
      expect(data.cardsByWord.length, 2);
      expect(data.vocab.first.phoneticUk, 'x');
      expect(data.model!.dailyMinutes!.value, 40);
      expect(data.model!.maxNewWords!.value, 10);
      expect(data.settings['tts_accent'], 'uk');

      final alpha = data.cardsByWord['alpha']!;
      expect(alpha.stability, closeTo(12.5, 1e-9));
      expect(alpha.reps, 2);
      expect(alpha.lapses, 1);
      expect(alpha.lastRating, FsrsRating.good);
      final beta = data.cardsByWord['beta']!;
      expect(beta.stability, closeTo(30, 1e-9));
      expect(beta.due.isBefore(DateTime.now()), isTrue, reason: '过期的状态要保留');
    });

    test('坏输入给可诊断错误,绝不抛异常', () {
      expect(ExportService.parseBackup('').error, isNotNull);
      expect(ExportService.parseBackup('not json').error, contains('JSON'));
      expect(ExportService.parseBackup('[1,2,3]').error, contains('对象'));
      expect(
        ExportService.parseBackup('{"app":"other","version":1}').error,
        contains('本 App'),
      );
      expect(
        ExportService.parseBackup('{"app":"readflow","version":99}').error,
        contains('更新版本'),
      );
    });

    test('缺字段/坏行被跳过,好行照常导入(不能一条坏数据毁一份备份)', () {
      final raw = jsonEncode({
        'app': 'readflow',
        'version': 1,
        'vocab': [
          {'word': 'good', 'translation': '好的'},
          {'translation': '没有单词字段'},
          'not-a-map',
          {'word': '  ', 'translation': '空白词'},
        ],
      });
      final data = ExportService.parseBackup(raw);
      expect(data.ok, isTrue);
      expect(data.vocab.length, 1);
      expect(data.vocab.first.word, 'good');
    });

    test('summaryLine 给人话概览(导入前让用户确认)', () {
      final data = ExportService.parseBackup(makeBackup());
      expect(data.summaryLine, contains('2 个词'));
      expect(data.summaryLine, contains('2 条复习状态'));
      expect(data.summaryLine, contains('学习画像'));
      expect(data.summaryLine, contains('设置'));
    });
  });
}
