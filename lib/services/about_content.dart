import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 「关于」三份文档:软件声明 / 软件特色 / 软件思想。
///
/// 内容由内容作者（Lead）写在 `assets/about/*.md`，本文件**只读引用、不改内容**。
/// 为什么要单独一层：
/// 1. 内容页与首启公告都要读同一份，避免两处各拼一遍；
/// 2. Markdown 走 rootBundle，读不到时**必须降级成占位而不是崩**（内容可能在别的
///    流水线里还没落地）；
/// 3. 公告页需要"摘要"，从正文里取第一段人话，而不是在 Dart 里再手写一份摘要
///    （否则内容和摘要会漂移）。
enum AboutDoc {
  declaration(
    '软件声明',
    '版权 · 免责 · 使用范围',
    'assets/about/software_declaration.md',
    '版权、免责与使用范围',
  ),
  features(
    '软件特色',
    '闭环架构 · 多维度 · 高个性化 · AI 驱动',
    'assets/about/software_features.md',
    '这个软件是怎么搭起来的',
  ),
  philosophy(
    '软件思想',
    '谈谈语言学习的本质',
    'assets/about/software_philosophy.md',
    '为什么这样设计学习',
  );

  const AboutDoc(this.title, this.subtitle, this.assetPath, this.noticeLabel);

  final String title;
  final String subtitle;
  final String assetPath;

  /// 首启公告里的一句话定位
  final String noticeLabel;
}

class AboutContent {
  AboutContent._();

  /// 版本号:发版时与 `pubspec.yaml` 的 versionName 同步（项目里没有运行时
  /// 读取版本的依赖，也没有现成常量；这里集中一处，便于发版时改一行）。
  static const String versionLabel = 'v2.28.0';

  static final Map<AboutDoc, String> _cache = <AboutDoc, String>{};
  static final Set<AboutDoc> _missing = <AboutDoc>{};

  /// 读一份文档的 Markdown 原文。**永不抛**：读不到给占位说明。
  static Future<String> markdown(AboutDoc doc) async {
    final String? cached = _cache[doc];
    if (cached != null) return cached;
    String text = '';
    try {
      text = await rootBundle.loadString(doc.assetPath);
    } catch (_) {
      text = '';
    }
    final bool ok = text.trim().isNotEmpty;
    if (!ok) {
      _missing.add(doc);
      text = _placeholder(doc);
    }
    _cache[doc] = text;
    return text;
  }

  /// 这份文档是不是"内容还没就绪"的占位（页面据此显示一行提示）
  static bool isMissing(AboutDoc doc) => _missing.contains(doc);

  /// 公告页用的一句话摘要:取**第一段真正的纯文本**（跳过标题/引用/列表符号/
  /// Markdown 表格 —— 声明里开头可能就是一张表格，旧实现会把
  /// `| 项目 | 内容 | --- |` 原样塞进公告卡，QA 判为首屏 bug）。
  static Future<String> summaryOf(AboutDoc doc) async {
    final String md = await markdown(doc);
    final List<String> lines = md.split('\n');
    final StringBuffer out = StringBuffer();
    for (final String raw in lines) {
      final String line = raw.trim();
      if (line.isEmpty) continue;
      // 标题 / 引用 / 分隔线 / HTML 注释 / 代码围栏 / 图片 —— 都不是"正文第一段"
      if (line.startsWith('#') ||
          line.startsWith('>') ||
          line.startsWith('---') ||
          line.startsWith('<!--') ||
          line.startsWith('```') ||
          line.startsWith('![')) {
        continue;
      }
      // Markdown 表格：整行跳过（含 | 的行、以及 --- | --- 这种分隔行）
      if (line.contains('|')) continue;
      if (RegExp(r'^[\s\-:_]+$').hasMatch(line)) continue;
      final String plain = _plain(line);
      if (plain.length < 8) continue;
      // 摘要里不允许残留 Markdown 控制符（星号/井号/反引号/中括号括号对）
      if (plain.contains('**') || plain.contains('`') || plain.contains('](')) {
        continue;
      }
      out.write(plain);
      if (out.length >= 54) break;
    }
    final String s = out.toString().trim();
    if (s.isEmpty) return doc.noticeLabel;
    return s.length <= 54 ? s : '${s.substring(0, 54)}…';
  }

  /// 列表项/强调/链接符号洗掉，只留人话（公告摘要用）
  static String _plain(String line) {
    String s = line;
    s = s.replaceAll(RegExp(r'^[-*+]\s+'), '');
    s = s.replaceAll(RegExp(r'^\d+[.)]\s+'), '');
    s = s.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
    s = s.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
    s = s.replaceAll('|', '');
    s = s.replaceAll(RegExp(r'\[([^\]]*)\]'), r'$1');
    return s.trim();
  }

  static String _placeholder(AboutDoc doc) {
    return '# ${doc.title}\n\n'
        '> 内容暂未就绪\n\n'
        '这份文档对应的文件还没有随包发布：`${doc.assetPath}`。\n\n'
        '它不会影响软件使用 —— 内容由内容作者补齐后，这一页会自动显示正文。\n';
  }

  @visibleForTesting
  static void resetCache() {
    _cache.clear();
    _missing.clear();
  }
}
