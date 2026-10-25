import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/bookmark.dart';
import '../../models/writing_log.dart';
import '../../providers/bookmark_provider.dart';
import '../../services/base_api.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/writing_review_settings.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart' show AppProgressRing;
import '../../widgets/error_state.dart';
import '../../widgets/writing_labels.dart';
import '../input/widgets/follow_up_drawer.dart';
import 'writing_logs_screen.dart';

/// 写译批改(v1.5.0 初版 / v1.6.0 重构 / v2.13 手写直批 + 可配置)。
///
/// 流程:选材料类型(手写档 / 电子档)→ 手写档**二选一**:
/// ①「先转电子档」识别成可编辑文本(改错别字)再批改;
/// ②「直接批改」把照片交给视觉模型,边识别边批改,不强制转文本。
/// 批改前可在「批改设置」里查看/修改预设提示词、选择思考强度(都会记住)。
/// 结果:分数 + 分类错误汇总 + 逐条点评 + 修正全文;每条点评可点开追问 AI。
class WriteReviewScreen extends StatefulWidget {
  const WriteReviewScreen({super.key});

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

enum _Phase { compose, transcribing, reviewing, result, error }

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  final ImagePicker _picker = ImagePicker();
  final _api = DoubaoApiService();
  final _textCtrl = TextEditingController();
  final List<File> _images = [];

  /// 手写档 / 电子档(取值与标签统一在 lib/widgets/writing_labels.dart,
  /// 与「写译记录」页共用同一份,避免两页文案漂移 —— P2-29)
  String _materialType = kMaterialTypeHandwritten;

  _Phase _phase = _Phase.compose;
  String? _error;

  Map<String, dynamic> _result = {};
  List<Map<String, String>> _issues = [];
  Map<String, String> _errorSummary = {};
  bool _promptedSave = false;
  bool _saved = false;

  /// 退出确认弹窗是否已经打开(P2-27):连按两次返回键只弹一个窗
  bool _exitDialogOpen = false;

  /// 本次结果是否来自「直接批改手写图」(v2.13)。
  /// 「重新批改」要沿用同一条路径 —— 用户点的是"重新批改这张照片",
  /// 不能因为模型顺手带回了 transcript 就悄悄改成文本批改。
  bool _reviewFromImages = false;

  /// 实际批改用的模型(保存写译记录时写入,而不是记成追问槽位的模型)
  String _reviewModel = '';

  /// 直接批改手写图时模型附带的识别原文(transcript)。
  /// 单独存一份而不是只看 `_textCtrl`:用户可能先敲了自己的草稿再去直批照片,
  /// 这时"我的原文"是他敲的内容,不能标成"识别自手写稿";
  /// 两份不一致时结果页会把识别原文另外列出来供核对。
  String _transcript = '';

  /// 批改设置(v2.13):提示词 / 思考强度都来自 Hive,这里只缓存一份,
  /// 设置页保存后刷新。默认值与读写规则统一收在 WritingReviewSettings。
  String _reviewPrompt = WritingReviewSettings.defaultPrompt;
  String _reviewThinking = WritingReviewSettings.defaultThinking;

  late final FollowUpController _followUp;

  static const _maxImages = 9;

  @override
  void initState() {
    super.initState();
    _followUp = FollowUpController(
      buildContext: _buildFollowUpContext,
      imageFilesProvider: () =>
          _materialType == kMaterialTypeHandwritten ? _images : null,
      historyKey: 'saved_writing_follow_up_chats',
      emptyHint: '就这次批改提问',
    );
    _loadReviewSettings();
  }

  /// 读批改设置。为什么放 initState 而不是 build:
  /// Hive 读取虽快也仍是 I/O,放进 build 会在每次重建时重复读;
  /// 而"下次进来自动带上次选择"只需要进页面时读一次。
  void _loadReviewSettings() {
    final reviewCfg = DoubaoApiService.reviewWritingEndpoint();
    _reviewModel = reviewCfg.model;
    _reviewPrompt = WritingReviewSettings.prompt();
    _reviewThinking = WritingReviewSettings.thinkingFor(reviewCfg.model);
  }

