import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../config/design_tokens.dart';
import '../../services/about_content.dart';
import '../../services/external_link.dart';
import '../../widgets/brief_kit.dart';
import '../../widgets/v4/v4_kit.dart';

/// 「关于」三份文档的内容页:软件声明 / 软件特色 / 软件思想。
///
/// 排版走 B「每日简报」纸面语言（暖纸白 + 墨字 + 砖红/墨绿点缀），
/// 不用 flutter_markdown 的默认黑字白底 —— 那会和 App 其它页面像两个软件。
///
/// 外链（文末真实文献）用现成的 [launchExternalUrl] 打开系统浏览器；
/// 打不开时给 SnackBar 明说，不静默失败。
class AboutDocScreen extends StatefulWidget {
  const AboutDocScreen({
    super.key,
    required this.doc,
    this.overrideMarkdown,
  });

  final AboutDoc doc;

  /// **仅用于测试/渲染**:直接给 Markdown 文本，跳过 rootBundle
  /// （测试环境没打包 assets 时也能验证排版不崩）。
  final String? overrideMarkdown;

  @override
  State<AboutDocScreen> createState() => _AboutDocScreenState();
}

class _AboutDocScreenState extends State<AboutDocScreen> {
  String? _markdown;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final String text = widget.overrideMarkdown ??
        await AboutContent.markdown(widget.doc);
    if (!mounted) return;
    setState(() {
      _markdown = text;
      _loading = false;
    });
  }

  Future<void> _openLink(String? href) async {
    final String url = (href ?? '').trim();
    if (url.isEmpty) return;
    final bool ok = await launchExternalUrl(url);
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('打不开链接:$url')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Scaffold(
      backgroundColor: t.pageBg,
      appBar: V4JellyAppBar(title: widget.doc.title),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 180,
                    height: 14,
                    decoration: BoxDecoration(
                      color: t.line,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < 8; i++) ...<Widget>[
                    Container(
                      height: 10,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: t.line.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 40),
              children: <Widget>[
                // 顶部栏已经显示文档名（软件思想），这里不再放一个同名大标题；
                // 只保留眉标 + 分隔线，让 Markdown 自己的 H1（原文标题）当正文标题，
                // 避免「软件思想 / 软件思想 / 谈谈语言学习的本质」三层重复。
                BriefLabel(widget.doc.subtitle, color: t.accent),
                const SizedBox(height: 8),
                Container(height: 1, color: t.line),
                if (AboutContent.isMissing(widget.doc)) ...[
                  const SizedBox(height: 10),
                  Text(
                    '内容暂未就绪 —— 这份文档还没有随包发布,补齐后自动显示。',
                    style: AppFont.metaStyle.copyWith(
                      fontSize: 10.5,
                      height: 1.55,
                      color: t.warn,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SelectionArea(
                  child: MarkdownBody(
                    data: _markdown ?? '',
                    selectable: true,
                    onTapLink: (String text, String? href, String title) {
                      _openLink(href);
                    },
                    styleSheet: aboutMarkdownSheet(t),
                  ),
                ),
                const SizedBox(height: 26),
                Container(height: 1, color: t.line),
                const SizedBox(height: 10),
                Text(
                  '内容随安装包发布 · ${AboutContent.versionLabel} · 不联网读取',
                  style: AppFont.metaStyle.copyWith(
                    fontSize: 10,
                    color: t.inkFaint,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 关于页/公告页共用的 Markdown 样式（纸面语言）。
///
/// 单独抽出来是为了「声明/特色/思想」三页 + 以后公告里的段落排版只有一份口径：
/// 正文 14/1.85 墨字、标题按简报字阶、引用走墨绿竖线、代码/行内码走浅底、
/// 链接用墨绿 + 下划线（可点，点击交给外部浏览器）。
MarkdownStyleSheet aboutMarkdownSheet(BriefTheme t) {
  final TextStyle body = AppFont.bodyStyle.copyWith(
    fontSize: 14,
    height: 1.85,
    color: t.ink,
  );
  final TextStyle meta = AppFont.bodyStyle.copyWith(
    fontSize: 12.5,
    height: 1.7,
    color: t.inkSoft,
  );
  return MarkdownStyleSheet(
    p: body,
    h1: AppFont.displayStyle.copyWith(
      fontSize: 22,
      height: 1.3,
      letterSpacing: -0.4,
      fontWeight: FontWeight.w800,
      color: t.ink,
    ),
    h2: AppFont.headingStyle.copyWith(
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w800,
      color: t.ink,
    ),
    h3: AppFont.subheadStyle.copyWith(
      fontSize: 15.5,
      height: 1.4,
      fontWeight: FontWeight.w700,
      color: t.ink,
    ),
    h4: AppFont.subheadStyle.copyWith(fontSize: 14, color: t.ink),
    h5: AppFont.subheadStyle.copyWith(fontSize: 13.5, color: t.inkSoft),
    h6: AppFont.metaStyle.copyWith(fontSize: 12, color: t.inkSoft),
    em: TextStyle(
      fontStyle: FontStyle.italic,
      color: t.inkSoft,
      backgroundColor: Colors.transparent,
    ),
    strong: body.copyWith(fontWeight: FontWeight.w800),
    a: meta.copyWith(
      color: t.accent2,
      decoration: TextDecoration.underline,
      decorationColor: t.accent2,
    ),
    blockquote: meta.copyWith(fontSize: 13, height: 1.8),
    blockquoteDecoration: BoxDecoration(
      color: t.tint(t.accent2, alpha: 0.05),
      border: Border(left: BorderSide(color: t.accent2, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      color: t.ink,
      backgroundColor: t.surfaceAlt,
    ),
    codeblockDecoration: BoxDecoration(
      color: t.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    listBullet: body.copyWith(color: t.accent, fontSize: 14),
    listIndent: 22,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: t.line)),
    ),
  );
}
