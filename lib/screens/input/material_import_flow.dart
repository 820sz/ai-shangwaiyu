import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/doubao_api.dart';
import '../../services/file_pick.dart';
import '../../services/material_import.dart';
import '../../services/material_library.dart';
import '../../services/material_source.dart';
import '../../widgets/app_ui.dart';

/// 材料导入的通道。
enum ImportChannel {
  /// 粘贴文本(自备材料)
  paste('粘贴文本', Icons.content_paste_go, '直接贴英文正文,最快'),

  /// 文件(txt/md/srt/csv/json/html)
  file('从文件导入', Icons.description_outlined,
      'txt / md / srt / csv / json / html;PDF、EPUB、DOCX 暂不支持'),

  /// 图片(拍照或相册 → AI 提取全文)
  image('从图片提取', Icons.image_outlined, '拍照或选图 → AI 提取全文 → 可校对后入库'),

  /// 外部链接(网页正文)
  link('从链接导入', Icons.link, '论文页 / 期刊 / 新闻 / 博客 —— 抓正文在软件内读');

  const ImportChannel(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}

/// 材料导入的执行流(v2.7,用户第 2(4) 条 + 第 3 条)。
///
/// 为什么把"选通道 + 抓取 + 校对 + 入库"放在一个共享类里:
/// 「材料中心」与「上传分析材料」两个入口都要这三条通道,而且用户明确要求
/// "不要每次加一个功能就出现前后端一堆新问题" —— 一份实现,两处调用。
///
/// 每条通道最终都产出同一个 [MaterialDoc],于是入库/难度分析/阅读器/
/// 我的学习材料全程复用既有管线。
class MaterialImportFlow {
  MaterialImportFlow._();

  /// 单个文件大小上限:纯文本超 8MB 基本不是"学习材料"(而且解析会卡主线程)
  static const int maxFileBytes = 8 * 1024 * 1024;

