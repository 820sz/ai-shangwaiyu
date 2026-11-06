/// 输出板块 · **老题组来源/等级回填**(显式操作,不隐式迁移)。
///
/// 背景(用户 2026-11-06 反馈):
/// - 早于本次修复入库的真题,`exercise_sets.paper_year/paper_label` 是空的
///   (写入端以前把 paper_label 写成空串),题库里看不到年份/套数;
/// - `exam_type` 也有两类脏值:材料链路因中文标签映射 bug 落成 `none`,
///   真题链路把泛化「四六级」一律记成 `cet4`。
///
/// 处理原则:
/// 1. **只在用户点按钮时执行**(题库页「重建题源标签」),不在启动时静默改历史数据;
/// 2. **只按标题/来源说明里出现的明确写法重判**(四级/CET-4、六级/CET-6、考研…),
///    「四六级」这种区分不了的保持原值,不猜;
/// 3. **只写现有列**(`exam_type` / `paper_year` / `paper_label`),
///    不加列、不改 dbVersion;
/// 4. 幂等:已经是正确值的行不改写,重复点按钮结果一致。
library;

import 'output_paper.dart';
import 'database.dart';

/// 一次回填的结果(给 UI 显示"扫了多少、补了多少、还剩多少没法定级")。
class ExamBackfillReport {
  /// 扫过的题组数
  final int scanned;

  /// 实际改写的题组数
  final int updated;

  /// 本来就是正确值(没动)
  final int unchanged;

  /// 看不出等级且没有卷面信息的(保持原值)
  final int undetermined;

  /// 失败的条数(DB 写失败)
  final int failed;

  const ExamBackfillReport({
    this.scanned = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.undetermined = 0,
    this.failed = 0,
  });

  String get summary {
    if (scanned == 0) return '没有需要重建的题组';
    final parts = <String>['扫描 $scanned 组'];
    if (updated > 0) parts.add('已补 $updated 组');
    if (unchanged > 0) parts.add('本来就对 $unchanged 组');
    if (undetermined > 0) parts.add('$undetermined 组看不出等级（保持原样）');
    if (failed > 0) parts.add('$failed 组写入失败');
    return parts.join(' · ');
  }

  @override
  String toString() => 'ExamBackfillReport($summary)';
}

/// 扫描最近 [limit] 个题组,给缺等级 / 缺卷面身份的行补上。
///
/// 只做三件事(其余一律不动):
/// - `exam_type` 为空或 `none`、但标题/来源里能看出等级 → 补;
/// - `source == 'exam'` 且 `paper_year` 为空、标题/URL 里能抽到年份 → 补;
/// - 同上且 `paper_label` 为空、能抽到「年+月」或套数 → 补。
Future<ExamBackfillReport> backfillExerciseExamMeta({int limit = 200}) async {
  final rows = await DatabaseService.listExerciseSets(limit: limit);
  if (rows.isEmpty) return const ExamBackfillReport();

  var updated = 0;
  var unchanged = 0;
  var undetermined = 0;
  var failed = 0;

  for (final row in rows) {
    final id = (row['id'] as num?)?.toInt();
    if (id == null) continue;

    final title = '${row['title'] ?? ''}'.trim();
    final note = '${row['license_note'] ?? ''}'.trim();
    final source = '${row['source'] ?? ''}'.trim();
    final currentExamType = '${row['exam_type'] ?? 'none'}'.trim();
    final currentYear = (row['paper_year'] as num?)?.toInt();
    final currentLabel = '${row['paper_label'] ?? ''}'.trim();

    // ① 等级:只认标题/来源说明里的明确写法
    final inferred = inferExamTypeFromText(title: title, note: note);
    // ② 卷面身份:只对真题组做(材料组的"2023"不等于一份卷)
    PaperMeta paper = const PaperMeta();
    if (source == 'exam') {
      final url = _firstUrl(note);
      paper = parsePaperMeta(url: url, title: title);
    }

    final nextExamType = (currentExamType.isEmpty || currentExamType == 'none')
        ? (inferred ?? currentExamType)
        : inferred ?? currentExamType;
    final nextYear = currentYear ?? (source == 'exam' ? paper.year : null);
    final nextLabel = currentLabel.isNotEmpty
        ? currentLabel
        : (source == 'exam' ? paper.label : '');

    final examChanged = nextExamType != currentExamType;
    final yearChanged = nextYear != currentYear;
    final labelChanged = nextLabel != currentLabel;

    if (!examChanged && !yearChanged && !labelChanged) {
      if (inferred == null &&
          (currentExamType.isEmpty || currentExamType == 'none') &&
          (source == 'exam' ? paper.isEmpty : true)) {
        undetermined += 1;
      } else {
        unchanged += 1;
      }
      continue;
    }

    final ok = await DatabaseService.updateExerciseSetMeta(
      id,
      examType: examChanged ? nextExamType : null,
      paperYear: yearChanged ? nextYear : null,
      paperLabel: labelChanged ? nextLabel : null,
    );
    if (ok) {
      updated += 1;
    } else {
      failed += 1;
    }
  }

  return ExamBackfillReport(
    scanned: rows.length,
    updated: updated,
    unchanged: unchanged,
    undetermined: undetermined,
    failed: failed,
  );
}

/// 从来源说明里取第一个 URL(与 [siteOfLicenseNote] 同一正则,避免两套口径)
String _firstUrl(String note) {
  final text = note.trim();
  if (text.isEmpty) return '';
  final match = RegExp(r'https?://[^\s,，、;；)）]+').firstMatch(text);
  return match?.group(0)?.trim() ?? '';
}

/// 给 UI 用的提示:回填前告诉用户会做什么、不会做什么(不让人开盲盒)。
String get examBackfillHint =>
    '只按标题/来源里写明的「四级 / 六级 / 考研 / 雅思」重判，'
    '写不清的保持原样；重复执行结果一致。';
