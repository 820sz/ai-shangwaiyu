import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/learning_record.dart';
import 'database.dart';
import 'fsrs.dart';
import 'learner_snapshot_loader.dart';
import 'learner_model_store.dart';
import 'widget_payload.dart';

/// 桌面小组件的数据通道(v2.2)。
///
/// 分工:**文案规则在 [WidgetPayload]**(纯函数、可测),这里只做"取数 → 写数据 →
/// 通知原生刷新"三件事,以及一处**必须与复习页同口径**的计算 ——
/// 新词额度用 [FsrsScheduler.newWordQuota](与 `ReviewQueue.build` 同一个函数),
/// 连续天数用 [LearnerSnapshotLoader.streakDays](与导师页同一份实现)。
/// 否则桌面说"待复习 32 / 额度 10"、打开 App 说 25 / 6,两个数字打架比不显示更糟。
///
/// 原生侧只有一个 `ReadFlowWidgetProvider`,按 [WidgetPayload] 里的键读
/// SharedPreferences 渲染;视图在 `android/app/src/main/res/layout/readflow_widget.xml`。
class WidgetService {
  WidgetService._();

  /// 原生 provider 的完整类名(home_widget 用它定位要刷新的 AppWidget)
  static const String androidProvider =
      'com.readflow.readflow.ReadFlowWidgetProvider';

  /// 写数据失败不该影响 App 主流程(小组件只是"顺带",不是关键路径)
  static Future<bool> sync({DateTime? now}) async {
    final at = now ?? DateTime.now();
    try {
      final payload = await buildPayload(now: at);
      for (final entry in payload.toWidgetData().entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: androidProvider);
      return true;
    } catch (e) {
      // 非 Android / 原生 provider 没注册时会抛:记日志即可,不冒泡到 UI
      debugPrint('ReadFlow 小组件同步失败: $e');
      return false;
    }
  }

  /// 取数并组装文案(与 [sync] 分开:设置页要能"预览这次会写什么")
  static Future<WidgetPayload> buildPayload({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final firstSync = !await hasSyncedBefore();

    final due = await _safe(() => DatabaseService.getDueReviewCount(at: at), 0);
    final taskRows = await _safe(
      () => DatabaseService.getTutorTasks(at),
      const <Map<String, Object?>>[],
    );
    final addedToday = await _safe(
      () => DatabaseService.getVocabCountSince(DateTime(at.year, at.month, at.day)),
      0,
    );
    final logs = await _safe(
      () => DatabaseService.getDailyLogsInRange(
        at.subtract(const Duration(days: 60)),
        at,
      ),
      const <LearningRecord>[],
    );
    final model = _safeModel();

    // 与复习页同一口径:先按"今天要复习多少"占掉预算,剩下的才是新词额度,
    // 再扣掉今天已经加过的词
    final allowance = FsrsScheduler.newWordQuota(
      dueToday: due,
      dailyMinutes: model.dailyMinutes ?? 0,
      maxNewWords: model.maxNewWords ?? 20,
    );
    final remaining = allowance - addedToday;

    return WidgetPayload.build(
      dueCount: due,
      newWordsRemaining: remaining < 0 ? 0 : remaining,
      streakDays: LearnerSnapshotLoader.streakDays(logs, at),
      tasks: [
        for (final row in taskRows)
          WidgetTask(
            title: '${row['title'] ?? '今日任务'}',
            done: row['done_at'] != null,
          ),
      ],
      now: at,
      firstSync: firstSync,
    );
  }

  /// 是否曾经同步过(全新安装时小组件先说"打开 App",不编 0)
  static Future<bool> hasSyncedBefore() async {
    final raw = await _safe(
      () => HomeWidget.getWidgetData<String>(WidgetPayload.keySyncedAt),
      null,
    );
    return (raw ?? '').isNotEmpty;
  }

  /// 诊断页用:桌面小组件现在的状态(已添加几个 + 最后同步时间)。
  /// 这两个数字要能同时看到 —— "已添加但一直没同步"和"压根没添加"是两种
  /// 完全不同的故障,用户截图这一行就能定性。
  static Future<String> statusLine({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final count = await installedCount();
    final raw = await _safe(
      () => HomeWidget.getWidgetData<String>(WidgetPayload.keySyncedAt),
      null,
    );
    final syncedAt = DateTime.tryParse(raw ?? '');
    return '已添加 $count 个 · 最后同步 ${WidgetPayload.syncAgeLabel(syncedAt, at)}';
  }
  /// 已添加到桌面上的小组件数量(设置页显示状态;失败当 0)
  static Future<int> installedCount() async {
    try {
      final list = await HomeWidget.getInstalledWidgets();
      return list
          .where((w) => (w.androidClassName ?? '').contains('ReadFlowWidget'))
          .length;
    } catch (e) {
      debugPrint('ReadFlow 读取已添加小组件失败: $e');
      return 0;
    }
  }

  /// 请求系统把小组件钉到桌面(Android 8+ 且启动器支持时才有反应)
  static Future<bool> requestPin() async {
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported() ?? false;
      if (!supported) return false;
      await HomeWidget.requestPinWidget(qualifiedAndroidName: androidProvider);
      return true;
    } catch (e) {
      debugPrint('ReadFlow 请求添加小组件失败: $e');
      return false;
    }
  }

  static Future<T> _safe<T>(Future<T> Function() run, T fallback) async {
    try {
      return await run();
    } catch (e) {
      debugPrint('ReadFlow 小组件取数失败(已降级): $e');
      return fallback;
    }
  }

  /// 模型读失败就当"没设过配额":额度算 0 而不是编一个默认值 ——
  /// 小组件宁可说"今天不加新词",也不该凭空给用户一个数字
  static _ModelView _safeModel() {
    try {
      final m = LearnerModelStore.load();
      return _ModelView(
        dailyMinutes: m.dailyMinutes?.value,
        maxNewWords: m.maxNewWords?.value,
      );
    } catch (e) {
      debugPrint('ReadFlow 小组件读取模型失败(已降级): $e');
      return const _ModelView(dailyMinutes: null, maxNewWords: 0);
    }
  }
}

/// 只取小组件需要的两个字段(避免把整个模型类型拖进这个服务)
class _ModelView {
  final int? dailyMinutes;
  final int? maxNewWords;

  const _ModelView({this.dailyMinutes, this.maxNewWords});
}
