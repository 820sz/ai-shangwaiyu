import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../services/about_content.dart';
import '../../widgets/brief_kit.dart';
import 'about_doc_screen.dart';

/// 首次启动的开屏公告（B「每日简报」语言）。
///
/// 三层目的，按优先级：
/// 1. **一次讲清"这软件是什么、怎么想、承诺什么"** —— 声明/特色/思想三块，
///    每块一句话 + 可展开看全文（用户第 8 条要求"三者作为开屏公告"）；
/// 2. **只出现一次**：点「我已阅读并继续」写 Hive 标记（[AboutNotice.markSeen]），
///    以后启动不再打扰；想重看走「我的 → 关于」；
/// 3. **不喧宾夺主**：纸面语言 + 一个主按钮，不做全屏渐变海报、不放动画。
class AboutNoticeScreen extends StatelessWidget {
  const AboutNoticeScreen({super.key, this.firstRun = true, this.summaryOverrides});

  /// true = 首次启动（按钮为「我已阅读并继续」）；
  /// false = 从关于页重看（按钮为「关闭」）。两种都 pop(true)，是否写标记由调用方决定。
  final bool firstRun;

  /// **仅用于逐屏渲染/测试**:直接给三块摘要，跳过 rootBundle 读取
  /// （渲染 harness 里 rootBundle 的异步完成时机不稳定，会让截图等到骨架态）。
  final Map<AboutDoc, String>? summaryOverrides;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Scaffold(
      backgroundColor: t.pageBg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.tint(t.accent, alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.auto_stories_outlined,
                          size: 22,
                          color: t.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            BriefLabel(
                              firstRun ? 'WELCOME · 首次使用' : 'ABOUT · 开屏公告',
                              color: t.accent,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'ReadFlow · 语流',
                              style: AppFont.bodyStyle.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: t.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: t.surfaceAlt,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          AboutContent.versionLabel,
                          style: AppFont.tagStyle.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: t.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    firstRun ? '花一分钟，认识这个软件' : '这个软件是什么、怎么想',
                    style: AppFont.displayStyle.copyWith(
                      fontSize: 26,
                      height: 1.25,
                      letterSpacing: -0.6,
                      fontWeight: FontWeight.w800,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ReadFlow 是一个"输入 → 输出"闭环的英语学习工具：读真实材料、'
                    '收词复习、做写译批改，再用学习助理把数据变成下一步动作。'
                    '下面三份说明，是这个软件的承诺、做法与想法。',
                    style: AppFont.bodyStyle.copyWith(
                      fontSize: 13.5,
                      height: 1.75,
                      color: t.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final AboutDoc doc in AboutDoc.values) ...<Widget>[
                    _DocCard(
                      doc: doc,
                      summaryOverride: summaryOverrides?[doc],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '点「我已阅读并继续」后，这份公告不再自动弹出；'
                    '随时可在「我的 → 关于与更新」里重看。',
                    style: AppFont.metaStyle.copyWith(
                      fontSize: 10.5,
                      height: 1.6,
                      color: t.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            // 底部主行动（不悬浮、不遮挡内容）
            Container(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
              decoration: BoxDecoration(
                color: t.pageBg,
                border: Border(top: BorderSide(color: t.line)),
              ),
              child: BriefPrimaryButton(
                label: firstRun ? '我已阅读并继续' : '关闭',
                icon: firstRun ? Icons.check_rounded : null,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 公告里的一份文档卡:标题 + 一句话摘要（异步从正文取第一段，不手写摘要）
class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, this.summaryOverride});

  final AboutDoc doc;
  final String? summaryOverride;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return BriefCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  doc.title,
                  style: AppFont.subheadStyle.copyWith(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: t.ink,
                  ),
                ),
              ),
              Text(
                doc.noticeLabel,
                style: AppFont.tagStyle.copyWith(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: t.accent2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (summaryOverride != null)
            Text(
              summaryOverride!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppFont.bodyStyle.copyWith(
                fontSize: 12,
                height: 1.7,
                color: t.inkSoft,
              ),
            )
          else
            FutureBuilder<String>(
              future: AboutContent.summaryOf(doc),
              builder: (BuildContext context, AsyncSnapshot<String> snap) {
                final String text = snap.data ??
                    (snap.hasError
                        ? doc.subtitle
                        : '…');
                return Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.bodyStyle.copyWith(
                    fontSize: 12,
                    height: 1.7,
                    color: t.inkSoft,
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AboutDocScreen(doc: doc),
                ),
              ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '查看全文',
                      style: AppFont.metaStyle.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: t.accent2,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: t.accent2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