  /// 弹「导入材料」选择器(单通道模式时直接用该通道,不弹)
  static Future<ImportChannel?> pickChannel(
    BuildContext context, {
    List<ImportChannel> channels = ImportChannel.values,
    String title = '导入材料',
  }) {
    if (channels.length == 1) return Future.value(channels.first);
    return showModalBottomSheet<ImportChannel>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
                child: Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              for (final c in channels)
                ListTile(
                  leading: Icon(c.icon, color: theme.colorScheme.primary),
                  title: Text(c.label),
                  subtitle: Text(c.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                  onTap: () => Navigator.pop(ctx, c),
                ),
              const SizedBox(height: Gap.xs),
            ],
          ),
        );
      },
    );
  }

  /// 跑一条通道 → 入库 → 返回结果(null = 用户取消或失败已提示)
  ///
  /// [initialUrl] 非空时直接进"链接导入"的确认框(第 3 条:外部链接导入入口)。
  static Future<IngestedMaterial?> run(
    BuildContext context, {
    required LearnerModel model,
    ImportChannel? channel,
    String? initialUrl,
    ImportChannel? only,
    String dialogTitle = '导入材料',
  }) async {
    final chosen = channel ??
        (initialUrl != null && initialUrl.trim().isNotEmpty
            ? ImportChannel.link
            : await pickChannel(
                context,
                channels: only == null ? ImportChannel.values : [only],
                title: dialogTitle,
              ));
    if (chosen == null || !context.mounted) return null;
    switch (chosen) {
      case ImportChannel.paste:
        return _pasteText(context, model);
      case ImportChannel.file:
        return _fromFile(context, model);
      case ImportChannel.image:
        return _fromImage(context, model);
      case ImportChannel.link:
        return _fromLink(context, model, initialUrl: initialUrl);
    }
  }

  /// 入库(所有通道的最后一步)+ 返回结果
  static Future<IngestedMaterial> ingest(
    BuildContext context,
    MaterialDoc doc, {
    required LearnerModel model,
  }) async {
    final vocab = context.read<VocabProvider>().vocabularies;
    return MaterialLibrary.ingestDoc(doc, model: model, vocab: vocab);
  }

  // ───────────────────────── ① 粘贴文本 ─────────────────────────

  static Future<IngestedMaterial?> _pasteText(
    BuildContext context,
    LearnerModel model,
  ) async {
    final titleCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴材料'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: Gap.xs),
              TextField(
                controller: textCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '英文正文',
                  hintText: '论文段落、字幕稿、教材内容都可以',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('分析并入库'),
          ),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    final text = textCtrl.text.trim();
    titleCtrl.dispose();
    textCtrl.dispose();
    if (ok != true || !context.mounted) return null;
    if (title.isEmpty || text.isEmpty) {
      _toast(context, '标题和正文都要填');
      return null;
    }
    try {
      final vocab = context.read<VocabProvider>().vocabularies;
      return await MaterialLibrary.ingestText(
        title: title,
        text: text,
        model: model,
        vocab: vocab,
      );
    } catch (e) {
      if (context.mounted) _toast(context, '导入失败:$e');
      return null;
    }
  }

  // ───────────────────────── ② 文件 ─────────────────────────

  static Future<IngestedMaterial?> _fromFile(
    BuildContext context,
    LearnerModel model,
  ) async {
    PickedLocalFile? picked;
    try {
      // 系统选择器(自写原生通道,零依赖;见 FilePickService 的说明)
      picked = await FilePickService.pickFile();
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
      return null;
    }
    if (picked == null || !context.mounted) return null;
    final name = picked.name;
    final ext = MaterialImport.extensionOf(name);
    if (MaterialImport.unsupportedExtensions.contains(ext)) {
      _toast(
        context,
        '.$ext 解析需要额外的解析库,本版还不支持 —— 可以先转成 txt 再导入,'
        '或直接复制文本用「粘贴材料」',
      );
      return null;
    }
    if (!MaterialImport.isSupportedFile(name)) {
      _toast(context, '只支持纯文本类文件(txt / md / srt / csv / json / html),'
          '这个文件的类型是 .$ext');
      return null;
    }
    final bytes = picked.bytes;
    if (bytes.isEmpty) {
      _toast(context, '这个文件是空的');
      return null;
    }
    if (bytes.length > maxFileBytes) {
      if (context.mounted) {
        _toast(
          context,
          '文件太大(${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB),'
          '上限 ${maxFileBytes ~/ 1024 ~/ 1024}MB —— 建议切成几份导入',
        );
      }
      return null;
    }
    final decoded = MaterialImport.decodeTextBytes(bytes);
    if (decoded.hasWarning && context.mounted) _toast(context, decoded.warning);
    try {
      final doc = MaterialImport.fromFileText(
        fileName: name,
        text: decoded.text,
      );
      if (!context.mounted) return null;
      // 文件名当标题先给用户过一眼(可以改成中文标题)
      final edited = await reviewDoc(
        context,
        title: doc.title,
        text: doc.plainText,
        note: '来自文件:$name',
        editableText: false,
      );
      if (edited == null || !context.mounted) return null;
      return await ingest(
        context,
        _retitle(doc, edited),
        model: model,
      );
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
      return null;
    }
  }

  // ───────────────────────── ③ 图片(AI 提取) ─────────────────────────

  static Future<IngestedMaterial?> _fromImage(
    BuildContext context,
    LearnerModel model,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择(可多选)'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return null;
    final picker = ImagePicker();
    final files = <File>[];
    try {
      if (source == ImageSource.camera) {
        final shot = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
          maxWidth: 2600,
        );
        if (shot != null) files.add(File(shot.path));
      } else {
        final picked = await picker.pickMultiImage(
          imageQuality: 92,
          maxWidth: 2600,
          limit: 6,
        );
        files.addAll(picked.map((x) => File(x.path)));
      }
    } catch (e) {
      if (context.mounted) _toast(context, '选图失败:$e');
      return null;
    }
    if (files.isEmpty || !context.mounted) return null;

    // 流式提取:边出边显示,用户能看到进度(长文可能要十几秒)
    final text = await _extractTextFromImages(context, files);
    if (text == null || !context.mounted) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _toast(context, 'AI 没有提取到文字 —— 换一张更清晰的图再试');
      return null;
    }
    final edited = await reviewDoc(
      context,
      title: '图片材料',
      text: trimmed,
      note: '由 ${files.length} 张图片经 AI 提取 —— '
          '识别难免有个别错字,可以直接在下面改好再入库',
      editableText: true,
    );
    if (edited == null || !context.mounted) return null;
    try {
      final doc = MaterialImport.fromImageText(
        text: edited.text,
        title: edited.title,
        sourceHint: '${files.length} 张图,可能有个别识别误差',
      );
      return await ingest(context, doc, model: model);
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
      return null;
    }
  }

  /// 调 AI 把图片转成文字(带进度弹窗)
  ///
  /// 进度用 [ValueNotifier] + 定时器推送:每个 chunk 都 setState 会在长文上
  /// 一秒重建几十次对话框,低端机直接掉帧;700ms 推一次"已提取 N 字 + 尾巴"
  /// 足够让用户看到它在干活。
  static Future<String?> _extractTextFromImages(
    BuildContext context,
    List<File> files,
  ) async {
    final api = DoubaoApiService();
    if (!api.isConfigured) {
      _toast(context, '图片提取需要先配置 API Key(我的 → API 设置)');
      return null;
    }
    final buffer = StringBuffer();
    final feed = ValueNotifier<String>('');
    StreamSubscription<SseChunk>? sub;
    final done = Completer<String?>();
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    Timer? ticker;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('正在提取图片文字…'),
        content: ValueListenableBuilder<String>(
          valueListenable: feed,
          builder: (ctx, value, _) => SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已提取 ${value.length} 字',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: Gap.xs),
                const LinearProgressIndicator(),
                const SizedBox(height: Gap.sm),
                Text(
                  value.length > 160
                      ? '…${value.substring(value.length - 160)}'
                      : value,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              sub?.cancel();
              if (!done.isCompleted) done.complete(null);
            },
            child: const Text('取消'),
          ),
        ],
      ),
    ).then((_) => dialogOpen = false);

    try {
      final stream = api.extractFullTextStream(files);
      sub = stream.listen(
        (chunk) {
          if (chunk.isReasoning) return;
          buffer.write(chunk.text);
        },
        onDone: () {
          if (!done.isCompleted) done.complete(buffer.toString());
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        cancelOnError: true,
      );
      ticker = Timer.periodic(const Duration(milliseconds: 700), (_) {
        feed.value = buffer.toString();
      });
      return await done.future.timeout(
        const Duration(minutes: 4),
        onTimeout: () {
          sub?.cancel();
          throw Exception('提取超时(4 分钟)—— 图片可能太大或模型太慢,可换一张图重试');
        },
      );
    } catch (e) {
      if (context.mounted) _toast(context, '提取失败:$e');
      return null;
    } finally {
      ticker?.cancel();
      feed.dispose();
      if (dialogOpen) navigator.pop();
    }
  }

  // ───────────────────────── ④ 链接 ─────────────────────────

  static Future<IngestedMaterial?> _fromLink(
    BuildContext context,
    LearnerModel model, {
    String? initialUrl,
  }) async {
    var prefill = (initialUrl ?? '').trim();
    if (prefill.isEmpty) {
      // 剪贴板里正好有个链接时直接填上 —— 用户多半是复制了链接才进来的
      try {
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        final t = (clip?.text ?? '').trim();
        if (t.isNotEmpty && MaterialSourceService.normalizeExternalUrl(t).isNotEmpty) {
          prefill = t;
        }
      } catch (_) {
        // 剪贴板读不到就不预填,不影响主流程
      }
    }
    if (!context.mounted) return null;
    final ctrl = TextEditingController(text: prefill);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从链接导入'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '贴一个公开网页链接(论文摘要页、期刊文章、新闻、博客…),'
                '软件会抓正文存进材料库,在里面就能逐段翻译、点词、追问。',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '链接',
                  hintText: 'https://arxiv.org/abs/1706.03762',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                '注:需要登录/付费的页面抓不到;正文由 JavaScript 渲染的站点也可能抓不到 —— '
                '失败时会有明确原因,并可以「用浏览器打开」看原文。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('抓取'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (url == null || url.trim().isEmpty || !context.mounted) return null;

    MaterialDoc doc;
    try {
      doc = await _withProgress(
        context,
        '正在抓取网页正文…',
        () => MaterialImport.fromAnyUrl(url, title: null),
      );
    } catch (e) {
      if (!context.mounted) return null;
      // 抓取失败 → 给"用浏览器打开"的退路(用户第 2(1) 条的心声)
      await _showFetchFailed(context, url, '$e');
      return null;
    }
    if (!context.mounted) return null;
    final edited = await reviewDoc(
      context,
      title: doc.title,
      text: doc.plainText,
      note: '来源:$url',
      editableText: false,
    );
    if (edited == null || !context.mounted) return null;
    try {
      return await ingest(context, _retitle(doc, edited), model: model);
    } catch (e) {
      if (context.mounted) _toast(context, '$e');
      return null;
    }
  }

  /// 抓取失败弹窗:原因 + 「用浏览器打开」+ 「重试」
  static Future<void> _showFetchFailed(
    BuildContext context,
    String url,
    String reason,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('这个链接抓不到正文'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reason, style: const TextStyle(fontSize: 13, height: 1.5)),
              const SizedBox(height: Gap.sm),
              SelectableText(url,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 公共小件 ─────────────────────────

  /// 入库前的人工校对弹窗:标题可改;图片提取的正文也可改(OCR 难免有错字)。
  ///
  /// [text] 传**全文**;不可编辑时(文件/链接,可能几十万字)只把前 1500 字放进
  /// 预览框,免得把整本书塞进一个 TextField(内存与重建代价都不划算)。
  static Future<({String title, String text})?> reviewDoc(
    BuildContext context, {
    required String title,
    required String text,
    String note = '',
    bool editableText = false,
  }) async {
    final titleCtrl = TextEditingController(text: title);
    final preview = _previewOf(text);
    final textCtrl = TextEditingController(text: preview);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认材料'),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.isNotEmpty) ...[
                  Text(note,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      )),
                  const SizedBox(height: Gap.xs),
                ],
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: Gap.sm),
                if (editableText)
                  TextField(
                    controller: textCtrl,
                    maxLines: 10,
                    minLines: 6,
                    decoration: const InputDecoration(
                      labelText: '正文(可直接改)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Gap.sm),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: Radii.controlRadius,
                    ),
                    child: Text(preview,
                        style: const TextStyle(fontSize: 12, height: 1.5)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('分析并入库'),
          ),
        ],
      ),
    );
    final t = titleCtrl.text.trim();
    final editedBody = textCtrl.text.trim();
    titleCtrl.dispose();
    textCtrl.dispose();
    if (ok != true) return null;
    // 不可编辑的通道:正文一律用原文,避免"只存了前 1500 字"
    final body = editableText
        ? (editedBody.isEmpty ? text : editedBody)
        : text;
    return (title: t.isEmpty ? title : t, text: body);
  }

  /// 预览文本:超长时截断并注明还剩多少字(用户能看出这不是全文)
  static String _previewOf(String text) {
    const limit = 1500;
    if (text.length <= limit) return text;
    return '${text.substring(0, limit)}\n……(后面还有 ${text.length - limit} 字,'
        '不会丢,入库的是完整正文)';
  }

  /// 用用户改过的标题重建文档(块与元信息原样保留,只换标题)
  static MaterialDoc _retitle(
    MaterialDoc doc,
    ({String title, String text}) edited,
  ) {
    final titleChanged = edited.title.trim() != doc.title.trim();
    final textChanged = edited.text.trim() != doc.plainText.trim();
    if (!titleChanged && !textChanged) return doc;
    return MaterialDoc(
      sourceId: doc.sourceId,
      sourceId2: doc.sourceId2,
      kind: doc.kind,
      title: edited.title.trim().isEmpty ? doc.title : edited.title.trim(),
      author: doc.author,
      url: doc.url,
      license: doc.license,
      language: doc.language,
      audioUrl: doc.audioUrl,
      chunks: textChanged
          ? MaterialSourceService.chunkByWords(edited.text, wordsPerChunk: 2500)
          : doc.chunks,
      plainText: textChanged
          ? edited.text
          : doc.plainText,
    );
  }

  /// 弹一个不可取消的进度框跑一段异步活儿
  static Future<T> _withProgress<T>(
    BuildContext context,
    String label,
    Future<T> Function() job,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(child: AppLoading(label: label)),
    );
    try {
      return await job();
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// 把英文标题补成「中文(英文)」(用户第 2(2) 条:材料标题都要中英并列)。
  /// 实现移到 [MaterialImport.localizedTitle](服务层,材料中心也用同一份)。
  static Future<String> localizedTitle(String rawTitle) =>
      MaterialImport.localizedTitle(rawTitle);

  static void _toast(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}
