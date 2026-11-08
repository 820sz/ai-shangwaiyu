import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../services/about_content.dart';
import '../../widgets/dash_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/v4/v4_kit.dart';
import 'about_doc_screen.dart';
import 'about_notice_screen.dart';

/// 「关于与更新」页。
///
/// v5.1(2026-11-07,用户第 8 条):在原有「数据与隐私 / 更新与诊断 / 关于软件」
/// 之上新增**关于三入口**(软件声明 / 软件特色 / 软件思想)、**开屏公告重看**
/// 与**开源许可**(软件声明里承诺过的入口 → `showLicensePage` 汇总依赖许可证)。
class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.onCheckUpdate,
    required this.onShowDiagnostics,
  });

  /// 复用「我的」页的检查更新逻辑(含"网络全断必须明说"的处理)
  final Future<void> Function() onCheckUpdate;

  /// 诊断信息弹层(API 配置摘要 + 崩溃日志)
  final Future<void> Function() onShowDiagnostics;

  Future<void> _openDoc(BuildContext context, AboutDoc doc) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AboutDocScreen(doc: doc)),
    );
  }

  void _openNotice(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AboutNoticeScreen(firstRun: false),
      ),
    );
  }

  void _openLicenses(BuildContext context) {
    // Flutter 自带:把 pubspec 所有依赖的 LICENSE 汇总成一页(无需自己维护列表)
    showLicensePage(
      context: context,
      applicationName: 'ReadFlow · 语流',
      applicationVersion: AboutContent.versionLabel,
      applicationLegalese: '个人非商业项目 · 作者 xi283',
      applicationIcon: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.auto_stories_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    return Scaffold(
      backgroundColor: d.skin.pageBg,
      appBar: const V4JellyAppBar(
        title: '关于与更新',
        domain: GraphicDomain.custom,
      ),
      body: ListView(
        padding: Insets.page,
        children: <Widget>[
          const SizedBox(height: Gap.xs),
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: d.skin.accentFill,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.auto_stories_outlined,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'ReadFlow · 语流',
                      style: AppFont.titleStyle.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: d.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AboutContent.versionLabel} · AI 外语学习:读进去,写出来',
                      style: AppFont.metaStyle.copyWith(
                        fontSize: 11,
                        color: d.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),

          // ── 01 关于软件(三入口 + 开屏公告)──
          const DashSectionTitle(index: '01', title: '关于软件', top: 0),
          DashCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              children: <Widget>[
                for (final AboutDoc doc in AboutDoc.values) ...<Widget>[
                  DashListRow(
                    title: doc.title,
                    subtitle: doc.subtitle,
                    leading: Icon(
                      switch (doc) {
                        AboutDoc.declaration => Icons.gavel_outlined,
                        AboutDoc.features => Icons.auto_awesome_outlined,
                        AboutDoc.philosophy => Icons.psychology_alt_outlined,
                      },
                      size: 20,
                      color: d.inkSoft,
                    ),
                    onTap: () => _openDoc(context, doc),
                  ),
                  Divider(height: 1, thickness: 0.8, color: d.line),
                ],
                DashListRow(
                  title: '开屏公告',
                  subtitle: '首次启动的三份说明',
                  leading: Icon(Icons.campaign_outlined, size: 20, color: d.inkSoft),
                  onTap: () => _openNotice(context),
                ),
              ],
            ),
          ),

          // ── 02 数据与隐私 ──
          const DashSectionTitle(index: '02', title: '数据与隐私'),
          DashCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _line(d, Icons.phone_iphone_rounded, '学习数据只存在这台手机上',
                    '生词、材料、统计都在本机,不上传。'),
                const SizedBox(height: Gap.sm),
                _line(d, Icons.cloud_off_outlined, '统计与周报都是本地计算',
                    '不联网,只有你用 AI 时才发请求。'),
                const SizedBox(height: Gap.sm),
                _line(d, Icons.key_outlined, 'API Key 只保存在本机设置里',
                    '诊断里只显示厂商与长度。'),
              ],
            ),
          ),

          // ── 03 更新与诊断 ──
          const DashSectionTitle(index: '03', title: '更新与诊断'),
          DashCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              children: <Widget>[
                DashListRow(
                  title: '检查更新',
                  subtitle: 'GitHub 最新 Release',
                  leading: Icon(Icons.system_update_alt, size: 20, color: d.inkSoft),
                  onTap: () async => onCheckUpdate(),
                ),
                Divider(height: 1, thickness: 0.8, color: d.line),
                DashListRow(
                  title: '诊断信息',
                  subtitle: '配置摘要(打码)+ 崩溃日志',
                  leading: Icon(Icons.medical_information, size: 20, color: d.inkSoft),
                  onTap: () async => onShowDiagnostics(),
                ),
                Divider(height: 1, thickness: 0.8, color: d.line),
                DashListRow(
                  title: '开源许可',
                  subtitle: '第三方开源库许可证',
                  leading: Icon(Icons.workspace_premium_outlined,
                      size: 20, color: d.inkSoft),
                  onTap: () => _openLicenses(context),
                ),
              ],
            ),
          ),

          // ── 04 关于这份软件 ──
          const DashSectionTitle(index: '04', title: '关于这份软件'),
          DashCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '输入 → 输出闭环:读真实材料、收词复习、写译批改。',
                  style: AppFont.bodyStyle.copyWith(
                    fontSize: 12.5,
                    height: 1.6,
                    color: d.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }

  Widget _line(DashTheme d, IconData icon, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: d.good),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: AppFont.bodyStyle.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: d.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: AppFont.metaStyle.copyWith(
                  fontSize: 11,
                  height: 1.6,
                  color: d.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
