import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../config/constants.dart';
import '../../models/saved_session.dart';
import '../../models/vocabulary.dart';
import '../../providers/vocab_provider.dart';
import '../../services/api_endpoint.dart';
import '../../services/doubao_api.dart';
import 'widgets/word_list_tile.dart';
import 'widgets/ai_result_header.dart';
import 'widgets/word_detail_sheet.dart';
import 'widgets/fulltext_result_card.dart';
import 'widgets/category_picker.dart';
import 'widgets/sub_category_input.dart';

/// 流式处理阶段
enum _StreamPhase { connecting, streaming, results, error }

/// 展示模式
enum _DisplayMode { detailed, quick }

/// 追问对话消息
class _FollowUpMessage {
  final String role; // 'user' | 'ai'
  final String content;
  final String? reasoningText;
  final bool streaming; // AI 是否仍在生成
  /// 生成此消息的模型名(仅 AI 消息有值)。
  /// 头像/标签按消息自身的模型渲染——切槽位不改变历史气泡;
  /// null = 旧版本数据,渲染时回退当前模型。
  final String? model;

  const _FollowUpMessage({
    required this.role,
    required this.content,
    this.reasoningText,
    this.streaming = false,
    this.model,
  });

  _FollowUpMessage copyWith({
    String? content,
    String? reasoningText,
    bool? streaming,
  }) => _FollowUpMessage(
    role: role,
    content: content ?? this.content,
    reasoningText: reasoningText ?? this.reasoningText,
    streaming: streaming ?? this.streaming,
    model: model,
  );
}

/// 保存的追问对话
class _SavedConversation {
  final String id; // timestamp
  final String title; // 第一个用户问题
  final String dateLabel;
  final List<Map<String, dynamic>>
  messages; // [{role, content, reasoningText?}]

