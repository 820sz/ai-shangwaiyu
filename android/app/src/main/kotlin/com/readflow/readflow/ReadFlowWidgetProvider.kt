package com.readflow.readflow

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 桌面小组件「AI上外语 · 今天」(v2.2)。
 *
 * 分工:
 * - **文案的唯一来源是 Dart 侧**(`lib/services/widget_payload.dart`),它把标题/副行/
 *   页脚算好后通过 `HomeWidget.saveWidgetData` 写进 `HomeWidgetPreferences`(即这里的
 *   `widgetData`),本类只负责渲染 + 点击打开 App;
 * - 本类额外做一件事:**兜底新鲜度判断**。App 可能好几天没打开,而系统每 30 分钟
 *   会回调一次 `onUpdate` —— 如果同步时间不是今天,就把标题换成"打开 App 刷新
 *   今日任务",**绝不让三天前的"待复习 3 个"冒充今天**。
 *   这条规则与 `widget_payload.dart` 的 `build()` 是同一套语义,改一处要改两处
 *   (那边负责同步时刻的文案,这边负责"App 没运行时"的兜底)。
 */
class ReadFlowWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val syncedAt = parseIso(widgetData.getString(KEY_SYNCED_AT, null))
        val synced = syncedAt != null
        val fresh = synced && isToday(syncedAt)
        val headline = widgetData.getString(KEY_HEADLINE, null)
        val dueLine = widgetData.getString(KEY_DUE_LINE, null)
        val streak = widgetData.getString(KEY_STREAK, null)
        val badge = widgetData.getString(KEY_BADGE, null)

        val headlineText = when {
            headline.isNullOrBlank() -> context.getString(R.string.widget_empty_headline)
            !fresh -> context.getString(R.string.widget_stale_headline)
            else -> headline
        }
        val dueText = when {
            headline.isNullOrBlank() -> context.getString(R.string.widget_empty_due)
            !fresh -> context.getString(R.string.widget_stale_due, ageLabel(context, syncedAt))
            else -> dueLine ?: ""
        }
        val footerText = when {
            headline.isNullOrBlank() -> context.getString(R.string.widget_never_synced)
            !fresh -> context.getString(R.string.widget_stale_footer)
            else -> listOfNotNull(
                streak?.takeIf { it.isNotBlank() },
                context.getString(R.string.widget_updated_at, clock(syncedAt!!)),
            ).joinToString(" · ")
        }

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.readflow_widget).apply {
                // 点整块 → 打开 App(默认落在导师页:今天学什么)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
                setTextViewText(R.id.widget_headline, headlineText)
                setTextViewText(R.id.widget_due, dueText)
                setTextViewText(R.id.widget_footer, footerText)
                if (badge.isNullOrBlank()) {
                    setViewVisibility(R.id.widget_badge, View.GONE)
                } else {
                    setTextViewText(R.id.widget_badge, badge)
                    setViewVisibility(R.id.widget_badge, View.VISIBLE)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** ISO8601(本地时区无偏移,同 App 内所有时间列的约定);解析失败返回 null */
    private fun parseIso(raw: String?): Date? {
        if (raw.isNullOrBlank()) return null
        return try {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).parse(raw)
        } catch (e: Exception) {
            null
        }
    }

    private fun isToday(date: Date): Boolean {
        val now = Calendar.getInstance()
        val then = Calendar.getInstance().apply { time = date }
        return now.get(Calendar.YEAR) == then.get(Calendar.YEAR) &&
            now.get(Calendar.DAY_OF_YEAR) == then.get(Calendar.DAY_OF_YEAR)
    }

    private fun clock(date: Date): String =
        SimpleDateFormat("HH:mm", Locale.US).format(date)

    /** "昨天" / "3 天前":按自然日算,与 Dart 侧 `_ageLabel` 同口径 */
    private fun ageLabel(context: Context, date: Date?): String {
        if (date == null) return context.getString(R.string.widget_never_synced)
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val then = Calendar.getInstance().apply {
            time = date
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val days = ((today - then) / 86_400_000L).toInt()
        return when {
            days <= 0 -> context.getString(R.string.widget_age_today, clock(date))
            days == 1 -> context.getString(R.string.widget_age_yesterday, clock(date))
            else -> context.getString(R.string.widget_age_days, days)
        }
    }

    private companion object {
        const val KEY_HEADLINE = "rf_headline"
        const val KEY_DUE_LINE = "rf_due_line"
        const val KEY_STREAK = "rf_streak"
        const val KEY_BADGE = "rf_badge"
        const val KEY_SYNCED_AT = "rf_synced_at"
    }
}