  @override
  void dispose() {
    _followUp.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  /// 追问抽屉的材料上下文:原文 + 批改结果 + 错误汇总
  String _buildFollowUpContext() {
    final buf = StringBuffer('材料类型:写译批改(用户提交的英文写作)\n');
    if (_reviewFromImages) {
      buf.writeln(
        '批改方式:直接批改手写照片(共 ${_images.length} 张,没有先转成电子稿)',
      );
    }
    final text = _textCtrl.text.trim();
    if (text.isNotEmpty) {
      buf.writeln('【我的原文】\n$text');
    } else if (_images.isNotEmpty) {
      buf.writeln('【我的原文】见随消息附上的手写稿照片');
    }
    // 用户先敲草稿又直批照片时,模型看到的是照片,不是草稿 ——
    // 把识别原文也带上,追问才不会"按错的那份"回答
    final transcript = _transcript.trim();
    if (transcript.isNotEmpty && transcript != text) {
      buf.writeln('\n【手写稿识别原文】\n$transcript');
    }
    final corrected = (_result['correction'] ?? '').toString().trim();
    if (corrected.isNotEmpty) {
      buf.writeln('\n【批改后全文】\n$corrected');
    }
    final score = (_result['score'] ?? '').toString().trim();
    if (score.isNotEmpty) buf.writeln('\n【得分】$score');
    if (_issues.isNotEmpty) {
      buf.writeln('\n【逐条点评】');
      for (final it in _issues) {
        buf.writeln(
          '- 原文「${it['original']}」→ 改为「${it['correction']}」'
          '(${it['type']}):${it['reason']}',
        );
      }
    }
    final summaryText = _errorSummary.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}:${e.value}')
        .join(';');
    if (summaryText.isNotEmpty) {
      buf.writeln('\n【错误分类汇总】$summaryText');
    }
    return buf.toString();
  }

  /// 点某一条批改错误 → 打开追问抽屉,自动带上这一条的上下文与预设问题。
  ///
  /// 为什么复用 [FollowUpController] 而不是新造弹层:
  /// - 抽屉已有流式输出、思考折叠、收藏、模型/思考切换、上下楼记忆;
  /// - 用户从识图页过来时操作是同一套,不必再学;
  /// - `contextOverride` 本来就是给"从某一处内容发起追问"准备的(识图页详解同款)。
  ///
  /// 只预填不自动发送:一次点击就产生一次 API 调用(花钱,而且用户没法先改问题),
  /// 保留"看一眼问题再发"的控制感;上下文已经塞好,直接点发送即可。
  void _askAboutIssue(int index, Map<String, String> issue) {
    final original = (issue['original'] ?? '').trim();
    final correction = (issue['correction'] ?? '').trim();
    final type = (issue['type'] ?? '').trim();
    final reason = (issue['reason'] ?? '').trim();
    final focus = StringBuffer()
      ..writeln('【用户点开了第 ${index + 1} 条错误,想重点追问这一条】')
      ..writeln('- 分类:${type.isEmpty ? '未分类' : type}')
      ..writeln('- 原句:${original.isEmpty ? '(AI 未给出原文片段)' : original}')
      ..writeln('- 建议改为:${correction.isEmpty ? '(无)' : correction}')
      ..writeln('- 批改解释:${reason.isEmpty ? '(无)' : reason}');
    final question = StringBuffer('这条错误请展开讲讲：');
    if (original.isNotEmpty) question.write('为什么「${_clip(original, 60)}」不对？');
    if (correction.isNotEmpty) {
      question.write('改成「${_clip(correction, 60)}」的依据是什么？');
    }
    question.write(
      '还能怎么改？请把${type.isEmpty ? '涉及的语法点' : '这一处$type问题'}讲清楚。',
    );
    showFollowUpDrawer(
      context: context,
      controller: _followUp,
      title: '追问这条错误',
      prefillQuestion: question.toString(),
      contextOverride: '$focus\n${_buildFollowUpContext()}',
    );
  }

  /// 预填问题里引用原文/改文的截断:整句塞进输入框会占满 4 行;
  /// 完整内容在追问上下文里,不会丢。
  String _clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  // ── 图片 ──