  const _SavedConversation({
    required this.id,
    required this.title,
    required this.dateLabel,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'dateLabel': dateLabel,
    'messages': messages,
  };

  factory _SavedConversation.fromJson(Map<String, dynamic> json) =>
      _SavedConversation(
        id: json['id'] as String,
        title: json['title'] as String,
        dateLabel: json['dateLabel'] as String,
        messages: (json['messages'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

/// 对话式 AI 识词结果页（流式版）
class ProcessChatScreen extends StatefulWidget {
  final List<File> imageFiles;
  final String? sourceBook;
  final String? sourcePage;
  final String
  analysisMode; // AppConstants.analysisModeMarked / analysisModeFullText
  /// 非空 = 恢复模式:跳过识别,直接还原会话的识别结果 + 追问消息
  final SavedSession? restoreSession;

  const ProcessChatScreen({
    super.key,
    required this.imageFiles,
    this.sourceBook,
    this.sourcePage,
    this.analysisMode = AppConstants.analysisModeMarked,
    this.restoreSession,
  });

  @override
  State<ProcessChatScreen> createState() => _ProcessChatScreenState();
}

class _ProcessChatScreenState extends State<ProcessChatScreen>
    with WidgetsBindingObserver {
  // ── 主屏流式状态 ──
  _StreamPhase _phase = _StreamPhase.connecting;
  String _reasoningText = '';
  String _contentText = '';
  String? _errorMessage;
  StreamSubscription<SseChunk>? _subscription;
  Timer? _firstByteTimer;
  bool _thinkingExpanded = false;

  // ── 结果 ──
  List<Vocabulary> _results = [];
  final Set<int> _selected = {};
  // 全文翻译结果
  List<Map<String, String>> _fullTextParagraphs = [];
  _DisplayMode _displayMode = _DisplayMode.detailed;
  int? _queryTargetIndex; // 详细模式：正在询问 AI 的词索引
  // 思考计时
  DateTime? _thinkingStartAt;
  int _thinkingSeconds = 0;
  Timer? _thinkingTimer; // 每秒刷新思考耗时显示

  // (2026-08-08 移除思考超时降级链路:reasoning_effort 生效后思考时长可控
  // ~3-25s,原降级是"等满阈值+重跑一次完整识别",总耗时反而巨长——
  // 思考模式直接等真实结果,Dio receiveTimeout 180s 兜底)

  // ── 当前配置（从 Hive 实时读） ──
  final DoubaoApiService _api = DoubaoApiService();
  // ── 滚动控制 ──
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _aiSectionKey = GlobalKey(debugLabel: 'ai_section');

  /// 多图分组锚点：imageIndex → GlobalKey，点击聊天栏图片跳转对应结果
  final Map<int, GlobalKey> _imageGroupKeys = {};

  String get _currentModel => _api.modelName;
  String get _currentThinking {
    final v = Hive.box(
      AppConstants.hiveBoxSettings,
    ).get(AppConstants.keyDoubaoThinking);
    return (v is String && v.isNotEmpty) ? v : 'disabled';
  }

  /// 追问当前槽位:'primary' / 'secondary'(Hive 持久化,默认主)
  String get _followUpSlot {
    final v = Hive.box(
      AppConstants.hiveBoxSettings,
    ).get(AppConstants.keyFollowUpSlot);
    return (v is String && v == 'secondary') ? 'secondary' : 'primary';
  }

  /// 追问当前使用的槽位配置(副未配置时回落到主)
  ApiEndpointConfig get _followUpEndpoint {
    if (_followUpSlot == 'secondary' &&
        ApiEndpointConfig.secondary.isConfigured) {
      return ApiEndpointConfig.secondary;
    }
    return ApiEndpointConfig.primary;
  }

  /// 追问当前显示的模型名(按槽位)
  String get _followUpModel => _followUpEndpoint.model;

  // ── 追问抽屉（ValueNotifier 确保跨路由更新） ──
  final ValueNotifier<List<_FollowUpMessage>> _followUpMessages = ValueNotifier(
    [],
  );
  final ValueNotifier<bool> _followUpLoading = ValueNotifier(false);

  /// 追问槽位切换通知:抽屉是独立路由,主屏 setState 不会重建它,
  /// 抽屉内的模型标签/AI 头像须监听此 notifier 才能跟随切换。
  final ValueNotifier<String> _followUpSlotNotifier = ValueNotifier('primary');
  final TextEditingController _followUpCtrl = TextEditingController();
  final FocusNode _followUpFocus = FocusNode();
  StreamSubscription<SseChunk>? _followUpSub;

  /// 发送新消息后待滚到底部（用户手动上滑浏览时不打扰,发送时强制跟随）
  bool _pendingFollowUpScroll = false;

  /// 本次会话是否有追问内容（用于退出时提示保存）
  bool _followUpDirty = false;

  /// 外部预设的追问上下文（来自"询问AI详解"），优先级高于自动构建
  String? _followUpContextOverride;

  /// 已保存的历史对话
  List<_SavedConversation> _savedConversations = [];

  // ── 追问持久化 Key ──
  static const _hiveKeySavedChats = 'saved_follow_up_chats';

  /// 全部图片（初始 = 进入页面时的图；追加识别时动态扩展）。
  /// 追加的图片继续识别,结果按来源图分 p1/p2/pn 组,不退出当前对话。
  late final List<File> _images;

  /// 本轮识别从第几张图开始（追加模式 = 上次的图片数；首次 = 0）
  int _streamStartIndex = 0;

  @override
  void initState() {
    super.initState();
    _images = [...widget.imageFiles];
    WidgetsBinding.instance.addObserver(this);
    _followUpSlotNotifier.value = _followUpSlot;
    _loadSavedConversations();
    if (widget.restoreSession != null) {
      _restoreSession(widget.restoreSession!);
    } else {
      _startStreaming();
    }
  }

  /// 恢复模式:还原会话快照(结果 + 全文翻译 + 追问消息),跳过识别。
  /// 追问消息原样进抽屉——满足"返回临时对话后追问记录不消失"。
  void _restoreSession(SavedSession s) {
    try {
      // 图片锚点按实际文件重建
      _imageGroupKeys.clear();
      for (int i = 0; i < _images.length; i++) {
        _imageGroupKeys[i] = GlobalKey(debugLabel: 'image_group_$i');
      }

      // 结果还原:照片副本丢失时置 null(分组标题仍显示,不崩)
      _results = s.results.map((m) {
        final v = Vocabulary.fromMap(m);
        final p = v.photoPath;
        if (p == null || p.isEmpty || !File(p).existsSync()) {
          return v.copyWith(photoPath: null);
        }
        return v;
      }).toList();
      // 恢复模式默认不选中(与识别完成一致,长按才选中)
      _selected.clear();

      _fullTextParagraphs = List<Map<String, String>>.from(
        s.fullTextParagraphs
            .map(
              (m) => {
                'original': m['original']?.toString() ?? '',
                'translation': m['translation']?.toString() ?? '',
              },
            )
            .where((m) => m['original']!.isNotEmpty),
      );

      _followUpMessages.value = s.followUpMessages
          .where((m) => m['content']?.toString().isNotEmpty ?? false)
          .map(
            (m) => _FollowUpMessage(
              role: m['role']?.toString() == 'user' ? 'user' : 'ai',
              content: m['content']?.toString() ?? '',
              reasoningText: m['reasoningText']?.toString(),
              model: m['model']?.toString(),
            ),
          )
          .toList();
      _followUpDirty = false;

      if (mounted) setState(() => _phase = _StreamPhase.results);
    } catch (e) {
      debugPrint('ReadFlow restoreSession error: $e');
      if (mounted) {
        setState(() {
          _phase = _StreamPhase.error;
          _errorMessage = '会话恢复失败，请重试。\n$e';
        });
      }
    }
  }

  // ═══════════════ 会话暂存 ═══════════════

  /// 暂存当前会话:结果 + 追问 + 图片副本 → Hive(最多 [AppConstants.maxSavedSessions] 条)
  Future<void> _saveSession() async {
    try {
      final now = DateTime.now();
      final id = now.millisecondsSinceEpoch.toString();

      // 图片复制到持久目录(系统可能清理缓存目录)
      final docsDir = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${docsDir.path}/sessions/$id');
      await sessionDir.create(recursive: true);
      final copyMap = <String, String>{};
      for (int i = 0; i < _images.length; i++) {
        final f = _images[i];
        if (!f.existsSync()) continue;
        final ext = f.path.split('.').last.toLowerCase();
        final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext)
            ? ext
            : 'jpg';
        final target = '${sessionDir.path}/img$i.$safeExt';
        try {
          await f.copy(target);
          copyMap[f.path] = target;
        } catch (e) {
          debugPrint('ReadFlow copy image $i error: $e');
        }
      }

      // photoPath 重写为持久副本;词来源仍以副本为准
      final results = _results
          .map((v) {
            final p = v.photoPath;
            if (p != null && copyMap.containsKey(p)) {
              return v.copyWith(photoPath: copyMap[p]);
            }
            return v;
          })
          .map((v) => v.toMap())
          .toList();

      final conv = SavedSession(
        id: id,
        createdAt: now,
        analysisMode: widget.analysisMode,
        sourceBook: widget.sourceBook,
        sourcePage: widget.sourcePage,
        results: results,
        fullTextParagraphs: _fullTextParagraphs,
        followUpMessages: _followUpMessages.value
            .where((m) => !m.streaming) // 跳过还在生成中的消息
            .map(
              (m) => {
                'role': m.role,
                'content': m.content,
                if (m.reasoningText != null) 'reasoningText': m.reasoningText,
                if (m.model != null) 'model': m.model,
              },
            )
            .toList(),
      );

      final box = Hive.box(AppConstants.hiveBoxSettings);
      final raw = box.get(AppConstants.keySavedSessions) as List? ?? [];
      // Hive 读回的嵌套 Map 是 _Map<dynamic, dynamic>,
      // 不能直接 as Map<String, dynamic>(运行时强转失败)——必须 .from 重建
      final list = raw
          .map((e) => SavedSession.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      list.insert(0, conv);
      while (list.length > AppConstants.maxSavedSessions) {
        list.removeLast();
      }
      await box.put(
        AppConstants.keySavedSessions,
        list.map((e) => e.toJson()).toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('会话已暂存，可在「输入」页继续查看'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('ReadFlow saveSession error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('暂存失败：$e')));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _firstByteTimer?.cancel();
    _thinkingTimer?.cancel();
    _followUpSub?.cancel();
    _followUpCtrl.dispose();
    _followUpFocus.dispose();
    _followUpMessages.dispose();
    _followUpLoading.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ═══════════════ 应用生命周期 ═══════════════
  // 后台不打断 SSE 流；回前台时若已断连则静默重试

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回前台时若流已因网络断连而报错，自动静默重试
      if (_phase == _StreamPhase.error && mounted) {
        final msg = _errorMessage ?? '';
        if (msg.contains('超时') ||
            msg.contains('连接') ||
            msg.contains('网络') ||
            msg.contains('Socket') ||
            msg.contains('Connection')) {
          _retry();
        }
        return;
      }
      // 识别中切后台:系统可能挂起网络导致流静默中断(订阅已结束
      // 但没进 error 态)——回前台自动重试,不让用户手动点
      if (mounted &&
          (_phase == _StreamPhase.connecting ||
              _phase == _StreamPhase.streaming) &&
          _subscription == null) {
        debugPrint('ReadFlow: 识别流被后台中断,回前台自动重试');
        _retry();
      }
    }
  }

  // ═══════════════ 主屏流式 ═══════════════

  void _startStreaming() {
    _firstByteTimer?.cancel();
    final thinking = _currentThinking;
    // 首字节超时(只报错,不降级重跑):不思考25s;思考模式60s——
    // reasoning_effort 生效后(2026-08-07 实测低≈3s/中≈14s/高≈25s)
    // 思考模式直接等真实结果,Dio receiveTimeout 180s 是最终兜底。
    // 到点仍未收到任何字节(连 reasoning 都不吐)判定模型空回复,报错让用户重试
    final timeoutSeconds = thinking == 'disabled' ? 25 : 60;
    _firstByteTimer = Timer(Duration(seconds: timeoutSeconds), () {
      if (mounted && _phase == _StreamPhase.connecting) {
        _subscription?.cancel();
        setState(() {
          _phase = _StreamPhase.error;
          _errorMessage =
              '等待超时：${timeoutSeconds}秒未收到AI响应。\n'
              '可能原因：① 模型速度慢，建议切换更快的模型 ② 图片过大 ③ 网络不稳定';
        });
      }
    });

    try {
      // 追加模式:只识别新追加的图片(旧结果保留,AI 对新图从 0 编号)
      final images = _streamStartIndex == 0
          ? _images
          : _images.sublist(_streamStartIndex);
      final stream = _api.extractVocabularyStream(
        images,
        sourceBook: widget.sourceBook,
        sourcePage: widget.sourcePage,
        analysisMode: widget.analysisMode,
      );

      _subscription = stream.listen(
        (chunk) {
          _firstByteTimer?.cancel();
          if (!mounted) return;

          if (chunk.isReasoning) {
            // 累积推理文字 + 计时
            if (_thinkingStartAt == null) {
              _thinkingStartAt = DateTime.now();
              _thinkingTimer?.cancel();
              _thinkingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
                if (mounted && _thinkingStartAt != null) {
                  setState(() {
                    _thinkingSeconds = DateTime.now()
                        .difference(_thinkingStartAt!)
                        .inSeconds;
                  });
                }
              });
            }
            _reasoningText += chunk.text;
          } else {
            // 收到 content → 停止思考计时
            if (_thinkingStartAt != null) {
              _thinkingTimer?.cancel();
              _thinkingSeconds = DateTime.now()
                  .difference(_thinkingStartAt!)
                  .inSeconds;
            }
            setState(() {
              _contentText += chunk.text;
              if (_phase == _StreamPhase.connecting) {
                _phase = _StreamPhase.streaming;
              }
            });
            _scrollToBottom();
            return;
          }

          setState(() {
            if (_phase == _StreamPhase.connecting) {
              _phase = _StreamPhase.streaming;
            }
          });
          _scrollToBottom();
        },
        onDone: _onStreamDone,
        onError: (e) {
          _firstByteTimer?.cancel();
          _thinkingTimer?.cancel();
          _subscription = null; // 流已断,供回前台检测
          final msg = e.toString();
          String hint = msg;
          if (msg.contains('Connection timed out') || msg.contains('超时')) {
            hint = '网络连接超时，请检查网络或关闭VPN后重试';
          } else if (msg.contains('401') || msg.contains('403')) {
            hint = 'API Key 无效，请前往设置重新填写';
          } else if (msg.contains('404')) {
            hint = '模型不存在或无权限，请检查模型名称';
          }
          if (mounted) {
            setState(() {
              _phase = _StreamPhase.error;
              _errorMessage = hint;
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      _firstByteTimer?.cancel();
      if (mounted) {
        setState(() {
          _phase = _StreamPhase.error;
          _errorMessage = '启动识别失败：${e.toString()}';
        });
      }
    }
  }

  void _onStreamDone() {
    _firstByteTimer?.cancel();
    _subscription = null; // 流已结束,供回前台检测"静默中断"
    if (!mounted) return;
    // cancelOnError=false → onDone 在 onError 后也触发，避免覆盖错误信息
    if (_phase == _StreamPhase.error) return;

    try {
      final rawMaps = DoubaoApiService.parseResponse(
        _contentText,
        analysisMode: widget.analysisMode,
      );
      if (rawMaps.isEmpty) {
        final msg = widget.analysisMode == AppConstants.analysisModeFullText
            ? 'AI 未识别到可翻译的文字内容。'
            : 'AI 未识别到标记的单词，请确认图片中有标记痕迹。';
        setState(() {
          _phase = _StreamPhase.error;
          _errorMessage = msg;
        });
        return;
      }

      // 多图分组：为每张图片建锚点 GlobalKey
      _imageGroupKeys.clear();
      for (int i = 0; i < _images.length; i++) {
        _imageGroupKeys[i] = GlobalKey(debugLabel: 'image_group_$i');
      }

      if (widget.analysisMode == AppConstants.analysisModeFullText) {
        // 全文翻译结果：Map{original, translation}
        _fullTextParagraphs = rawMaps
            .map(
              (r) => {
                'original': r['original'] as String? ?? '',
                'translation': r['translation'] as String? ?? '',
              },
            )
            .where((m) => m['original']!.isNotEmpty)
            .toList();
        setState(() {
          _phase = _StreamPhase.results;
        });
      } else {
        // 圈画模式结果 — 多图时按 image_index 映射正确的 photoPath。
        // 追加模式:AI 对"本轮新图"从 0 编号,加 _streamStartIndex 映射回全局
        final results = rawMaps.map((r) {
          final imgIdx = (r['image_index'] as int? ?? 0) + _streamStartIndex;
          final photoPath = imgIdx >= 0 && imgIdx < _images.length
              ? _images[imgIdx].path
              : _images.last.path;
          return Vocabulary(
            word: r['word'] as String,
            translation: r['translation'] as String?,
            sourceBook: widget.sourceBook,
            sourcePage: widget.sourcePage,
            originalSentence: r['original_sentence'] as String?,
            photoPath: photoPath,
            wordType: (r['word_type'] as String?) ?? 'word',
            partOfSpeech: r['part_of_speech'] as String?,
            grammarNote: r['grammar_note'] as String?,
          );
        }).toList();

        setState(() {
          _phase = _StreamPhase.results;
          if (_streamStartIndex == 0) {
            // 首次识别:整组替换,默认不选中(长按才选中)
            _results = results;
            _selected.clear();
          } else {
            // 追加识别:新结果接在旧结果后;新词默认不选中,旧选中保留
            _results = [..._results, ...results];
          }
          _streamStartIndex = 0; // 本轮结束复位,下次从头开始
        });
      }
      // 滚动到 AI 结果区域顶部
      _scrollToAiSection();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _StreamPhase.error;
        _errorMessage = 'AI 返回内容解析失败，请重试。\n${e.toString()}';
      });
    }
  }

  void _retry() {
    _subscription?.cancel();
    _thinkingTimer?.cancel();
    _streamStartIndex = 0; // 重试 = 全新识别
    setState(() {
      _phase = _StreamPhase.connecting;
      _reasoningText = '';
      _contentText = '';
      _thinkingExpanded = false;
      _thinkingStartAt = null;
      _thinkingSeconds = 0;
      _errorMessage = null;
      _queryTargetIndex = null;
    });
    _startStreaming();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 流完成时滚动到 AI 结果区顶部（而非底部，防止越过头）
  void _scrollToAiSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _aiSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0, // 顶部对齐
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 点击聊天栏图片 → 滚动到对应分组的识别结果
  void _scrollToImageGroup(int imageIndex) {
    final key = _imageGroupKeys[imageIndex];
    if (key == null || !_scrollCtrl.hasClients) return;
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ═══════════════ 追问持久化 ═══════════════

  /// 从 Hive 加载已保存的历史对话
  void _loadSavedConversations() {
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final raw = box.get(_hiveKeySavedChats);
      if (raw is List) {
        _savedConversations = raw
            .map(
              (e) => _SavedConversation.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
    } catch (_) {
      _savedConversations = [];
    }
  }

  /// 保存当前追问到 Hive
  Future<void> _saveFollowUpConversation() async {
    final msgs = _followUpMessages.value;
    if (msgs.isEmpty) return;
    final now = DateTime.now();
    final firstUserMsg =
        msgs.where((m) => m.role == 'user').firstOrNull?.content ?? '';
    final title = firstUserMsg.isNotEmpty
        ? (firstUserMsg.length > 30
              ? '${firstUserMsg.substring(0, 30)}…'
              : firstUserMsg)
        : '追问记录';
    final conv = _SavedConversation(
      id: now.millisecondsSinceEpoch.toString(),
      title: title.length > 30 ? '${title.substring(0, 30)}…' : title,
      dateLabel:
          '${now.month}月${now.day}日 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      messages: msgs
          .where((m) => !m.streaming) // 跳过还在流式生成中的 AI 消息
          .map(
            (m) => {
              'role': m.role,
              'content': m.content,
              if (m.reasoningText != null) 'reasoningText': m.reasoningText,
              if (m.model != null) 'model': m.model,
            },
          )
          .toList(),
    );
    _savedConversations.insert(0, conv);
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.put(
        _hiveKeySavedChats,
        _savedConversations.map((c) => c.toJson()).toList(),
      );
      _followUpDirty = false; // 保存成功才清 dirty flag
    } catch (e) {
      debugPrint('ReadFlow saveFollowUp error: $e');
    }
  }

  /// 加载历史对话到当前追问抽屉
  void _loadFollowUpConversation(_SavedConversation conv) {
    _followUpMessages.value = conv.messages
        .map(
          (m) => _FollowUpMessage(
            role: m['role'] as String,
            content: m['content'] as String,
            reasoningText: m['reasoningText'] as String?,
            model: m['model'] as String?,
          ),
        )
        .toList();
    _followUpDirty = false;
  }

  /// 历史对话选择器
  void _showHistoryPicker() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    '历史追问',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      _savedConversations.clear();
                      Hive.box(
                        AppConstants.hiveBoxSettings,
                      ).delete(_hiveKeySavedChats);
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      '清空全部',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
            if (_savedConversations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('暂无保存的对话', style: TextStyle(color: Colors.grey)),
              )
            else
              ...List.generate(_savedConversations.length, (i) {
                final conv = _savedConversations[i];
                return ListTile(
                  title: Text(
                    conv.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    conv.dateLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      _savedConversations.removeAt(i);
                      Hive.box(AppConstants.hiveBoxSettings).put(
                        _hiveKeySavedChats,
                        _savedConversations.map((c) => c.toJson()).toList(),
                      );
                      Navigator.pop(ctx);
                    },
                  ),
                  onTap: () {
                    Navigator.pop(ctx); // 关历史面板
                    _loadFollowUpConversation(conv);
                  },
                );
              }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 退出确认：有识别结果或未保存追问时弹窗询问。
  /// 「暂时离开」= 暂存整个会话(结果+追问+图片副本)后退出,
  /// 下次从「输入」页"继续上次会话"恢复。
  /// 2026-08-09 修复:v1.2.10 起默认不选中,旧条件(须有选中词)导致
  /// 返回弹窗永不出现——改为只要有识别结果就弹,未选中时提供"保存全部"。
  Future<bool> _onWillPop() async {
    // 先处理识别结果保存确认
    if (_phase == _StreamPhase.results && _results.isNotEmpty) {
      final hasSel = _selected.isNotEmpty;
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('保存识别的生词？'),
          content: Text(
            hasSel
                ? '你选中了 ${_selected.length} 个词，是否保存到词库？'
                : '识别出 ${_results.length} 个词（未选中），是否全部保存到词库？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'temporary'),
              child: const Text('暂时离开'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('不保存'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: Text(hasSel ? '保存并退出' : '保存全部'),
            ),
          ],
        ),
      );
      if (result == 'save') {
        await _saveAndReturn(saveAll: !hasSel);
        return false; // _saveAndReturn 已 pop
      }
      if (result == 'temporary') {
        // 暂存含追问消息,直接退出;暂存失败不阻断退出(会话仍在,
        // 只是丢了快照)——返回 true 继续退
        await _saveSession();
        return true;
      }
      if (result == 'cancel') return false; // 不退出
      // discard: 不保存，继续退出
    }

    // 追问对话保存确认
    if (_followUpDirty && _followUpMessages.value.isNotEmpty) {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('保存追问对话？'),
          content: const Text('你在本次会话中有追问对话记录，是否保存以便下次查看？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'temporary'),
              child: const Text('暂时离开'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('不保存'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (result == 'temporary') {
        // 暂存整个会话(含追问)后退出
        await _saveSession();
        return true;
      }
      if (result == 'save') {
        await _saveFollowUpConversation();
      }
    }
    return true; // 允许退出
  }

  // ═══════════════ 保存 ═══════════════

  Future<void> _saveAndReturn({bool saveAll = false}) async {
    // saveAll=true:未选中任何词时从返回弹窗"保存全部"进入,保存所有结果
    final selected = (saveAll
            ? List.generate(_results.length, (i) => i)
            : _selected)
        .map((i) => _results[i])
        .toList();
    if (selected.isEmpty) return;

    // 1. 弹出分类选择
    final category = await showCategoryPicker(context);
    if (category == null || !mounted) return; // 用户取消

    // 2. 弹出子分类输入（可跳过）
    final subInfo = await showSubCategoryInput(
      context,
      category: category,
      prefill: widget.sourceBook ?? '',
    );
    if (!mounted) return;

    try {
      final categorized = selected.map((v) {
        return v.copyWith(
          category: category,
          materialPath: subInfo?.materialPath,
          sourceBook: subInfo?.materialName ?? v.sourceBook,
        );
      }).toList();
      await context.read<VocabProvider>().saveVocabularies(categorized);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  // ═══════════════ 追问抽屉 ═══════════════

  void _openFollowUp({String? prefillQuestion, String? followUpContext}) {
    _followUpCtrl.clear();
    if (prefillQuestion != null) {
      _followUpCtrl.text = prefillQuestion;
    }
    if (followUpContext != null) {
      _followUpContextOverride = followUpContext;
    } else {
      _followUpContextOverride = null;
    }
    final bottomSafe = MediaQuery.of(this.context).padding.bottom;
    showModalBottomSheet(
      context: this.context,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + bottomSafe,
        ),
        child: _buildFollowUpSheet(ctx),
      ),
    );
  }

  Widget _buildFollowUpSheet(BuildContext sheetCtx) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Column(
          children: [
            // ── 拖拽条 ──
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── 标题栏 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 18,
                    color: Color(0xFF4A90D9),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '追问对话',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  // 模型/思考选择器（紧凑，与底部栏同步）
                  _buildCompactModelPicker(),
                  // 新对话按钮
                  if (_followUpMessages.value.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _followUpMessages.value = [];
                        _followUpDirty = false;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '新建',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[400],
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  // 历史对话按钮
                  if (_savedConversations.isNotEmpty)
                    GestureDetector(
                      onTap: () => _showHistoryPicker(),
                      child: Icon(
                        Icons.history,
                        size: 18,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            // ── 消息列表（ValueListenableBuilder 确保流式更新） ──
            Expanded(
              child: ValueListenableBuilder<List<_FollowUpMessage>>(
                valueListenable: _followUpMessages,
                builder: (ctx, msgs, child) {
                  if (msgs.isEmpty) {
                    return Center(
                      child: Text(
                        '输入问题，AI 将基于图片内容回答',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    );
                  }
                  // 流式更新/新消息时自动跟随到底部:
                  // 发送消息强制跳底(平滑);流式更新时若在底部附近则瞬时
                  // 跟随(jumpTo——animateTo 动画在频繁更新时跟不上,
                  // 表现为"楼层高了不跳");用户手动上滑浏览历史不被拉回
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!scrollCtrl.hasClients) return;
                    final pos = scrollCtrl.position;
                    final nearBottom =
                        pos.maxScrollExtent - pos.pixels < 150;
                    if (_pendingFollowUpScroll || nearBottom) {
                      _pendingFollowUpScroll = false;
                      if (pos.maxScrollExtent > 0) {
                        if (nearBottom) {
                          scrollCtrl.jumpTo(pos.maxScrollExtent);
                        } else {
                          scrollCtrl.animateTo(
                            pos.maxScrollExtent,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        }
                      }
                    }
                  });
                  return Stack(
                    children: [
                      ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: msgs.length,
                        itemBuilder: (_, i) => _buildFollowUpBubble(msgs[i]),
                      ),
                      // 回顶/回底小按钮（楼层高时方便跳转）
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: _FollowUpScrollButtons(scrollCtrl: scrollCtrl),
                      ),
                    ],
                  );
                },
              ),
            ),
            // ── 输入栏（StatefulBuilder 确保输入状态本地更新） ──
            StatefulBuilder(
              builder: (ctx, setLocalState) {
                final hasText = _followUpCtrl.text.isNotEmpty;
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _followUpCtrl,
                            focusNode: _followUpFocus,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: '基于图片内容提问…',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              suffixIcon: hasText
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _followUpCtrl.clear();
                                        setLocalState(() {});
                                      },
                                    )
                                  : null,
                            ),
                            onChanged: (_) => setLocalState(() {}),
                            onSubmitted: (v) {
                              if (v.trim().isEmpty || _followUpLoading.value)
                                return;
                              _sendFollowUp(v.trim());
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 生成中显示红色停止按钮——AI 卡住时可主动打断,
                        // 打断后保留已生成内容,可重新提问
                        ValueListenableBuilder<bool>(
                          valueListenable: _followUpLoading,
                          builder: (ctx, loading, _) {
                            if (loading) {
                              return IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red[400],
                                ),
                                onPressed: _stopFollowUp,
                                tooltip: '停止生成',
                                icon: const Icon(Icons.stop, size: 18),
                              );
                            }
                            return IconButton.filled(
                              onPressed: !hasText
                                  ? null
                                  : () => _sendFollowUp(
                                      _followUpCtrl.text.trim(),
                                    ),
                              icon: const Icon(Icons.send, size: 18),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _sendFollowUp(String text) {
    if (text.isEmpty) return;
    final userMsg = _FollowUpMessage(role: 'user', content: text);
    // 捕获发送时实际生效的模型(副槽位未配置会回落到主)——该楼回复就记它
    final aiMsg = _FollowUpMessage(
      role: 'ai',
      content: '',
      streaming: true,
      model: _followUpModel,
    );

    _followUpMessages.value = [..._followUpMessages.value, userMsg, aiMsg];
    _followUpCtrl.clear();
    _followUpLoading.value = true;
    _followUpDirty = true;
    _pendingFollowUpScroll = true; // 发送后强制滚动到最新消息

    _doFollowUpStream(text, _followUpMessages.value.length - 1);
  }

  /// 用户手动停止生成:取消流式订阅,当前 AI 消息保留已生成内容。
  /// 停止后 _followUpLoading 置 false,输入框恢复可重新提问。
  void _stopFollowUp() {
    _followUpSub?.cancel();
    _followUpSub = null;
    final msgs = List<_FollowUpMessage>.from(_followUpMessages.value);
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == 'ai' && msgs[i].streaming) {
        msgs[i] = _FollowUpMessage(
          role: 'ai',
          content: msgs[i].content.isEmpty ? '（已停止生成）' : msgs[i].content,
          reasoningText: msgs[i].reasoningText,
          streaming: false,
          model: msgs[i].model,
        );
        break;
      }
    }
    _followUpMessages.value = msgs;
    _followUpLoading.value = false;
  }

  Future<void> _doFollowUpStream(String question, int aiMsgIndex) async {
    _followUpSub?.cancel();
    String reasoning = '';
    String content = '';

    String finalContext;
    if (_followUpContextOverride != null) {
      finalContext = _followUpContextOverride!;
      _followUpContextOverride = null; // 一次性消费
    } else {
      final ctx = StringBuffer();
      if (_results.isNotEmpty) {
        ctx.writeln('已识别的词汇：');
        for (final v in _results) {
          ctx.writeln('- ${v.word}: ${v.translation ?? ""} (${v.wordType})');
        }
      }
      finalContext = ctx.toString();
    }

    void updateMsg({bool done = false}) {
      final msgs = List<_FollowUpMessage>.from(_followUpMessages.value);
      if (aiMsgIndex < msgs.length) {
        msgs[aiMsgIndex] = _FollowUpMessage(
          role: 'ai',
          content: done
              ? (content.isNotEmpty ? content : '（AI 未返回内容）')
              : content,
          reasoningText: reasoning.isNotEmpty ? reasoning : null,
          streaming: !done,
          model: msgs[aiMsgIndex].model, // 保留发送时捕获的模型
        );
        _followUpMessages.value = msgs;
      }
      if (done) _followUpLoading.value = false;
    }

    try {
      final stream = _api.followUpStream(
        question,
        context: finalContext,
        endpoint: _followUpEndpoint,
      );

      _followUpSub = stream.listen(
        (chunk) {
          if (!mounted) return;
          if (chunk.isReasoning) {
            reasoning += chunk.text;
          } else {
            content += chunk.text;
          }
          updateMsg();
        },
        onDone: () {
          if (mounted) updateMsg(done: true);
        },
        onError: (e) {
          if (mounted) {
            // 保留已流式显示的内容，追加错误信息
            content = content.isNotEmpty
                ? '$content\n\n[错误] 请求失败：$e'
                : '请求失败：$e';
            updateMsg(done: true);
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (mounted) {
        content = '请求失败：$e';
        updateMsg(done: true);
      }
    }
  }

  Widget _buildFollowUpBubble(_FollowUpMessage msg) {
    final isUser = msg.role == 'user';

    if (!isUser) {
      return _AiFollowUpBubble(
        message: msg,
        avatar: _aiAvatar(radius: 14, modelName: msg.model ?? _followUpModel),
      );
    }

    // 用户气泡（右侧）
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4A90D9).withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                msg.content,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _userAvatar(radius: 14),
        ],
      ),
    );
  }


  // ═══════════════ Build ═══════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false, // 我们手动控制，先弹保存确认
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return; // 已经 pop 了
        try {
          final ok = await _onWillPop();
          if (ok && mounted) Navigator.of(context).pop(result);
        } catch (e) {
          debugPrint('ReadFlow onPopInvokedWithResult error: $e');
          if (mounted) Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_appBarTitle),
          actions: [
            // 暂存入口已移入返回确认弹窗的「暂时离开」——不再占用 AppBar
            if (_phase == _StreamPhase.results &&
                widget.analysisMode != AppConstants.analysisModeFullText) ...[
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: '全选/全不选',
                onPressed: () {
                  setState(() {
                    if (_selected.length == _results.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(
                        List.generate(_results.length, (i) => i),
                      );
                    }
                  });
                },
              ),
              // 选中操作（右上角，长按选中后出现）：
              // 取消选择 + 删除——一次清空所有选中,不用逐个长按取消
              if (_selected.isNotEmpty) ...[
                TextButton(
                  onPressed: () {
                    setState(() => _selected.clear());
                  },
                  child: Text(
                    '取消选择(${_selected.length})',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red[400]),
                  tooltip: '删除选中的 ${_selected.length} 个词汇',
                  onPressed: _deleteSelected,
                ),
              ],
              // 详细/总览切换 — 带中文标签，颜色跟随 AppBar 前景色
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    final wasDetailed = _displayMode == _DisplayMode.detailed;
                    _displayMode = wasDetailed
                        ? _DisplayMode.quick
                        : _DisplayMode.detailed;
                  });
                },
                icon: Icon(
                  _displayMode == _DisplayMode.detailed
                      ? Icons.view_agenda
                      : Icons.view_module,
                  size: 18,
                ),
                label: Text(
                  _displayMode == _DisplayMode.detailed ? '总览' : '详细',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            // ── 主屏内容 ──
            Expanded(
              child: ClipRect(
                clipBehavior: Clip.hardEdge,
                child: Stack(
                  children: [
                    ListView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      children: [
                        _buildUserBubble(theme),
                        const SizedBox(height: 16),
                        Container(
                          key: _aiSectionKey,
                          child: _buildAiSection(theme),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                    // ── 回到顶部浮动按钮（仅结果态显示） ──
                    if (_phase == _StreamPhase.results)
                      Positioned(
                        right: 12,
                        bottom: 8,
                        child: _ScrollToTopButton(scrollCtrl: _scrollCtrl),
                      ),
                  ],
                ),
              ), // ClipRect
            ),
            // "询问AI详解？" 浮动芯片 + 底部操作栏 — SafeArea 包裹防止系统导航栏遮挡
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_queryTargetIndex != null) _buildQueryChip(theme),
                  _buildBottomBar(theme),
                ],
              ),
            ),
          ],
        ), // Column
      ),
    ); // PopScope
  }

  String get _appBarTitle {
    switch (_phase) {
      case _StreamPhase.connecting:
        return '正在连接...';
      case _StreamPhase.streaming:
        return widget.analysisMode == AppConstants.analysisModeFullText
            ? 'AI 翻译中...'
            : 'AI 识别中...';
      case _StreamPhase.results:
        return widget.analysisMode == AppConstants.analysisModeFullText
            ? '全文翻译'
            : '识别结果 (${_selected.length}/${_results.length})';
      case _StreamPhase.error:
        return widget.analysisMode == AppConstants.analysisModeFullText
            ? '翻译失败'
            : '识别失败';
    }
  }

  /// 详细模式下单击词汇后浮现的"询问AI详解？"芯片
  Widget _buildQueryChip(ThemeData theme) {
    if (_queryTargetIndex == null || _queryTargetIndex! >= _results.length) {
      return const SizedBox.shrink();
    }
    final word = _results[_queryTargetIndex!].word;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90D9).withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A90D9).withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90D9).withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology, size: 20, color: Color(0xFF4A90D9)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '询问 AI 详解 "$word"？',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF4A90D9).withAlpha(220),
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _queryTargetIndex = null),
            child: const Icon(Icons.close, size: 18, color: Color(0xFF4A90D9)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              _askAiAboutWord(_queryTargetIndex!);
              setState(() => _queryTargetIndex = null);
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: const Text('去问问', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 详细模式：将单词发送到追问抽屉，AI 待命不回复
  void _askAiAboutWord(int index) {
    if (index >= _results.length) return;
    final item = _results[index];
    // 预填追问上下文
    final ctx = StringBuffer();
    ctx.writeln('单词：${item.word}');
    if (item.translation != null && item.translation!.isNotEmpty) {
      ctx.writeln('释义：${item.translation}');
    }
    if (item.partOfSpeech != null && item.partOfSpeech!.isNotEmpty) {
      ctx.writeln('词性：${item.partOfSpeech}');
    }
    if (item.originalSentence != null && item.originalSentence!.isNotEmpty) {
      ctx.writeln('例句：${item.originalSentence}');
    }
    if (item.grammarNote != null && item.grammarNote!.isNotEmpty) {
      ctx.writeln('语法：${item.grammarNote}');
    }
    // 打开追问抽屉，预填问题但等用户发送
    _openFollowUp(
      prefillQuestion: '请详细解释 "${item.word}" 的用法',
      followUpContext: ctx.toString(),
    );
  }

  /// 追问抽屉专用的紧凑模型/思考选择器 — 主/副双槽位分组。
  /// 选主槽位模型 → 识图同款(多模态);选副槽位模型 → 专项文本(若已配置)。
  /// 包 ValueListenableBuilder:抽屉是独立路由,切换后标签文本须自行重建。
  Widget _buildCompactModelPicker() {
    return ValueListenableBuilder<String>(
      valueListenable: _followUpSlotNotifier,
      builder: (_, __, ___) => _buildCompactModelPickerInner(),
    );
  }

  Widget _buildCompactModelPickerInner() {
    final secConfigured = ApiEndpointConfig.secondary.isConfigured;
    final isSecondary = _followUpSlot == 'secondary' && secConfigured;
    // 副分组模型 = 已保存的副模型 + 内置清单(去重,保证当前值可选)
    final secModels = <String>{
      if (ApiEndpointConfig.secondary.model.isNotEmpty)
        ApiEndpointConfig.secondary.model,
      ...AppConstants.deepseekFallbackModels,
    }.toList();

    PopupMenuItem<String> groupTitle(String text) => PopupMenuItem(
      enabled: false,
      height: 24,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
        ),
      ),
    );

    return PopupMenuButton<String>(
      offset: const Offset(0, 200),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 420),
      itemBuilder: (_) => [
        // ── 主 API(多模态) ──
        groupTitle(isSecondary ? '主 API(多模态)' : '主 API'),
        ...DoubaoApiService.fallbackDoubaoModels.map((m) {
          final isSel = _followUpSlot == 'primary' && m == _followUpModel;
          return PopupMenuItem(
            value: 'primary:$m',
            height: 30,
            child: Text(
              m,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                color: isSel ? const Color(0xFF3D7A5C) : null,
              ),
            ),
          );
        }),
        // ── 副 API(专项文本,始终显示分组;未配置时禁用并引导去设置) ──
        const PopupMenuDivider(),
        groupTitle(secConfigured ? '副 API(专项文本)' : '副 API(专项文本 · 未配置)'),
        if (!secConfigured)
          const PopupMenuItem(
            enabled: false,
            height: 36,
            child: Text(
              '到「我的 → API 设置」填写副 API Key 后即可切换',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          )
        else
          ...secModels.map((m) {
            final isSel = _followUpSlot == 'secondary' && m == _followUpModel;
            return PopupMenuItem(
              value: 'secondary:$m',
              height: 30,
              child: Text(
                m,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                  color: isSel ? const Color(0xFF4A6CF7) : null,
                ),
              ),
            );
          }),
        const PopupMenuDivider(),
        // ── 思考模式(写入当前追问槽位) ──
        ...AppConstants.thinkingOptions.entries.map((e) {
          final isSel = e.key == _followUpEndpoint.thinking;
          return PopupMenuItem(
            value: 'think:${e.key}',
            height: 30,
            child: Row(
              children: [
                Icon(
                  isSel ? Icons.lightbulb : Icons.lightbulb_outline,
                  size: 12,
                  color: isSel ? Colors.orange : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                    color: isSel ? Colors.orange : null,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
      onSelected: (v) {
        // Hive put 同步写内存,Future 只是刷盘通知——UI 无需等磁盘,
        // 不 await 可避免测试 FakeAsync 挂起与真机刷盘卡顿
        final box = Hive.box(AppConstants.hiveBoxSettings);
        if (v.startsWith('primary:')) {
          box.put(AppConstants.keyDoubaoModel, v.substring(8));
          box.put(AppConstants.keyFollowUpSlot, 'primary');
        } else if (v.startsWith('secondary:')) {
          // 'secondary:' 恰好 10 字符——之前 substring(11) 会吃掉模型名首字母
          box.put(AppConstants.keyDeepseekModel, v.substring(10));
          box.put(AppConstants.keyFollowUpSlot, 'secondary');
        } else if (v.startsWith('think:')) {
          // 思考模式写入当前追问槽位对应的 key
          final key = _followUpSlot == 'secondary'
              ? AppConstants.keyDeepseekThinking
              : AppConstants.keyDoubaoThinking;
          box.put(key, v.substring(6));
        }
        // 抽屉是独立路由,用 notifier 驱动头像/模型标签重建
        _followUpSlotNotifier.value = _followUpSlot;
        if (mounted) setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isSecondary ? '副·' : '主·',
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[400],
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              _followUpModel.length > 16
                  ? '${_followUpModel.substring(0, 16)}…'
                  : _followUpModel,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ═══════════════ 底部操作栏 ═══════════════

  Widget _buildBottomBar(ThemeData theme) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          // 模型 + 思考（弹出菜单）— flex=2
          Flexible(
            flex: 2,
            child: PopupMenuButton<String>(
              offset: const Offset(0, -360),
              padding: EdgeInsets.zero,
              itemBuilder: (_) => [
                ...DoubaoApiService.fallbackDoubaoModels.map((m) {
                  final isSel = m == _currentModel;
                  return PopupMenuItem(
                    value: 'model:$m',
                    height: 32,
                    child: Row(
                      children: [
                        if (isSel)
                          const Icon(
                            Icons.check,
                            size: 16,
                            color: Color(0xFF3D7A5C),
                          )
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            m,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSel
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isSel ? const Color(0xFF3D7A5C) : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const PopupMenuDivider(),
                ...AppConstants.thinkingOptions.entries.map((e) {
                  final isSel = e.key == _currentThinking;
                  return PopupMenuItem(
                    value: 'think:${e.key}',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(
                          isSel ? Icons.lightbulb : Icons.lightbulb_outline,
                          size: 14,
                          color: isSel ? Colors.orange : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSel
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSel ? Colors.orange : null,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onSelected: (v) async {
                if (v.startsWith('model:')) {
                  await Hive.box(
                    AppConstants.hiveBoxSettings,
                  ).put(AppConstants.keyDoubaoModel, v.substring(6));
                } else if (v.startsWith('think:')) {
                  await Hive.box(
                    AppConstants.hiveBoxSettings,
                  ).put(AppConstants.keyDoubaoThinking, v.substring(6));
                }
                if (mounted) setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.model_training,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        '模型',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_up,
                      size: 14,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // 保存词汇（C位）— flex=3，全文翻译模式下隐藏
          if (_phase == _StreamPhase.results &&
              widget.analysisMode != AppConstants.analysisModeFullText)
            Flexible(
              flex: 3,
              child: FilledButton.icon(
                onPressed: _selected.isEmpty ? null : _saveAndReturn,
                icon: const Icon(Icons.save, size: 16),
                label: Text(
                  '保存(${_selected.length})',
                  style: const TextStyle(fontSize: 13),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ),

          const SizedBox(width: 4),

          // 追问 — flex=2
          Flexible(
            flex: 2,
            child: ActionChip(
              avatar: Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: cs.primary,
              ),
              label: Text(
                '追问',
                style: TextStyle(fontSize: 12, color: cs.onSurface),
              ),
              onPressed: _openFollowUp,
              visualDensity: VisualDensity.compact,
              backgroundColor: cs.surface,
              side: BorderSide(color: cs.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════ 头像 ═══════════════

  Widget _userAvatar({double radius = 16}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Icon(Icons.person, size: radius * 1.1, color: Colors.white),
    );
  }

  /// AI 头像：品牌Logo（ClipOval + errorBuilder 兜底）。
  /// [modelName] 为空时用主槽位模型 —— 追问抽屉必须显式传
  /// 当前追问槽位的模型名，否则头像永远按主模型显示。
  Widget _aiAvatar({
    bool error = false,
    double radius = 16,
    String? modelName,
  }) {
    final name = modelName ?? _currentModel;
    final asset = _iconAssetFor(name);
    final color = error ? Colors.red[400]! : _colorFor(name);
    final double size = radius * 2;

    // 错误状态：红底 + 错误图标
    if (error) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: color,
        child: Icon(
          Icons.error_outline,
          size: radius * 1.0,
          color: Colors.white,
        ),
      );
    }

    // 有品牌 Logo 路径 → ClipOval + Image.asset（加载失败时 errorBuilder 兜底）
    if (asset != null) {
      return ClipOval(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, err, stack) =>
              _avatarFallback(radius, color, name),
        ),
      );
    }

    // 无品牌 Logo → 纯色 + 首字母
    return _avatarFallback(radius, color, name);
  }

  /// 品牌 Logo 加载失败或无品牌时的兜底：纯色圆 + 首字母
  Widget _avatarFallback(double radius, Color color, String modelName) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: _avatarText(radius, modelName),
    );
  }

  Widget _avatarText(double radius, String modelName) {
    final label = modelName.isNotEmpty ? modelName[0].toUpperCase() : 'AI';
    return Text(
      label,
      style: TextStyle(
        fontSize: radius * 0.85,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  String? _iconAssetFor(String modelName) {
    final m = modelName.toLowerCase();
    if (m.contains('doubao') || m.contains('seed') || m.contains('ark')) {
      return 'assets/icons/doubao-color.png';
    }
    if (m.contains('deepseek')) {
      return 'assets/icons/deepseek-color.png';
    }
    if (m.contains('gpt') || m.contains('openai')) {
      return 'assets/icons/openai.png';
    }
    if (m.contains('claude') || m.contains('anthropic')) {
      return 'assets/icons/claude-color.png';
    }
    if (m.contains('gemini')) {
      return 'assets/icons/gemini-color.png';
    }
    if (m.contains('qwen') || m.contains('tongyi')) {
      return 'assets/icons/qwen-color.png';
    }
    if (m.contains('glm') || m.contains('chatglm') || m.contains('zhipu')) {
      return 'assets/icons/zhipu-color.png';
    }
    if (m.contains('moonshot') || m.contains('kimi')) {
      return 'assets/icons/kimi-color.png';
    }
    if (m.contains('google')) {
      return 'assets/icons/google-color.png';
    }
    if (m.contains('iflytek') || m.contains('spark')) {
      return 'assets/icons/iflytekcloud-color.png';
    }
    return null;
  }

  Color _colorFor(String modelName) {
    final m = modelName.toLowerCase();
    if (m.contains('doubao') || m.contains('seed') || m.contains('ark'))
      return const Color(0xFF3D7A5C);
    if (m.contains('deepseek')) return const Color(0xFF4A6CF7);
    if (m.contains('gpt') || m.contains('openai'))
      return const Color(0xFF10A37F);
    if (m.contains('claude') || m.contains('anthropic'))
      return const Color(0xFFD97757);
    if (m.contains('gemini')) return const Color(0xFF4285F4);
    if (m.contains('qwen') || m.contains('tongyi'))
      return const Color(0xFF6B4CE6);
    if (m.contains('glm') || m.contains('zhipu'))
      return const Color(0xFF5B8DEF);
    if (m.contains('moonshot') || m.contains('kimi'))
      return const Color(0xFF8B5CF6);
    if (m.contains('baidu') || m.contains('ernie'))
      return const Color(0xFF2932E1);
    if (m.contains('google')) return const Color(0xFF4285F4);
    if (m.contains('iflytek') || m.contains('spark'))
      return const Color(0xFF1677FF);
    // 稳定兜底色
    final colors = const [
      Color(0xFFE53935),
      Color(0xFF43A047),
      Color(0xFF1E88E5),
      Color(0xFFFB8C00),
      Color(0xFF8E24AA),
      Color(0xFF00ACC1),
    ];
    var hash = 0;
    for (var i = 0; i < modelName.length; i++) {
      hash = modelName.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  // ═══════════════ 用户气泡 ═══════════════

  /// 追加图片继续识别:不退出当前对话,新图识别结果接在旧结果后,
  /// 按来源图分 p1/p2/pn 组,页码条可点击跳转
  Future<void> _addMoreImages() async {
    if (_phase != _StreamPhase.results) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (picked.isEmpty || !mounted) return;
    final newFiles = picked.map((x) => File(x.path)).toList();
    setState(() {
      _streamStartIndex = _images.length; // 从新图开始识别
      _images.addAll(newFiles);
      _phase = _StreamPhase.connecting;
      _reasoningText = '';
      _contentText = '';
      _thinkingStartAt = null;
      _thinkingSeconds = 0;
      _thinkingExpanded = false;
    });
    _startStreaming();
  }

  Widget _buildUserBubble(ThemeData theme) {
    final count = _images.length;
    final imgWidth = MediaQuery.of(context).size.width * 0.55;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 图片区域:无图片(副本丢失)时给占位提示,绝不渲染空 ListView —
              // 水平视口在无高度约束下会抛 "Horizontal viewport was given
              // unbounded height" 并级联炸掉整个 body(恢复会话时 imageFiles 可能为空)。
              if (count == 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '图片副本已丢失，仅恢复识别结果',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ),
              ] else ...[
                // 多图水平滚动
                SizedBox(
                  height: count > 1 ? 180 : null,
                  child: count == 1
                      ? GestureDetector(
                          onTap: _phase == _StreamPhase.results
                              ? () => _scrollToImageGroup(0)
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.file(
                              _images.first,
                              width: imgWidth,
                              fit: BoxFit.contain,
                            ),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: count,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: _phase == _StreamPhase.results
                                ? () => _scrollToImageGroup(i)
                                : null,
                            child: Container(
                              width: imgWidth,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Stack(
                                children: [
                                  Image.file(
                                    _images[i],
                                    width: imgWidth,
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'p${i + 1}/$count',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
              const SizedBox(height: 4),
              // 图片计数 + 追加图片按钮（结果态可点，独立一行不混排）
              Row(
                children: [
                  Text(
                    '共 $count 张图片',
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                  const Spacer(),
                  if (_phase == _StreamPhase.results &&
                      widget.analysisMode != AppConstants.analysisModeFullText)
                    GestureDetector(
                      onTap: _addMoreImages,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue[100]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add,
                              size: 13,
                              color: Colors.blue[600],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '追加图片',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              // 页码条：p1/p2/pn — 点击跳到对应图片的识别结果分组
              if (count > 1 && _phase == _StreamPhase.results)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(count, (i) {
                      return InkWell(
                        onTap: () => _scrollToImageGroup(i),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue[100]!),
                          ),
                          child: Text(
                            'p${i + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          children: [
            _userAvatar(),
            const SizedBox(height: 2),
            Text('我', style: TextStyle(fontSize: 9, color: Colors.grey[400])),
          ],
        ),
      ],
    );
  }

  // ═══════════════ AI 区域（阶段分发） ═══════════════

  Widget _buildAiSection(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            _aiAvatar(error: _phase == _StreamPhase.error),
            const SizedBox(height: 2),
            Text(
              _providerName,
              style: TextStyle(fontSize: 9, color: Colors.grey[400]),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Flexible(child: _buildAiContent(theme)),
      ],
    );
  }

  /// 模型厂商简称
  String get _providerName {
    final m = _currentModel.toLowerCase();
    if (m.contains('doubao') || m.contains('seed') || m.contains('ark'))
      return '豆包';
    if (m.contains('deepseek') || m.contains('ds')) return 'DeepSeek';
    if (m.contains('gpt') || m.contains('openai')) return 'OpenAI';
    if (m.contains('claude') || m.contains('anthropic')) return 'Claude';
    if (m.contains('gemini')) return 'Gemini';
    if (m.contains('qwen') || m.contains('tongyi')) return '通义';
    if (m.contains('glm') || m.contains('chatglm')) return '智谱';
    if (m.contains('moonshot') || m.contains('kimi')) return 'Kimi';
    return 'AI';
  }

  Widget _buildAiContent(ThemeData theme) {
    switch (_phase) {
      case _StreamPhase.connecting:
        return _buildConnectingContent(theme);
      case _StreamPhase.streaming:
        return _buildStreamingContent(theme);
      case _StreamPhase.results:
        if (widget.analysisMode == AppConstants.analysisModeFullText) {
          return _buildFullTextResults(theme);
        }
        return _buildResultsContent(theme);
      case _StreamPhase.error:
        return _buildErrorContent(theme);
    }
  }

  /// 全文翻译结果展示
  Widget _buildFullTextResults(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 思考过程
        if (_reasoningText.isNotEmpty) ...[
          _buildThinkingSection(),
          const SizedBox(height: 12),
        ],
        // 摘要
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF4A90D9).withAlpha(12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '翻译完成 · 共 ${_fullTextParagraphs.length} 个段落',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$_currentModel · ${AppConstants.thinkingOptions[_currentThinking] ?? "不思考"}',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 段落卡片
        ...List.generate(_fullTextParagraphs.length, (i) {
          final p = _fullTextParagraphs[i];
          return FulltextResultCard(
            index: i,
            original: p['original'] ?? '',
            translation: p['translation'] ?? '',
          );
        }),
      ],
    );
  }

  // ── 连接中 ──

  Widget _buildConnectingContent(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _thinkingDot(0),
              const SizedBox(width: 6),
              _thinkingDot(1),
              const SizedBox(width: 6),
              _thinkingDot(2),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'AI 正在识别图片中的标记内容…',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            '模型: $_currentModel',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _thinkingDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4A90D9).withAlpha((150 * value).toInt()),
            ),
          ),
        );
      },
    );
  }

  // ── 流式中 ──

  Widget _buildStreamingContent(ThemeData theme) {
    final hasReasoning = _reasoningText.isNotEmpty;
    final displayContent = _contentText.length > 2000
        ? '…${_contentText.substring(_contentText.length - 2000)}'
        : _contentText;

    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90D9).withAlpha(10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  hasReasoning
                      ? '思考中… $_thinkingSeconds秒'
                      : (_thinkingSeconds > 0
                            ? '正在生成… (思考耗时$_thinkingSeconds秒)'
                            : '正在生成…'),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
            // 思考过程（可折叠）
            if (hasReasoning) ...[
              const SizedBox(height: 8),
              _buildThinkingSection(),
              const SizedBox(height: 8),
              const Divider(height: 1),
            ],
            if (displayContent.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                displayContent,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _attributionLine(),
            const SizedBox(height: 8),
            // 取消按钮 — 模型思考太久时可中断
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  _subscription?.cancel();
                  _firstByteTimer?.cancel();
                  _thinkingTimer?.cancel();
                  if (mounted) {
                    setState(() {
                      _phase = _StreamPhase.error;
                      _errorMessage = _contentText.isNotEmpty
                          ? '已取消。当前已获取到部分内容，可返回重试。'
                          : '已取消。可返回或切换模型后重试。';
                    });
                  }
                },
                icon: const Icon(
                  Icons.stop_circle_outlined,
                  size: 16,
                  color: Colors.red,
                ),
                label: const Text(
                  '取消',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 结果 ──

  /// 详细模式卡片：展示完整解析（释义/词性/例句/语法）
  Widget _buildDetailTile(
    int index,
    Vocabulary item,
    bool isSel,
    ThemeData theme,
  ) {
    final cs = theme.colorScheme;
    final barColor = item.wordType == 'phrase'
        ? Colors.orange
        : item.wordType == 'sentence'
        ? Colors.purple
        : const Color(0xFF4A90D9);

    return GestureDetector(
      onTap: () => setState(() => _queryTargetIndex = index),
      onLongPress: () => setState(() {
        isSel ? _selected.remove(index) : _selected.add(index);
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSel ? cs.primary.withAlpha(8) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? barColor.withAlpha(80) : Colors.grey[200]!,
            width: isSel ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：序号 + 单词（横幅单行）+ ✏ 紧凑按钮
            Row(
              children: [
                // 序号徽章（第1个标1）
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: barColor.withAlpha(22),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: barColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 单词占满横幅;短语/句子完整呈现(一排显示不完第二排接着),
                // 只有单词类型单行省略。
                // 模型会把 phrase/sentence 的 word 词条化截断(实测输出开头
                // ~20 字符+"…"),originalSentence 字段才是完整句子——
                // 截断时回退用完整句子显示(2026-08-07 用户实测定位)
                Expanded(
                  child: Text(
                    _displayWord(item),
                    maxLines: item.wordType == 'word' ? 1 : null,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // 编辑按钮——右上角紧凑小按钮,不挤压单词空间
                InkWell(
                  onTap: () => _editItem(index),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 15,
                      color: Colors.grey[500],
                    ),
                  ),
                ),
              ],
            ),
            // 第二行：类型标签 + 词性
            if (item.wordType != 'word' ||
                (item.partOfSpeech != null &&
                    item.partOfSpeech!.isNotEmpty)) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _typeChip(item.wordType, barColor),
                  if (item.partOfSpeech != null &&
                      item.partOfSpeech!.isNotEmpty)
                    _typeChip(item.partOfSpeech!, Colors.grey[600]!),
                ],
              ),
            ],
            // 释义
            if (item.translation != null && item.translation!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.translation!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[800],
                ),
              ),
            ],
            // 例句
            if (item.originalSentence != null &&
                item.originalSentence!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.originalSentence!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  // 例句完整呈现,不省略
                ),
              ),
            ],
            // 语法
            if (item.grammarNote != null && item.grammarNote!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.grammarNote!,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
            // 底部提示
            const SizedBox(height: 4),
            Text(
              '点击询问 AI 详解 · 长按选中',
              style: TextStyle(fontSize: 10, color: Colors.grey[350]),
            ),
          ],
        ),
      ),
    );
  }

  /// 词条显示文本:模型会把 word 字段词条化截断(实测输出开头 ~20 字符
  /// +"…"),original_sentence 字段才是完整句子——word 以省略号结尾且
  /// 存在更长的完整句子时,回退显示完整句子。不区分类型:单词也可能被截。
  String _displayWord(Vocabulary item) {
    final w = item.word;
    if ((w.endsWith('…') || w.endsWith('...')) &&
        item.originalSentence != null &&
        item.originalSentence!.length > w.length) {
      return item.originalSentence!;
    }
    return w;
  }

  Widget _typeChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildResultsContent(ThemeData theme) {
    final words = _results.where((v) => v.wordType == 'word').length;
    final phrases = _results.where((v) => v.wordType == 'phrase').length;
    final sentences = _results.where((v) => v.wordType == 'sentence').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 思考过程
        if (_reasoningText.isNotEmpty) ...[
          _buildThinkingSection(),
          const SizedBox(height: 12),
        ],
        // 紧凑摘要头部
        AiResultHeader(
          totalCount: _results.length,
          wordCount: words,
          phraseCount: phrases,
          sentenceCount: sentences,
          modelName: _currentModel,
          thinkingLabel:
              AppConstants.thinkingOptions[_currentThinking] ?? '不思考',
        ),
        const SizedBox(height: 8),
        // 选中计数
        Text(
          '已选 ${_selected.length}/${_results.length}',
          style: TextStyle(fontSize: 11, color: Colors.grey[400]),
        ),
        const SizedBox(height: 4),
        // 词汇列表 — 多图时按来源图片分组
        if (_images.length > 1)
          ..._buildGroupedResults(theme)
        else
          ..._buildFlatResults(theme),
        const SizedBox(height: 4),
        // 手动添加词汇：AI 漏识别时用户自行补充
        Center(
          child: TextButton.icon(
            onPressed: _showAddWordDialog,
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text('添加词汇（AI 漏识别时手动补充）'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ),
        Center(
          child: Text(
            _displayMode == _DisplayMode.detailed
                ? '单击词汇 → AI 详解 | 长按选中'
                : '单击词汇 → 查看详情 | 长按选中',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }

  /// 单图时：扁平词汇列表
  List<Widget> _buildFlatResults(ThemeData theme) {
    return List.generate(_results.length, (i) {
      final item = _results[i];
      final isSel = _selected.contains(i);
      if (_displayMode == _DisplayMode.detailed) {
        return _buildDetailTile(i, item, isSel, theme);
      } else {
        return WordListTile(
          item: item,
          isSelected: isSel,
          index: i,
          onTap: () {
            showWordDetailSheet(
              context: context,
              item: item,
              onSave: () => _saveSingleItem(i),
              onEdit: () => _editItem(i),
              onRemove: () => setState(() => _selected.remove(i)),
            );
          },
          onLongPress: () {
            setState(() {
              isSel ? _selected.remove(i) : _selected.add(i);
            });
          },
        );
      }
    });
  }

  /// 多图时：按来源图片分组展示
  List<Widget> _buildGroupedResults(ThemeData theme) {
    // 按 photoPath 分组，保持原始顺序
    final groups = <String, List<int>>{};
    final order = <String>[];
    for (int i = 0; i < _results.length; i++) {
      final key = _results[i].photoPath ?? '';
      if (!groups.containsKey(key)) {
        groups[key] = [];
        order.add(key);
      }
      groups[key]!.add(i);
    }

    final widgets = <Widget>[];
    for (int g = 0; g < order.length; g++) {
      final key = order[g];
      final indices = groups[key]!;
      // 图源标题：找到对应的 image 索引；手动补充的词无照片来源，
      // 单独归入「手动补充」组
      final imgIndex = _images.indexWhere((f) => f.path == key);
      final String label;
      if (key.isEmpty) {
        label = '📝 手动补充';
      } else {
        // 页码标注 p1/p2/pn,与图片区页码条一致
        label = imgIndex >= 0
            ? 'p${imgIndex + 1} · 📷 图片 ${imgIndex + 1}'
            : '📷 图片 ${g + 1}';
      }
      final pageInfo =
          (widget.sourcePage != null && widget.sourcePage!.isNotEmpty)
          ? ' · 第${widget.sourcePage}页'
          : '';
      // 用对应图片的 GlobalKey 做锚点
      final anchorKey = imgIndex >= 0 ? _imageGroupKeys[imgIndex] : null;
      widgets.add(
        Padding(
          key: anchorKey,
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.image, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$label$pageInfo · ${indices.length}个词汇',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      // 该组内的词汇
      for (final i in indices) {
        final item = _results[i];
        final isSel = _selected.contains(i);
        if (_displayMode == _DisplayMode.detailed) {
          widgets.add(_buildDetailTile(i, item, isSel, theme));
        } else {
          widgets.add(
            WordListTile(
              item: item,
              isSelected: isSel,
              onTap: () {
                showWordDetailSheet(
                  context: context,
                  item: item,
                  onSave: () => _saveSingleItem(i),
                  onEdit: () => _editItem(i),
                  onRemove: () => setState(() => _selected.remove(i)),
                );
              },
              onLongPress: () {
                setState(() {
                  isSel ? _selected.remove(i) : _selected.add(i);
                });
              },
              index: i,
            ),
          );
        }
      }
    }
    return widgets;
  }

  /// 单独保存一个词
  Future<void> _saveSingleItem(int index) async {
    // 1. 弹出分类选择
    final category = await showCategoryPicker(context);
    if (category == null || !mounted) return;

    // 2. 弹出子分类输入（可跳过）
    final subInfo = await showSubCategoryInput(
      context,
      category: category,
      prefill: widget.sourceBook ?? '',
    );
    if (!mounted) return;

    try {
      final item = _results[index].copyWith(
        category: category,
        materialPath: subInfo?.materialPath,
        sourceBook: subInfo?.materialName ?? _results[index].sourceBook,
      );
      await context.read<VocabProvider>().saveVocabularies([item]);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已保存：${_results[index].word}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  // ── 可折叠思考过程（共用组件） ──

  Widget _buildThinkingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _thinkingExpanded = !_thinkingExpanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _thinkingExpanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: Colors.orange[300],
              ),
              const SizedBox(width: 4),
              Text(
                _thinkingSeconds > 0
                    ? '思考过程 · $_thinkingSeconds秒 · ${_reasoningText.length}字'
                    : '思考过程 (${_reasoningText.length}字)',
                style: TextStyle(fontSize: 11, color: Colors.orange[300]),
              ),
            ],
          ),
        ),
        if (_thinkingExpanded) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[100]!),
            ),
            child: SelectableText(
              _reasoningText.length > 1500
                  ? '…${_reasoningText.substring(_reasoningText.length - 1500)}'
                  : _reasoningText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.orange[800],
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── 错误 ──

  Widget _buildErrorContent(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            _errorMessage ?? '未知错误',
            style: TextStyle(fontSize: 13, color: Colors.red[700]),
          ),
          const SizedBox(height: 4),
          Text(
            '模型: $_currentModel',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[700],
                  side: BorderSide(color: Colors.red[300]!),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 归属标注 ──

  Widget _attributionLine() {
    return Text(
      '翻译释义由 $_providerName 大模型 ($_currentModel) 生成 · 仅供参考',
      style: TextStyle(fontSize: 10, color: Colors.grey[350]),
    );
  }

  void _editItem(int index) {
    final item = _results[index];
    final wordCtrl = TextEditingController(text: item.word);
    final transCtrl = TextEditingController(text: item.translation ?? '');
    final posCtrl = TextEditingController(text: item.partOfSpeech ?? '');
    final grammarCtrl = TextEditingController(text: item.grammarNote ?? '');
    final sentenceCtrl = TextEditingController(
      text: item.originalSentence ?? '',
    );

    void disposeAll() {
      wordCtrl.dispose();
      transCtrl.dispose();
      posCtrl.dispose();
      grammarCtrl.dispose();
      sentenceCtrl.dispose();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑生词'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordCtrl,
                decoration: const InputDecoration(labelText: '原文'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: transCtrl,
                decoration: const InputDecoration(labelText: '释义'),
              ),
              const SizedBox(height: 12),
              if (item.wordType == 'word') ...[
                TextField(
                  controller: posCtrl,
                  decoration: const InputDecoration(
                    labelText: '词性',
                    hintText: '如：名词 n.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (item.wordType != 'word') ...[
                TextField(
                  controller: grammarCtrl,
                  decoration: const InputDecoration(
                    labelText: '语法分析',
                    hintText: '如：固定搭配、从句结构',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: sentenceCtrl,
                decoration: const InputDecoration(labelText: '原文例句'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              // 修改原文后例句自动替换提示
              Text(
                '修改「原文」后，例句中的「${item.word.length > 12 ? '${item.word.substring(0, 12)}…' : item.word}」会自动替换为新词',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              disposeAll();
              Navigator.pop(ctx);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final wordText = wordCtrl.text.trim();
              if (wordText.isEmpty) {
                disposeAll();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('单词不能为空')));
                return;
              }
              // 例句中的旧词自动替换为新词（保留原句大小写形态），
              // 避免「hi is a boy」改成 he 后例句仍是 hi
              final newSentence = replaceWordInSentence(
                sentenceCtrl.text.trim().isEmpty
                    ? (item.originalSentence ?? '')
                    : sentenceCtrl.text.trim(),
                item.word,
                wordText,
              );
              setState(() {
                _results[index] = item.copyWith(
                  word: wordText,
                  translation: transCtrl.text.trim(),
                  partOfSpeech: posCtrl.text.trim().isEmpty
                      ? null
                      : posCtrl.text.trim(),
                  grammarNote: grammarCtrl.text.trim().isEmpty
                      ? null
                      : grammarCtrl.text.trim(),
                  originalSentence: newSentence.isEmpty
                      ? null
                      : newSentence,
                );
              });
              disposeAll();
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 删除长按选中的词汇（索引降序删除避免错位），确认后清空选中
  void _deleteSelected() {
    final n = _selected.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除选中词汇'),
        content: Text('确定删除选中的 $n 个词汇？\n删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                final toRemove = _selected.toSet();
                _results = [
                  for (int i = 0; i < _results.length; i++)
                    if (!toRemove.contains(i)) _results[i],
                ];
                _selected.clear();
                _queryTargetIndex = null;
              });
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
        ],
      ),
    );
  }

  /// 手动添加词汇：AI 漏识别时用户自行补充。
  /// 新词进入 _results 同一数据源——详细/总览/追问/选中/保存/暂存自动同步。
  void _showAddWordDialog() {
    final wordCtrl = TextEditingController();
    final transCtrl = TextEditingController();
    final posCtrl = TextEditingController();
    final sentenceCtrl = TextEditingController();

    void disposeAll() {
      wordCtrl.dispose();
      transCtrl.dispose();
      posCtrl.dispose();
      sentenceCtrl.dispose();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('添加词汇'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wordCtrl,
                decoration: const InputDecoration(
                  labelText: '单词/短语（必填）',
                  hintText: '如：unfettered',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: transCtrl,
                decoration: const InputDecoration(labelText: '释义'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: posCtrl,
                decoration: const InputDecoration(
                  labelText: '词性',
                  hintText: '如：形容词 adj.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sentenceCtrl,
                decoration: const InputDecoration(
                  labelText: '例句（可选）',
                  hintText: '如：The mind wants unfettered freedom.',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              disposeAll();
              Navigator.pop(ctx);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final wordText = wordCtrl.text.trim();
              if (wordText.isEmpty) {
                disposeAll();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('单词不能为空')),
                );
                return;
              }
              final sentence = sentenceCtrl.text.trim();
              setState(() {
                _results.add(
                  Vocabulary(
                    word: wordText,
                    translation: transCtrl.text.trim().isEmpty
                        ? null
                        : transCtrl.text.trim(),
                    partOfSpeech: posCtrl.text.trim().isEmpty
                        ? null
                        : posCtrl.text.trim(),
                    originalSentence: sentence.isEmpty ? null : sentence,
                    photoPath: null, // 手动补充的词无照片来源
                  ),
                );
              });
              disposeAll();
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}

/// 例句中把旧词替换为新词（保留原句大小写形态）：
/// 原文 "He is a hi boy" 改 hi→he 得 "He is a he boy"（首字母跟随原词大小写）。
/// 纯函数，可单测。
String replaceWordInSentence(
  String sentence,
  String oldWord,
  String newWord,
) {
  if (sentence.isEmpty ||
      oldWord.isEmpty ||
      newWord.isEmpty ||
      oldWord == newWord) {
    return sentence;
  }
  final re = RegExp('\\b${RegExp.escape(oldWord)}\\b', caseSensitive: false);
  return sentence.replaceAllMapped(re, (m) {
    final matched = m.group(0)!;
    final isUpper =
        matched.isNotEmpty && matched[0].toUpperCase() == matched[0];
    if (isUpper && newWord.isNotEmpty) {
      return newWord[0].toUpperCase() + newWord.substring(1);
    }
    return newWord;
  });
}

/// 回到顶部浮动小按钮 — 仅在结果态显示，点击后平滑滚动到顶部
/// 追问 AI 气泡:模型标签 + 可折叠思考过程 + Markdown 渲染正文。
/// 本地状态承载思考折叠——流式更新重建气泡时状态保留。
class _AiFollowUpBubble extends StatefulWidget {
  final _FollowUpMessage message;
  final Widget avatar;

  const _AiFollowUpBubble({
    required this.message,
    required this.avatar,
  });

  @override
  State<_AiFollowUpBubble> createState() => _AiFollowUpBubbleState();
}

class _AiFollowUpBubbleState extends State<_AiFollowUpBubble> {
  bool _thinkingExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.avatar,
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              // 宽气泡:充分利用抽屉横向空间,缓解 Markdown 表格换行错位
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.88,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 模型名标签
                  if (msg.model != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        msg.model!,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  // 思考过程（可折叠，标题条点击切换）
                  if (msg.reasoningText != null &&
                      msg.reasoningText!.isNotEmpty)
                    _ThinkingBlock(
                      text: msg.reasoningText!,
                      expanded: _thinkingExpanded,
                      streaming: msg.streaming,
                      onToggle: () => setState(
                        () => _thinkingExpanded = !_thinkingExpanded,
                      ),
                    ),
                  // 正文（Markdown 渲染：标题/加粗/表格/列表层级清晰）
                  if (msg.content.isNotEmpty)
                    MarkdownBody(
                      data: msg.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        theme,
                      ).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          height: 1.5,
                          color: Colors.grey[800],
                        ),
                        h1: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        h2: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        h3: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        strong: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        tableBorder: TableBorder.all(
                          color: Colors.grey.shade300,
                          width: 0.5,
                        ),
                        tableHead: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                        tableBody: TextStyle(fontSize: 12, height: 1.4),
                        tableCellsPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        blockquote: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                        code: TextStyle(
                          fontSize: 12,
                          color: Colors.deepOrange[700],
                          fontFamily: 'monospace',
                        ),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.grey[300]!, width: 1),
                          ),
                        ),
                      ),
                    )
                  else if (msg.streaming)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '正在思考…',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Text(
                      '（AI 未返回内容）',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 可折叠思考过程块：标题条点击切换展开/收起；展开时限制高度可滚动
class _ThinkingBlock extends StatelessWidget {
  final String text;
  final bool expanded;
  final bool streaming;
  final VoidCallback onToggle;

  const _ThinkingBlock({
    required this.text,
    required this.expanded,
    required this.streaming,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题条
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Text('💭', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(
                    streaming ? '思考过程（生成中）' : '思考过程',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.orange[600],
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange[400],
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 追问抽屉 回顶/回底 小按钮:监听滚动位置,↑ 未在顶部时显示,↓ 未到底时显示
class _FollowUpScrollButtons extends StatefulWidget {
  final ScrollController scrollCtrl;
  const _FollowUpScrollButtons({required this.scrollCtrl});

  @override
  State<_FollowUpScrollButtons> createState() => _FollowUpScrollButtonsState();
}

class _FollowUpScrollButtonsState extends State<_FollowUpScrollButtons> {
  double _offset = 0;
  double _maxExtent = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollCtrl.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final pos = widget.scrollCtrl.position;
    setState(() {
      _offset = pos.pixels;
      _maxExtent = pos.maxScrollExtent;
    });
  }

  @override
  Widget build(BuildContext context) {
    final atTop = _offset < 40;
    final atBottom = _maxExtent - _offset < 40;
    // 内容不满一屏时隐藏
    if (atTop && atBottom) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!atTop)
          _smallButton(Icons.keyboard_arrow_up, () {
            widget.scrollCtrl.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }),
        if (!atBottom) ...[
          const SizedBox(height: 4),
          _smallButton(Icons.keyboard_arrow_down, () {
            widget.scrollCtrl.animateTo(
              widget.scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }),
        ],
      ],
    );
  }

  Widget _smallButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: Colors.grey[600]),
        ),
      ),
    );
  }
}

class _ScrollToTopButton extends StatefulWidget {
  final ScrollController scrollCtrl;
  const _ScrollToTopButton({required this.scrollCtrl});

  @override
  State<_ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<_ScrollToTopButton> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollCtrl.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final show = widget.scrollCtrl.hasClients && widget.scrollCtrl.offset > 200;
    if (show != _visible && mounted) {
      setState(() => _visible = show);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: cs.primary,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          widget.scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.arrow_upward, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}