  Future<void> _pickImages({required bool fromCamera}) async {
    if (_images.length >= _maxImages) {
      _toast('最多 $_maxImages 张图片');
      return;
    }
    try {
      if (fromCamera) {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: 1600,
        );
        if (photo != null && mounted) {
          setState(() => _images.add(File(photo.path)));
        }
      } else {
        final picked = await _picker.pickMultiImage(
          imageQuality: 70,
          maxWidth: 1600,
          limit: _maxImages - _images.length,
        );
        if (picked.isNotEmpty && mounted) {
          setState(() {
            _images.addAll(
              picked
                  .take(_maxImages - _images.length)
                  .map((x) => File(x.path)),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) _toast('选择图片失败：$e');
    }
  }

  // ── 识别(手写档 → 电子档) ──

  Future<void> _transcribe() async {
    if (_images.isEmpty) {
      _toast('请先拍照或从相册选择手写稿');
      return;
    }
    setState(() {
      _phase = _Phase.transcribing;
      _error = null;
    });
    try {
      final text = await _api.transcribeWriting(_images);
      if (!mounted) return;
      setState(() {
        final old = _textCtrl.text.trim();
        _textCtrl.text = old.isEmpty ? text : '$old\n$text';
        _phase = _Phase.compose;
      });
      _toast('已识别为电子档，可修改后批改');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '识别失败：${BaseApiService.friendlyError(e)}';
      });
    }
  }

  // ── 批改 ──

  /// 文本批改(电子档,或手写档先转成的电子稿)。
  Future<void> _review() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _toast(
        _materialType == kMaterialTypeHandwritten && _images.isNotEmpty
            ? '请先输入英文，或点「直接批改手写图」让 AI 看手写稿'
            : '请先输入英文内容',
      );
      return;
    }
    final cfg = DoubaoApiService.reviewWritingEndpoint();
    setState(() {
      _phase = _Phase.reviewing;
      _error = null;
      _reviewFromImages = false;
      _reviewModel = cfg.model;
      _transcript = '';
      _promptedSave = false;
      _saved = false;
    });
    try {
      final result = await _api.reviewWriting(
        text,
        endpoint: cfg,
        systemPrompt: _reviewPrompt,
        thinkingLevel: _reviewThinking,
      );
      _applyResult(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '批改失败：${BaseApiService.friendlyError(e)}';
      });
    }
  }

  /// 直接批改手写图(v2.13):不强制转电子档,把照片交给视觉模型边识别边批改。
  ///
  /// 与 [_review] 分开两条入口而不是加一个布尔开关:
  /// 用户在上传区就能看到两个并列的按钮("先转电子档"/"直接批改"),
  /// 不必先理解某个开关代表什么;两条路径的失败原因也不同(看图不支持 vs 文本为空)。
  Future<void> _reviewImages() async {
    if (_images.isEmpty) {
      _toast('请先拍照或从相册选择手写稿');
      return;
    }
    final cfg = DoubaoApiService.reviewWritingEndpoint(requireVision: true);
    setState(() {
      _phase = _Phase.reviewing;
      _error = null;
      _reviewFromImages = true;
      _reviewModel = cfg.model;
      _transcript = '';
      _promptedSave = false;
      _saved = false;
    });
    try {
      final result = await _api.reviewWritingImages(
        _images,
        endpoint: cfg,
        systemPrompt: _reviewPrompt,
        thinkingLevel: _reviewThinking,
      );
      _applyResult(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '批改失败：${BaseApiService.friendlyError(e)}';
      });
    }
  }

  /// 批改成功后的统一收尾(文本批改 / 手写直批都走这里,避免两套状态更新漂移)。
  void _applyResult(Map<String, dynamic> result) {
    if (!mounted) return;
    final transcript = (result['transcript'] ?? '').toString().trim();
    setState(() {
      _result = result;
      _issues = (result['issues'] as List<Map<String, String>>?) ?? [];
      _errorSummary =
          (result['error_summary'] as Map<String, String>?) ?? {};
      _transcript = _reviewFromImages ? transcript : '';
      // 直接批改手写图时模型会带回 transcript:补进「我的原文」,
      // 用户能核对有没有看错字,也能接着在电子稿上改。
      // 只在原文为空时填 —— 绝不覆盖用户自己敲过的内容。
      if (transcript.isNotEmpty && _textCtrl.text.trim().isEmpty) {
        _textCtrl.text = transcript;
      }
      _phase = _Phase.result;
    });
    if (!_promptedSave) {
      _promptedSave = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _askSaveLog());
    }
  }

  // ── 保存练习日志 ──

  Future<void> _askSaveLog() async {
    if (!mounted || _saved) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('是否保存此次写译练习？'),
        content: const Text('保存后可在「写译记录」按日期查阅。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('暂不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) await _saveLog();
  }

  /// 保存为写译记录。返回是否真的写库成功 ——
  /// 退出确认要用它决定"保存后能不能 pop":失败还退出去等于数据照样丢。
  Future<bool> _saveLog() async {
    try {
      await DatabaseService.insertWritingLog(
        WritingLog(
          sourceType: _materialType,
          originalText: _textCtrl.text.trim(),
          correctedText: (_result['correction'] ?? '').toString(),
          score: (_result['score'] ?? '').toString(),
          summary: (_result['summary'] ?? '').toString(),
          issues: _issues,
          errorSummary: _errorSummary,
          // 记**实际批改用的模型**(可能是副槽位/主槽位,也可能因直批手写图换了视觉槽位),
          // 不是追问槽位 —— 记录页复盘时看到的名字要和那次批改对得上。
          model: _reviewModel.isNotEmpty
              ? _reviewModel
              : _followUp.endpoint.model,
          imagePaths: _images.map((f) => f.path).toList(),
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) {
        setState(() => _saved = true);
        _toast('已保存到写译记录');
      }
      return true;
    } catch (e) {
      if (mounted) _toast('保存失败：$e');
      return false;
    }
  }

  /// 收藏这次批改(v2.8,用户第 10 条):错处与点评进「写译收藏夹」。
  ///
  /// 为什么值得有:写译的问题是"每次都犯同一类错",把批改收藏起来,
  /// 以后在收藏夹里能集中回看"我反复踩的坑是什么"。
  Future<void> _bookmarkReview() async {
    final bp = context.read<BookmarkProvider>();
    final summary = (_result['summary'] ?? '').toString().trim();
    final score = (_result['score'] ?? '').toString().trim();
    final issues = _issues
        .map((e) => '· ${e['type'] ?? ''}：${e['detail'] ?? e['original'] ?? ''}')
        .join('\n');
    // 错误归类是 Map<类别, 说明>,拼成一行"类别:说明"更省地方
    final errorLines = _errorSummary.entries
        .where((e) => e.value.trim().isNotEmpty)
        .map((e) => '${e.key}:${e.value.trim()}')
        .join('; ');
    final body = StringBuffer();
    if (score.isNotEmpty) body.writeln('得分：$score');
    if (summary.isNotEmpty) body.writeln(summary);
    if (errorLines.isNotEmpty) body.writeln('错误归类：$errorLines');
    if (issues.isNotEmpty) body.writeln(issues);
    if (body.toString().trim().isEmpty) {
      _toast('这次还没有可收藏的批改内容');
      return;
    }
    final saved = await bp.toggle(
      Bookmark(
        source: AppConstants.bookmarkSourceWriting,
        title: '写译批改 ${DateTime.now().month}/${DateTime.now().day}'
            '${score.isEmpty ? '' : ' · $score'}',
        content: body.toString().trim(),
      ),
    );
    if (!mounted) return;
    _toast(saved ? '已收藏进「写译」收藏夹' : '已取消收藏');
  }

  // ── 退出保护(P2-27) ──
  /// 页面上是否有"值得挽留"的产物:敲过的原文 / 拍过的手写稿 / 已出的批改结果。
  bool _hasUnsavedWork() {
    if (_textCtrl.text.trim().isNotEmpty) return true;
    if (_images.isNotEmpty) return true;
    if (_phase == _Phase.result || _result.isNotEmpty) return true;
    return false;
  }

  /// 原文词数(编辑态与退出提示共用一份算法,避免两处数出不同结果)
  int get _wordCount => _textCtrl.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;

  /// 返回键/左上角箭头被按下时的三选一问(与识图页 process_chat.dart 的
  /// `_onWillPop` 同一套交互风格:取消 / 直接离开 / 保存并退出)。
  ///
  /// 为什么必须问:手写档最多要拍 9 张、原文可能敲几百字、批改还花过一次
  /// AI 调用 —— 按一下返回就全丢,而且不进 writing_logs(练习统计少记)。
  /// 返回 true = 允许离开;false = 留在本页。
  Future<bool> _onWillPop() async {
    if (!_hasUnsavedWork()) return true; // 空白页:不打扰用户
    if (_exitDialogOpen) return false; // 连点两次返回不叠弹窗
    _exitDialogOpen = true;
    var choice = 'cancel';
    try {
      final parts = <String>[];
      if (_textCtrl.text.trim().isNotEmpty) parts.add('$_wordCount 词原文');
      if (_images.isNotEmpty) parts.add('${_images.length} 张手写稿');
      if (_phase == _Phase.result) parts.add('本次批改结果');
      final what = parts.isEmpty ? '当前内容' : parts.join('、');
      final hint = _phase == _Phase.result
          ? '保存为写译记录后可在「写译记录」按日期查阅。'
          : '保存为写译记录后可在「写译记录」按日期查阅。\n'
                '（本次还没批改，记录里暂时没有分数与点评）';
      choice =
          await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('离开写译批改？'),
              content: Text('你还有 $what 没有保存。\n$hint'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'discard'),
                  child: const Text('直接离开'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('保存为写译记录'),
                ),
              ],
            ),
          ) ??
          'cancel';
    } finally {
      _exitDialogOpen = false;
    }
    if (choice == 'save') {
      final saved = await _saveLog();
      // 保存失败就留在页面上(草稿还在),不要"报个错然后照退不误"
      if (!saved) return false;
      // 顺手把本轮追问对话存进历史,避免"存了批改却丢了追问"
      if (_followUp.dirty && _followUp.messages.value.isNotEmpty) {
        await _followUp.saveConversation();
      }
      return true;
    }
    return choice == 'discard';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _backToCompose() {
    setState(() {
      _phase = _Phase.compose;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 我们手动控制:先问保存/离开,再决定退不退(P2-27)
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        try {
          final ok = await _onWillPop();
          // 这里的 context 是 build 参数,不是 State.context —— 异步后用
          // context.mounted 判断才对得上(用 mounted 会被 lint 认为"无关检查")
          if (ok && context.mounted) Navigator.of(context).pop(result);
        } catch (e) {
          // 兜底:确认流程本身出错也不能把用户困在这一页
          debugPrint('ReadFlow writeReview onPopInvokedWithResult: $e');
          if (context.mounted) Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('写译批改'),
          actions: [
            // 常驻保存入口(P2-27):结果页很长,底部的保存按钮得滚到底才看得见;
            // 而原来只有"批改完成弹一次"的对话框,点过"暂不保存"就再也回不来。
            // 这里刻意用紧凑的图标按钮:AppBar 是 centerTitle,放带文字的长按钮
            // 会挤压居中的标题(窄屏上标题会被截断)。
            if (_phase == _Phase.result)
              IconButton(
                tooltip: _saved ? '已保存到写译记录' : '保存记录',
                icon: Icon(
                  _saved ? Icons.check_circle_outline : Icons.save_outlined,
                ),
                onPressed: _saved ? null : () => _saveLog(),
              ),
            // v2.8(用户第 10 条):批改结果可收藏进「写译收藏夹」
            // —— 收藏的是这次批改的错处与点评,方便以后集中回看
            if (_phase == _Phase.result)
              IconButton(
                tooltip: '收藏这次批改(写译收藏夹)',
                icon: const Icon(Icons.star_border),
                onPressed: _bookmarkReview,
              ),
            IconButton(
              tooltip: '写译记录',
              icon: const Icon(Icons.history_edu_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WritingLogsScreen()),
              ),
            ),
          ],
        ),
        floatingActionButton: _phase == _Phase.result
            ? FloatingActionButton.extended(
                onPressed: () => showFollowUpDrawer(
                  context: context,
                  controller: _followUp,
                  title: '追问批改',
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('追问'),
              )
            : null,
        body: AnimatedSwitcher(
          // A1:阶段切换(编辑 → 生成中 → 结果/错误)给 200ms easeOut 淡入,
          // 不再硬切;分数圆环另有 520ms 的数值入场(见 _scoreBadge)。
          // 输入、滚动这类高频操作不加动画。
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          child: KeyedSubtree(
            key: ValueKey(_phase),
            child: switch (_phase) {
              _Phase.error => _buildError(context),
              _Phase.transcribing || _Phase.reviewing => _buildLoading(context),
              _Phase.result => _buildResult(context),
              _Phase.compose => _buildCompose(context),
            },
          ),
        ),
      ),
    ); // PopScope
  }

  // ── 编辑态 ──

  Widget _buildCompose(BuildContext context) {
    final theme = Theme.of(context);
    final isHandwritten = _materialType == kMaterialTypeHandwritten;
    final wordCount = _wordCount;
    return ListView(
      padding: Insets.page,
      children: [
        // 材料类型(取值与文案见 lib/widgets/writing_labels.dart,
        // 与「写译记录」页共用一份 —— P2-29 的局部收口)
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: kMaterialTypeHandwritten,
              icon: Icon(Icons.gesture, size: 16),
              label: Text(kMaterialTypeHandwrittenLabel),
            ),
            ButtonSegment(
              value: kMaterialTypeElectronic,
              icon: Icon(Icons.keyboard_alt_outlined, size: 16),
              label: Text(kMaterialTypeElectronicLabel),
            ),
          ],
          selected: {_materialType},
          onSelectionChanged: (s) => setState(() => _materialType = s.first),
        ),
        const SizedBox(height: Gap.sm),

        // 手写稿:固定高度横向条,永不撑破页面
        if (isHandwritten) ...[
          Row(
            children: [
              Text(
                '手写稿 ${_images.length}/$_maxImages',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: '从相册选择（可多选）',
                onPressed: () => _pickImages(fromCamera: false),
                icon: const Icon(Icons.photo_library_outlined),
              ),
              IconButton(
                tooltip: '拍照',
                onPressed: () => _pickImages(fromCamera: true),
                icon: const Icon(Icons.camera_alt_outlined),
              ),
            ],
          ),
          const SizedBox(height: Gap.xxs),
          SizedBox(
            height: 92,
            child: _images.isEmpty
                ? GestureDetector(
                    onTap: () => _pickImages(fromCamera: false),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: Radii.controlRadius,
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 28,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: Gap.xs),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _openImageViewer(i),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(Radii.control - 2),
                            child: Image.file(
                              _images[i],
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // 角标压在图片上:黑白在两种主题下都对(硬编码色闸门已豁免)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _images.removeAt(i)),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black54,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: Gap.xs),
          // v2.13:两条路并列摆出来,由用户选,不再强制先转写。
          // 竖排而不是左右各半:系统字号放大到 2× 时,半宽按钮里的
          // "先转成电子档(可改)" 会被挤破;写译用户里有不少会开大字号。
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _images.isEmpty ? null : _transcribe,
              icon: const Icon(Icons.document_scanner_outlined, size: 16),
              // 标签刻意短("可改"放在下面的说明里):大字号下长按钮会挤爆
              label: const Text('先转电子档'),
            ),
          ),
          const SizedBox(height: Gap.xs),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _images.isEmpty ? null : _reviewImages,
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('直接批改手写图'),
            ),
          ),
          const SizedBox(height: Gap.xxs),
          Text(
            '两种都行：先转电子档可以顺手改错别字；直接批改会把照片交给 AI，跳过转写确认。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Gap.sm),
        ],

        // 文本区:固定高度,内部滚动(长文不会把页面顶爆)
        Row(
          children: [
            Text(
              isHandwritten ? '电子档' : '英文内容',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '$wordCount 词',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        SizedBox(
          height: 240,
          child: TextField(
            controller: _textCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: isHandwritten
                  ? '可先点「先转电子档」，或直接在上面输入/粘贴英文'
                  : '粘贴或输入要批改的英文',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(Gap.sm),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        _reviewSettingsEntry(theme),
        const SizedBox(height: Gap.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _review,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('AI 批改'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: Gap.sm + 2),
            ),
          ),
        ),
      ],
    );
  }

  /// 「批改设置」入口:一眼看到当前提示词是否自定义、思考档位是什么,
  /// 点开可改提示词 / 换思考强度。放在批改按钮正上方,是"批改前"的最后一站。
  Widget _reviewSettingsEntry(ThemeData theme) {
    final customized =
        _reviewPrompt.trim() != WritingReviewSettings.defaultPrompt.trim();
    final thinkingLabel =
        WritingReviewSettings.thinkingLabel(_reviewModel, _reviewThinking);
    return AppCard(
      onTap: _openReviewSettings,
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.sm,
        vertical: Gap.xs,
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '批改设置',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '提示词：${customized ? '已自定义' : '默认'} · 思考：$thinkingLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  /// 打开批改设置(提示词 + 思考强度)。
  ///
  /// 只有设置页返回 true 才刷新缓存:用户直接下滑关闭 = 放弃本次修改,
  /// 不能把没保存的编辑误当成已经生效的设置。
  Future<void> _openReviewSettings() async {
    final cfg = DoubaoApiService.reviewWritingEndpoint();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ReviewSettingsSheet(
          initialPrompt: _reviewPrompt,
          initialThinking: WritingReviewSettings.thinkingFor(cfg.model),
          model: cfg.model,
        ),
      ),
    );
    if (!mounted || saved != true) return;
    setState(() {
      _reviewPrompt = WritingReviewSettings.prompt();
      _reviewThinking = WritingReviewSettings.thinkingFor(cfg.model);
      _reviewModel = cfg.model;
    });
    _toast('已保存批改设置');
  }

  /// 全屏看图(v1.7.0):可缩放拖动,点空白处关闭
  void _openImageViewer(int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, _) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text('${index + 1} / ${_images.length}'),
          ),
          body: GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.file(_images[index], fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return AppLoading(
      label: _phase == _Phase.transcribing
          ? 'AI 正在识别手写内容…'
          : _reviewFromImages
          ? 'AI 正在读手写稿并批改…'
          : 'AI 正在批改写作…',
    );
  }

  Widget _buildError(BuildContext context) {
    // 用公共 ErrorState(P2-30 / B4):错误 + 一个明确出口,
    // 与统计页/写译记录页的错误态长得一样,用户不必重新学
    return ErrorState(
      message: _error ?? '批改失败',
      onRetry: _backToCompose,
      retryLabel: '返回重试',
    );
  }

  // ── 结果态 ──

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final scoreTxt = (_result['score'] ?? '').toString();
    final score = int.tryParse(scoreTxt);
    // 语义色随明暗切换(v2.5,U2):以前写死 Colors.green/orange/red,
    // 白底上只有 2.5~3.1:1(小字号看不清),深色下又偏刺眼
    final scoreColor = score == null
        ? theme.colorScheme.onSurfaceVariant
        : score >= 80
        ? AppTheme.successColor(context)
        : score >= 60
        ? AppTheme.warningColor(context)
        : AppTheme.dangerColor(context);
    final hasSummary = _errorSummary.values.any((v) => v.trim().isNotEmpty);
    final shownOriginal = _textCtrl.text.trim();
    final transcript = _transcript.trim();
    final originalFromTranscript = _reviewFromImages &&
        transcript.isNotEmpty &&
        shownOriginal == transcript;
    // 没有可显示原文时给一句如实的说明(直批手写稿且模型没回 transcript)
    final emptyOriginalHint = _reviewFromImages && _images.isNotEmpty
        ? '本次直接批改手写稿（${_images.length} 张），没有生成电子稿。'
              '想要可编辑的原文，可以回上一步点「先转电子档」。'
        : '（这次没有可显示的原文）';

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 96),
      children: [
        // 分数 + 总评
        AppCard(
          color: scoreColor.withAlpha(12),
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              _scoreBadge(
                score: score,
                scoreTxt: scoreTxt,
                color: scoreColor,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  (_result['summary'] ?? '').toString().isEmpty
                      ? '批改完成'
                      : _result['summary'].toString(),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),

        // 错误分类汇总
        if (hasSummary) ...[
          const AppSectionTitle(title: '错误分类汇总'),
          ...WritingLog.categories
              .where((c) => (_errorSummary[c] ?? '').trim().isNotEmpty)
              .map((c) => _summaryCard(theme, c, _errorSummary[c]!)),
        ],

        // 逐条点评(v2.13):每条都可点开追问,副标题把入口说清楚
        if (_issues.isNotEmpty) ...[
          AppSectionTitle(
            title: '逐条点评（${_issues.length}）',
            subtitle: '点任意一条可追问 AI',
          ),
          ..._issues.asMap().entries.map(
            (e) => _issueCard(theme, e.key, e.value),
          ),
        ],

        // 修正后全文
        if ((_result['correction'] ?? '').toString().isNotEmpty) ...[
          const AppSectionTitle(title: '修正后全文'),
          AppCard(
            child: SelectableText(
              _result['correction'].toString(),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        ],

        // 我的原文(直接批改且模型没回 transcript 时没有文本可显示 ——
        // 如实说明批改依据是照片,不要让用户以为原文丢了)
        AppSectionTitle(
          title: originalFromTranscript ? '我的原文（识别自手写稿）' : '我的原文',
        ),
        AppCard(
          child: shownOriginal.isEmpty
              ? Text(
                  emptyOriginalHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : SelectableText(
                  shownOriginal,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),

        // 用户先敲了自己的草稿、又直接批改了照片:识别原文与草稿是两份东西,
        // 单独列出来,用户才能核对 AI 到底按哪份批的(也避免被标成"识别自手写稿")
        if (_reviewFromImages &&
            transcript.isNotEmpty &&
            shownOriginal.isNotEmpty &&
            shownOriginal != transcript) ...[
          const AppSectionTitle(title: '手写稿识别原文'),
          AppCard(
            child: SelectableText(
              transcript,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],

        const SizedBox(height: Gap.md),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _backToCompose,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('修改后再批'),
            ),
            const Spacer(),
            FilledButton.icon(
              // 直接批改的结果要沿用照片路径重新批,不能悄悄换成文本批改
              onPressed: _reviewFromImages ? _reviewImages : _review,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(_reviewFromImages ? '重新批改照片' : '重新批改'),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _saved ? null : () => _saveLog(),
            icon: Icon(
              _saved ? Icons.check : Icons.save_outlined,
              size: 18,
            ),
            // 文案与 AppBar 的「保存记录」/退出弹窗的「保存为写译记录」对齐(P2-29)
            label: Text(_saved ? '已保存到写译记录' : '保存为写译记录'),
          ),
        ),
      ],
    );
  }

  /// 分数圆环 + 分数文本。
  ///
  /// A1(动效):从生成中到出结果是全 App 唯一的"成就时刻",值得一次
  /// 520ms 的 TweenAnimationBuilder 入场 —— 数字从 0 涨到目标分,
  /// 圆环按同一进度填充(两者读同一个动画值,数字和环不会脱节)。
  /// 用 TweenAnimationBuilder 而不是 AnimationController:一次性的值入场,
  /// 不需要显式管理生命周期,也不怕页面重建后重播(目标值不变就不重播)。
  ///
  /// B3(字号放大):不再是 64×64 硬盒 + fontSize 22 —— 系统字号 1.5×~2× 时
  /// 会被裁掉。下限保持 64,上限 84 兜底,里面套 FittedBox:正常字号仍是 64,
  /// 字号放大时圆环跟着长一点,极端字号则缩小填进去。
  Widget _scoreBadge({
    required int? score,
    required String scoreTxt,
    required Color color,
  }) {
    final target = (score ?? 0).clamp(0, 100).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final shown = score == null
            ? (scoreTxt.isEmpty ? '--' : scoreTxt)
            : '${value.round()}';
        return Stack(
          alignment: Alignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 64,
                minHeight: 64,
                maxWidth: 84,
                maxHeight: 84,
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(25),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shown,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
            // 圆环:与数字共用动画值(0 → score/100)
            if (score != null)
              Positioned.fill(
                child: IgnorePointer(
                  // 这个环画的是「已经出分」的确定值(不是等待态),所以不能用
                  // 骨架屏/时间线 —— 那会把刚出来的分数盖住。铁律又不许出现
                  // CircularProgressIndicator,于是复用 design_kit 里自绘的
                  // AppProgressRing(它正是为这条规则准备的)。
                  // centerText 传空:分数由下层 Container 显示,避免重复。
                  child: AppProgressRing(
                    value: value / 100,
                    centerText: '',
                    size: 84,
                    stroke: 3.5,
                    color: color,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(ThemeData theme, String category, String text) {
    // 用调色板角色而不是写死的紫/蓝/青:深浅两套主题下都成立,
    // 也保证和主色是一家人(不再是一堆"看着很语义"的杂色)
    final cs = theme.colorScheme;
    final color = switch (category) {
      '词汇' => cs.tertiary,
      '语法' => cs.secondary,
      '表达优化' => cs.primary,
      _ => cs.onSurfaceVariant,
    };
    return AppCard(
      margin: const EdgeInsets.only(bottom: Gap.xs),
      padding: const EdgeInsets.all(Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(Radii.control - 4),
            ),
            child: Text(
              category,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  /// 单条点评卡片(v2.13):**整张卡可点** → 带着这一条的上下文追问 AI。
  ///
  /// 右上角必须写「追问」:只让卡片可点而不给提示,用户不会发现这个入口
  /// (批改结果很长,卡片看起来又像纯展示)。
  Widget _issueCard(ThemeData theme, int index, Map<String, String> issue) {
    final original = issue['original'] ?? '';
    final correction = issue['correction'] ?? '';
    final type = issue['type'] ?? '';
    final reason = issue['reason'] ?? '';
    return AppCard(
      margin: const EdgeInsets.only(bottom: Gap.xs),
      padding: const EdgeInsets.all(Gap.sm),
      onTap: () => _askAboutIssue(index, issue),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: Gap.xxs + 2),
              if (type.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.xxs + 2,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(15),
                      borderRadius: BorderRadius.circular(Radii.control - 6),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              Icon(
                Icons.chat_bubble_outline,
                size: 13,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 2),
              Text(
                '追问',
                style: TextStyle(
                  fontSize: AppFont.tag,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          // 原文划掉(红)→ 改后(绿):这对语义色以前写死 Colors.red[400] /
          // Colors.green[700],深色下亮度不对;现在随主题切换
          if (original.isNotEmpty)
            Text(
              original,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.dangerColor(context),
                decoration: TextDecoration.lineThrough,
              ),
            ),
          if (correction.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              correction,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.successColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: Gap.xxs + 2),
            Text(
              reason,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 批改设置弹层(v2.13):预设提示词 + 思考强度。
///
/// 为什么用底部弹层而不是新页面:设置只有两组,跳页面会打断
/// "拍照/输入 → 调设置 → 批改"的连续感;弹层关掉就回到原稿,草稿不丢。
///
/// 保存策略:两组合并成一个「保存」——用户改完提示词顺手换了档位,
/// 一次落盘;下滑关闭 = 放弃本次修改(页面只在返回 true 时刷新缓存)。
class _ReviewSettingsSheet extends StatefulWidget {
  final String initialPrompt;
  final String initialThinking;
  final String model;

  const _ReviewSettingsSheet({
    required this.initialPrompt,
    required this.initialThinking,
    required this.model,
  });

  @override
  State<_ReviewSettingsSheet> createState() => _ReviewSettingsSheetState();
}

class _ReviewSettingsSheetState extends State<_ReviewSettingsSheet> {
  late final TextEditingController _promptCtrl;
  late String _thinking;
  bool _saving = false;

  /// 保存失败就地提示(不弹 SnackBar:SnackBar 在弹层下面,会被盖住)
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController(text: widget.initialPrompt);
    _thinking = widget.initialThinking;
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  bool get _isDefaultPrompt =>
      _promptCtrl.text.trim() == WritingReviewSettings.defaultPrompt.trim();

  /// 恢复默认只改输入框,**不立刻落盘** —— 用户可能只是看看默认长什么样,
  /// 点「保存」才真正生效,和"取消不保存"的预期一致。
  void _restoreDefault() {
    _promptCtrl.text = WritingReviewSettings.defaultPrompt;
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final promptOk = await WritingReviewSettings.savePrompt(_promptCtrl.text);
    final thinkingOk = await WritingReviewSettings.setThinking(
      widget.model,
      _thinking,
    );
    if (!mounted) return;
    final ok = promptOk && thinkingOk;
    setState(() {
      _saving = false;
      _saveError = ok ? null : '保存失败，请重试';
    });
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final options = WritingReviewSettings.thinkingOptionsFor(widget.model);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Gap.page,
          Gap.xs,
          Gap.page,
          Gap.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽条:告诉用户这层可以下滑关掉(与追问抽屉同一套手势)
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Icon(Icons.tune, size: AppFont.heading, color: cs.primary),
                const SizedBox(width: Gap.xs),
                Text(
                  '批改设置',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Text(
              '批改时提示词会原样发给 AI。可以整段改，但请保留 JSON 字段要求，'
              '否则结果页无法展示分数、点评与修正全文。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: _promptCtrl,
              minLines: 8,
              maxLines: 16,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: AppFont.meta,
                height: 1.5,
                color: cs.onSurface,
              ),
              decoration: InputDecoration(
                labelText: '预设批改提示词',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(Gap.sm),
                helperText: _isDefaultPrompt
                    ? '当前为默认提示词'
                    : '当前为自定义提示词（留空保存 = 恢复默认）',
              ),
            ),
            // 放在输入框下方而不是标题行:大字号下标题行放两个按钮会挤爆;
            // 始终可点 —— 输入框被清空时也要能一键填回默认提示词,
            // 点它只改输入框,落盘仍由底部「保存」决定
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _restoreDefault,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('恢复默认'),
              ),
            ),
            const SizedBox(height: Gap.xxs),
            Text(
              '直接批改手写图时，系统会在末尾自动追加“先识别手写内容、返回 transcript”的要求，'
              '这部分不用自己写。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Text(
                  '思考强度',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Text(
                    widget.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xxs),
            Text(
              '档位随批改模型变化；档位越高，模型想得越久，适合长文与复杂语法。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: Gap.xs),
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              children: [
                for (final e in options.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _thinking == e.key,
                    onSelected: (_) => setState(() => _thinking = e.key),
                  ),
              ],
            ),
            const SizedBox(height: Gap.xxs),
            Text(
              '只影响「AI 批改」这一步；「先转电子档」仍走快速识别，不会变慢。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: Gap.lg),
            if (_saveError != null) ...[
              Text(
                _saveError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: Gap.xs),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    // 保存是本地 Hive 写入,毫秒级;这里不做转圈,
                    // 只禁用按钮 + 换文案,避免闪烁
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
