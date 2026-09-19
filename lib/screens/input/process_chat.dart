import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/constants.dart';
import '../../models/saved_session.dart';
import '../../models/vocabulary.dart';
import '../../models/bookmark.dart';
import '../../providers/vocab_provider.dart';
import '../../providers/bookmark_provider.dart';
import '../../services/api_endpoint.dart';
import '../../services/base_api.dart';
import '../../services/doubao_api.dart';
import '../../services/tts_service.dart';
import '../../utils/follow_up_context.dart';
import '../../utils/supplement_merge.dart';
import 'widgets/word_list_tile.dart';
import 'widgets/ai_result_header.dart';
import 'widgets/word_detail_sheet.dart';
import 'widgets/fulltext_result_card.dart';
import 'widgets/category_picker.dart';
import 'widgets/sub_category_input.dart';
import 'widgets/example_sentence.dart';
import 'widgets/follow_up_models.dart';
import 'widgets/follow_up_drawer.dart';
import 'widgets/scroll_buttons.dart';
import 'widgets/model_avatars.dart';

/// 流式处理阶段
enum _StreamPhase { connecting, streaming, results, error }

/// 展示模式
enum _DisplayMode { detailed, quick }

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
  DateTime? _lastChunkAt; // 心跳:最后收到数据的时间,用于回前台静默中断检测

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

  /// 当前思考档位 = 配置层已校验的档位(单一事实来源)。
  /// v1.8.0 起**不再有"自动降级成不思考"**:用户选了什么档位就用什么档位,
  /// 思考模型只吐思考过程时改为"从思考内容里取结果 / 同档位重试"。
  String get _currentThinking => ApiEndpointConfig.primary.thinking;

  /// 本轮请求实际使用的思考档位(_onStreamDone 判断是否思考模式用)
  String _lastRequestThinking = 'disabled';

  /// reasoning-only 同档位重试守卫(避免无限重试;成功或用户手动重试时复位)
  bool _reasoningOnlyRetried = false;

  /// 内容被截断的同档位重试守卫
  bool _truncationRetried = false;

  /// 追问当前使用的槽位配置(副未配置时回落到主)。
  /// v1.6.0:整套追问逻辑抽到 FollowUpController(与写译批改共用),
  /// 这里只保留「AI 补全词汇」等本页需要的槽位访问。
  ApiEndpointConfig get _followUpEndpoint => _followUp.endpoint;

  /// 追问抽屉共享控制器(材料上下文 = 识别结果 / 全文翻译段落)
  late final FollowUpController _followUp;

  /// 全部图片（初始 = 进入页面时的图；追加识别时动态扩展）。
  /// 追加的图片继续识别,结果按来源图分 p1/p2/pn 组,不退出当前对话。
  late final List<File> _images;

  /// 本轮识别从第几张图开始（追加模式 = 上次的图片数；首次 = 0）
  int _streamStartIndex = 0;

  /// 补充识别模式(v1.3.0 问题 3):对全部图片重新识别,只并入遗漏项。
  /// 为 true 时 [_onStreamDone] 走去重合并分支,结束后复位。
  bool _supplementMode = false;

  /// 校准重识别模式(v1.7.0):用户对首次识别不满意时的"认真重做一遍"。
  /// 与补充识别的区别:校准会**整组替换**结果(不合并),并用逐行扫描 +
  /// 高清图 + 自检的强化提示词。为 true 时 [_onStreamDone] 走替换分支。
  bool _recalibrateMode = false;

  /// 全文翻译:每轮识别的段落起点(imageIndex → 段落下标)。
  /// 追加图片后点击 p1/p2 定位到该图第一段(v1.4.1 用户实测:
  /// 追加后点 p1/p2 永远停在追加结果上,没法回到第一张图)。
  final List<int> _fullTextGroupStarts = [];

  /// 全文翻译段落卡片锚点(与 _fullTextParagraphs 对齐)
  final List<GlobalKey> _fullTextCardKeys = [];

  @override
  void initState() {
    super.initState();
    _images = [...widget.imageFiles];
    WidgetsBinding.instance.addObserver(this);
    // 追问控制器:上下文取识别结果 + 全文翻译段落,支持视觉的模型可附原图
    _followUp = FollowUpController(
      buildContext: () =>
          buildFollowUpContext(results: _results, paragraphs: _fullTextParagraphs),
      imageFilesProvider: () => _images,
    );
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

      _followUp.messages.value = s.followUpMessages
          .where((m) => m['content']?.toString().isNotEmpty ?? false)
          .map(
            (m) => FollowUpMessage(
              role: m['role']?.toString() == 'user' ? 'user' : 'ai',
              content: m['content']?.toString() ?? '',
              reasoningText: m['reasoningText']?.toString(),
              model: m['model']?.toString(),
            ),
          )
          .toList();
      _followUp.dirty = false;

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
        followUpMessages: _followUp.messages.value
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
    _followUp.dispose();
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
            msg.contains('Receive timeout') || // Dio 接收超时原文
            msg.contains('连接') ||
            msg.contains('网络') ||
            msg.contains('Socket') ||
            msg.contains('Connection')) {
          _retry();
        }
        return;
      }
      // 识别中切后台:系统可能挂起网络导致流静默中断——
      // 流内没有 error/onDone 通知,只能用"最后收到数据的时间"心跳检测
      // (旧实现用 _subscription == null 判断,但订阅在 streaming 中永不为
      // null,该分支是死代码;改判 30s 无新 chunk)
      if (mounted &&
          _phase == _StreamPhase.streaming &&
          _lastChunkAt != null &&
          DateTime.now().difference(_lastChunkAt!) >
              const Duration(seconds: 30)) {
        debugPrint('ReadFlow: 识别流疑似静默中断(30s 无数据),回前台自动重试');
        _retry();
      }
    }
  }

  // ═══════════════ 主屏流式 ═══════════════

  void _startStreaming() {
    _firstByteTimer?.cancel();
    _lastChunkAt = null; // 新流开始,重置心跳
    final thinking = _currentThinking;
    _lastRequestThinking = thinking;
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
        // 补充识别:告知已有词,只找遗漏(v1.3.0 问题 3)
        excludeWords:
            _supplementMode ? _results.map((v) => v.word).toList() : const [],
        // 校准重识别:强化提示词 + 高清图(v1.7.0)
        calibrate: _recalibrateMode,
      );

      _subscription = stream.listen(
        (chunk) {
          _firstByteTimer?.cancel();
          _lastChunkAt = DateTime.now(); // 心跳更新
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
          String hint;
          if (msg.contains('Connection timed out') || msg.contains('超时')) {
            hint = '网络连接超时，请检查网络或关闭VPN后重试';
          } else {
            // v1.4.1:显示服务端真实错误(中文指引),不再一屏 DioException 英文
            hint = BaseApiService.friendlyError(e);
            // 特例:DS 视觉模型配在方舟端点下(旧配置残留)加强提示
            final m = _currentModel.toLowerCase();
            if ((msg.contains('401') || msg.contains('403')) &&
                m.contains('deepseek') &&
                m.contains('vision') &&
                !ApiEndpointConfig.primary.baseUrl.contains('deepseek.com')) {
              hint = '模型与端点不匹配：DeepSeek 视觉模型需搭配 '
                  'https://api.deepseek.com 和 DeepSeek 官方 Key（sk- 开头）。'
                  '现在 Base URL 留空即可自动配对，请到「我的 → API 设置」重新保存。';
            }
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
      _thinkingTimer?.cancel();
      _thinkingStartAt = null;
      if (mounted) {
        setState(() {
          _phase = _StreamPhase.error;
          _errorMessage = '启动识别失败：${e.toString()}';
        });
      }
    }
  }

  /// LLM 返回的 image_index 可能是 int/字符串/浮点(该模型族结构输出不可靠),
  /// 全量安全解析;解析失败按 0 处理,绝不抛 TypeError 毁掉整批识别。
  int _safeImageIndex(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  void _onStreamDone() {
    _firstByteTimer?.cancel();
    _thinkingTimer?.cancel(); // 思考计时在流结束/出错/重试都必须停,否则 setState 永转
    _thinkingStartAt = null;
    _subscription = null; // 流已结束,供回前台检测"静默中断"
    if (!mounted) return;
    // cancelOnError=false → onDone 在 onError 后也触发，避免覆盖错误信息
    if (_phase == _StreamPhase.error) return;

    // v1.8.0 根因修复(用户实测"思考一长就被强行砍成不思考"):
    // 思考模型有时把最终 JSON 直接写在 reasoning_content 里(content 空)。
    // 正确做法不是砍档位,而是**先把思考内容里的 JSON 取出来用**。
    if (_contentText.trim().isEmpty && _reasoningText.isNotEmpty) {
      final fromReasoning = DoubaoApiService.extractJsonBlock(_reasoningText);
      if (fromReasoning.isNotEmpty) {
        try {
          final maps = DoubaoApiService.parseResponse(
            fromReasoning,
            analysisMode: widget.analysisMode,
          );
          if (maps.isNotEmpty) {
            _contentText = fromReasoning; // 结果来自思考通道,档位保持不变
          }
        } catch (e) {
          debugPrint('ReadFlow reasoning JSON parse failed: $e');
        }
      }
    }

    // 思考模式下确实没有可用结果 → 用**同一档位**重试一次(绝不改成不思考),
    // 第二次仍失败则如实报错,把选择权留给用户。
    if (_contentText.trim().isEmpty &&
        _reasoningText.isNotEmpty &&
        _lastRequestThinking != 'disabled') {
      if (!_reasoningOnlyRetried) {
        _reasoningOnlyRetried = true;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '思考模型本次只输出了思考过程，正在用相同档位（'
                '${AppConstants.thinkingOptionsFor(_currentModel)[_lastRequestThinking] ?? _lastRequestThinking}'
                '）重试一次…',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        _retry();
        return;
      }
      setState(() {
        _phase = _StreamPhase.error;
        _errorMessage =
            '模型两次都只返回了思考过程、没有结果。\n'
            '思考档位保持为你选择的值（未被改成"不思考"），可：\n'
            '① 直接重试  ② 换模型  ③ 到设置里换一个更快的思考档位\n\n'
            '思考内容（前 300 字）：\n'
            '${_reasoningText.length > 300 ? '${_reasoningText.substring(0, 300)}…' : _reasoningText}';
      });
      return;
    }

    try {
      final rawMaps = DoubaoApiService.parseResponse(
        _contentText,
        analysisMode: widget.analysisMode,
      );
      if (rawMaps.isEmpty) {
        if (_supplementMode) {
          // 补充识别没找到遗漏 → 回结果页 + 提示,不算错误(v1.3.0 问题 3)
          setState(() {
            _supplementMode = false;
            _phase = _StreamPhase.results;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('AI 未发现新的遗漏内容'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        if (_recalibrateMode) {
          // 校准重识别没识别到标注 → 保留原结果,明确告知(不丢用户数据)
          setState(() {
            _recalibrateMode = false;
            _phase = _StreamPhase.results;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('重新识别未发现标注内容，已保留原结果'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
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
        // 追加图片时新段落接在旧段落后,不替换(v1.4.0 问题 10)
        final newParas = rawMaps
            .map(
              (r) => {
                'original': r['original'] as String? ?? '',
                'translation': r['translation'] as String? ?? '',
              },
            )
            .where((m) => m['original']!.isNotEmpty)
            .toList();
        _fullTextParagraphs = _streamStartIndex == 0
            ? newParas
            : [..._fullTextParagraphs, ...newParas];
        // 记录每轮识别起点(点击 pN 跳转用,v1.4.1)
        if (_streamStartIndex == 0) {
          _fullTextGroupStarts
            ..clear()
            ..add(0);
        } else {
          _fullTextGroupStarts.add(_fullTextParagraphs.length - newParas.length);
        }
        setState(() {
          _phase = _StreamPhase.results;
          _streamStartIndex = 0;
        });
      } else {
        // 圈画模式结果 — 多图时按 image_index 映射正确的 photoPath。
        // 追加模式:AI 对"本轮新图"从 0 编号,加 _streamStartIndex 映射回全局
        final results = rawMaps.map((r) {
          final imgIdx = _safeImageIndex(r['image_index']) + _streamStartIndex;
          // 越界(模型幻觉组号)回退第一张而非最后一张:
          // 识别从第一张开始,0 更可能是"模型忘标"而非"标到最后一本",
          // 避免把词悄悄绑到最后一本书上
          final photoPath = imgIdx >= 0 && imgIdx < _images.length
              ? _images[imgIdx].path
              : _images[0].path;
          return Vocabulary(
            word: r['word'] as String,
            translation: r['translation'] as String?,
            sourceBook: widget.sourceBook,
            sourcePage: widget.sourcePage,
            originalSentence: r['original_sentence'] as String?,
            photoPath: photoPath,
            wordType: (r['word_type'] as String?) ?? 'word',
            partOfSpeech: r['part_of_speech'] as String?,
            phonetic: r['phonetic'] as String?,
            grammarNote: r['grammar_note'] as String?,
          );
        }).toList();

        setState(() {
          _phase = _StreamPhase.results;
          if (_recalibrateMode) {
            // 重新识别:整组替换(旧结果作废),但**保留手动补充的词**
            // (photoPath == null 是用户自己敲进去的,不能被 AI 覆盖掉)
            final manual = _results.where((v) => v.photoPath == null).toList();
            _results = [...results, ...manual];
            _selected.clear();
          } else if (_streamStartIndex == 0 && !_supplementMode) {
            // 首次识别:整组替换,默认不选中(长按才选中)
            _results = results;
            _selected.clear();
          } else if (_supplementMode) {
            // 补充识别:只并入遗漏项,按 (word, wordType) 去重(v1.3.0 问题 3)
            _results = mergeSupplementResults(_results, results);
          } else {
            // 追加识别:新结果接在旧结果后;新词默认不选中,旧选中保留
            _results = [..._results, ...results];
          }
          final wasCalibrate = _recalibrateMode;
          _reasoningOnlyRetried = false; // 成功即复位守卫
          _truncationRetried = false;
          _recalibrateMode = false; // 校准结束复位
          _streamStartIndex = 0; // 本轮结束复位,下次从头开始
          _supplementMode = false; // 补充识别结束复位
          if (wasCalibrate) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text('重新识别完成：共 ${results.length} 条标注内容'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
          }
        });
      }
      // 滚动到 AI 结果区域顶部
      _scrollToAiSection();
    } catch (e) {
      if (!mounted) return;
      // 校准/补充标记复位:失败后重试按普通重试处理(否则会带着旧模式重跑)
      final wasCalibrate = _recalibrateMode;
      _recalibrateMode = false;
      _supplementMode = false;
      // v1.8.0:内容疑似截断(JSON 未闭合)时,用**同一思考档位**重试一次,
      // 不再把用户选的档位砍成"不思考";第二次仍截断则如实报错。
      final raw = _contentText.trim();
      if (_lastRequestThinking != 'disabled' &&
          raw.isNotEmpty &&
          !raw.endsWith('}') &&
          !raw.endsWith(']') &&
          !_truncationRetried) {
        _truncationRetried = true;
        _recalibrateMode = wasCalibrate; // 截断重试:保留校准语义
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('识别内容疑似被截断，正在用相同思考档位重试一次…'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
        _retry();
        return;
      }
      // v1.4.2:解析失败必须展示 AI 原文片段——思考模式输出格式/截断问题
      // 从此一眼定位,不再盲猜
      final rawSnippet = raw.isEmpty
          ? '(流未收到内容)'
          : raw.length > 400
              ? '${raw.substring(0, 400)}…'
              : raw;
      setState(() {
        _phase = _StreamPhase.error;
        _errorMessage = 'AI 返回内容解析失败，请重试。\n${e.toString()}\n\n'
            'AI 返回原文(前 400 字):\n$rawSnippet';
      });
    }
  }

  /// [resetGuards] true = 用户手动点重试:清掉 reasoning-only/截断重试守卫
  void _retry({bool resetGuards = false}) {
    _subscription?.cancel();
    if (resetGuards) {
      _reasoningOnlyRetried = false;
      _truncationRetried = false;
    }
    _thinkingTimer?.cancel();
    // 追加模式失败重试:保留 _streamStartIndex,只重识别"本轮追加的图"。
    // 旧实现无条件置 0 → 追加失败重试时全量重识别,onDone 走首轮分支
    // 整组替换 _results 并清空 _selected,把批量1 的结果和选中静默丢掉。
    // 首次识别失败时 _streamStartIndex 本来就是 0,语义不变 = 全新识别。
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

  /// 点击聊天栏图片/页码条 → 滚动到对应分组的识别结果
  /// (v1.4.1:全文翻译模式滚到该图第一段,不再永远停在追加结果)
  void _scrollToImageGroup(int imageIndex) {
    if (widget.analysisMode == AppConstants.analysisModeFullText) {
      if (imageIndex >= 0 && imageIndex < _fullTextGroupStarts.length) {
        final start = _fullTextGroupStarts[imageIndex];
        if (start < _fullTextCardKeys.length) {
          final ctx = _fullTextCardKeys[start].currentContext;
          if (ctx != null && _scrollCtrl.hasClients) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.05,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
            return;
          }
        }
      }
      // 找不到对应段(单次多图无分组信息)→ 滚回顶部(图片区)
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      return;
    }
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
        final saved = await _saveAndReturn(saveAll: !hasSel);
        // 用户在分类选择处取消:返回键已被消费,必须给反馈,否则像没点一样
        if (!saved && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已取消保存,没有词被存入词库')),
          );
        }
        return false; // _saveAndReturn 成功时已 pop
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
    if (_followUp.dirty && _followUp.messages.value.isNotEmpty) {
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
        await _followUp.saveConversation();
      }
    }
    return true; // 允许退出
  }

  // ═══════════════ 保存 ═══════════════

  /// 保存选中/全部结果并退出。返回是否真正完成了保存——
  /// 用户在分类选择处取消时返回 false,调用方需给出提示,
  /// 否则返回键被消费却毫无反馈(2026-08-11 code-review F10)。
  Future<bool> _saveAndReturn({bool saveAll = false}) async {
    // saveAll=true:未选中任何词时从返回弹窗"保存全部"进入,保存所有结果
    final selected = (saveAll
            ? List.generate(_results.length, (i) => i)
            : _selected)
        .map((i) => _results[i])
        .toList();
    if (selected.isEmpty) return false;

    // 1. 弹出分类选择
    final category = await showCategoryPicker(context);
    if (category == null || !mounted) return false; // 用户取消 → 调用方提示

    // 2. 弹出子分类输入（可跳过）
    final subInfo = await showSubCategoryInput(
      context,
      category: category,
      prefill: widget.sourceBook ?? '',
    );
    if (!mounted) return false;

    try {
      final categorized = selected.map((v) {
        return v.copyWith(
          category: category,
          materialPath: subInfo?.materialPath,
          sourceBook: subInfo?.materialName ?? v.sourceBook,
          // 书籍类页码独立字段(v1.4.4)
          sourcePage: subInfo?.sourcePage ?? v.sourcePage,
        );
      }).toList();
      await context.read<VocabProvider>().saveVocabularies(categorized);
      if (mounted) Navigator.pop(context, true);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
      return false;
    }
  }

  /// 打开追问抽屉(独立路由;与识图页共用同一套交互)
  void _openFollowUp({String? prefillQuestion, String? followUpContext}) {
    showFollowUpDrawer(
      context: context,
      controller: _followUp,
      prefillQuestion: prefillQuestion,
      contextOverride: followUpContext,
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
              // 重新识别(v1.8.0 用户要求):校准与补漏合成一个动作——
              // 对全部图片重新完整识别(逐行扫描+高清+自检),结果整组替换。
              // 不再让用户面对"校准 vs 补漏"的选择题。
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: '重新识别',
                onPressed: _recalibrate,
              ),
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
                        child: ScrollToTopButton(scrollCtrl: _scrollCtrl),
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
    // 截断词条(带省略号残片)模型看不懂,传完整句(F7)
    final aiWord = item.displayWordText;
    // 预填追问上下文
    final ctx = StringBuffer();
    ctx.writeln('单词：$aiWord');
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
      prefillQuestion: '请详细解释 "$aiWord" 的用法',
      followUpContext: ctx.toString(),
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
                // 按端点族/最近拉取结果展示(user:配了 DS 不显示豆包,v1.4.3)
                ...primaryModelChoices().map((m) {
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
                // 思考档位按模型族:DS 4 档/豆包 2 档(v1.4.3)
                ...AppConstants.thinkingOptionsFor(_currentModel).entries
                    .map((e) {
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

  /// 重新识别(v1.8.0 合并版):对识别结果不满意时**重新认真识别一遍**——
  /// 逐行扫描 + 高清图(detail=high) + 输出前自检,结果整组替换。
  /// 校准与补漏本就是一件事(重跑一遍自然既纠正又补全),不再让用户选。
  /// 会先弹确认:当前结果与手动修改会被替换(手动补充的词会保留)。
  Future<void> _recalibrate() async {
    if (_phase != _StreamPhase.results ||
        widget.analysisMode == AppConstants.analysisModeFullText ||
        _images.isEmpty) {
      return;
    }
    final manualCount = _results.where((v) => v.photoPath == null).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新识别'),
        content: Text(
          '重新完整识别这些图片（逐行扫描 + 高清图 + 输出前自检），'
          '既纠正错识也补齐漏识。\n\n'
          '当前 ${_results.length} 条结果将被替换'
          '${manualCount > 0 ? '（其中 $manualCount 条手动补充的词会保留）' : ''}，确定继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重新识别'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _recalibrateMode = true;
      _supplementMode = false;
      _streamStartIndex = 0; // 全部图片重跑
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
                  // 追加图片:圈画/全文翻译模式都支持(v1.4.0 问题 10)
                  if (_phase == _StreamPhase.results)
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
            userAvatar(context: context),
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
            aiAvatar(error: _phase == _StreamPhase.error, modelName: _currentModel),
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
                '$_currentModel · ${AppConstants.thinkingOptionsFor(_currentModel)[_currentThinking] ?? "不思考"}',
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 段落卡片(点击原文/「AI 讲解」→ 追问详解该段,v1.4.0 问题 6)
        // 多轮追加时按图片分组显示(如"p1 识别结果…"开头),不再挤在一起(v1.4.2)
        ..._syncFullTextCardKeys(),
        ..._buildFullTextGrouped(theme),
      ],
    );
  }

  /// 全文翻译段落:多图(多轮)按图片分组渲染,单图平铺
  List<Widget> _buildFullTextGrouped(ThemeData theme) {
    final widgets = <Widget>[];
    if (_fullTextGroupStarts.length <= 1) {
      for (var i = 0; i < _fullTextParagraphs.length; i++) {
        widgets.add(_fullTextCard(i));
      }
      return widgets;
    }
    for (var g = 0; g < _fullTextGroupStarts.length; g++) {
      final start = _fullTextGroupStarts[g];
      final end = g + 1 < _fullTextGroupStarts.length
          ? _fullTextGroupStarts[g + 1]
          : _fullTextParagraphs.length;
      if (start >= end) continue; // 空轮(理论上不会)
      widgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.image_outlined,
                  size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'p${g + 1} 识别结果 · 第 ${g + 1} 张图片',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
      for (var i = start; i < end; i++) {
        widgets.add(_fullTextCard(i));
      }
    }
    return widgets;
  }

  Widget _fullTextCard(int i) {
    final p = _fullTextParagraphs[i];
    return KeyedSubtree(
      key: i < _fullTextCardKeys.length ? _fullTextCardKeys[i] : null,
      child: FulltextResultCard(
        index: i,
        original: p['original'] ?? '',
        translation: p['translation'] ?? '',
        onAskExplain: () => _askAiAboutParagraph(i),
      ),
    );
  }

  /// 全文翻译段落锚点列表与段落数对齐(重建时补齐/截断)
  List<Widget> _syncFullTextCardKeys() {
    while (_fullTextCardKeys.length < _fullTextParagraphs.length) {
      _fullTextCardKeys.add(GlobalKey(debugLabel: 'fulltext_card'));
    }
    while (_fullTextCardKeys.length > _fullTextParagraphs.length) {
      _fullTextCardKeys.removeLast();
    }
    return const <Widget>[];
  }

  /// 全文翻译段落 → 追问详解(带原文+译文上下文,AI 待命)
  void _askAiAboutParagraph(int index) {
    if (index < 0 || index >= _fullTextParagraphs.length) return;
    final p = _fullTextParagraphs[index];
    final ctx = StringBuffer()
      ..writeln('原文段落：${p['original'] ?? ''}')
      ..writeln('译文：${p['translation'] ?? ''}');
    _openFollowUp(
      prefillQuestion: '请详细讲解这段英文的语法结构、重点词汇和含义',
      followUpContext: ctx.toString(),
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
      // v1.8.0:选中模式下单击 = 选中/取消;否则单击 = 询问 AI 详解
      onTap: () {
        if (_selected.isNotEmpty) {
          _onWordLongPress(index);
          return;
        }
        setState(() => _queryTargetIndex = index);
      },
      onLongPress: () => _onWordLongPress(index),
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
                    item.displayWordText,
                    // 不限行 + 永不打省略号:一排放不下自动换行
                    // (2026-08-10 用户实测终局修复:maxLines:null + visible)
                    maxLines: null,
                    overflow: TextOverflow.visible,
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
                // 收藏星标——好句子/词条单独收藏(v1.4.0 问题 8)
                InkWell(
                  onTap: () => _toggleVocabBookmark(item),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      _isVocabBookmarked(item)
                          ? Icons.star
                          : Icons.star_border,
                      size: 15,
                      color: _isVocabBookmarked(item)
                          ? Colors.amber[700]
                          : Colors.grey[400],
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
                // 冗长例句限行 3 行 + 展开;出处句中目标词加粗
                // (2026-08-10 用户需求:例句精简 + 词汇标粗)
                child: ExampleSentence(
                  sentence: item.originalSentence!,
                  highlightWord: item.word,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
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
              AppConstants.thinkingOptionsFor(_currentModel)[_currentThinking] ??
                  '不思考',
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
            label: const Text('添加词汇'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ),
        Center(
          child: Text(
            _selected.isEmpty
                ? (_displayMode == _DisplayMode.detailed
                      ? '单击 = AI 详解 · 长按进入选中'
                      : '单击 = 查看详情 · 长按进入选中')
                : '选中模式：单击 = 选中/取消 · 右上角可删除/保存',
            style: TextStyle(
              fontSize: 12,
              color: _selected.isEmpty
                  ? Colors.grey[400]
                  : theme.colorScheme.primary,
              fontWeight: _selected.isEmpty ? FontWeight.normal : FontWeight.w600,
            ),
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
            // v1.8.0:选中模式下单击 = 选中/取消选中(用户要求单点快选,
            // 不再为了选一个词长按半天);非选中模式仍然是看详情
            if (_selected.isNotEmpty) {
              _onWordLongPress(i);
              return;
            }
            showWordDetailSheet(
              context: context,
              item: item,
              onSave: () => _saveSingleItem(i),
              onEdit: () => _editItem(i),
              onRemove: () => setState(() => _selected.remove(i)),
            );
          },
          onLongPress: () => _onWordLongPress(i),
          onBookmark: () => _toggleVocabBookmark(item),
          bookmarked: _isVocabBookmarked(item),
          onSpeak: () => _speakWord(item),
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
                if (_selected.isNotEmpty) {
                  _onWordLongPress(i);
                  return;
                }
                showWordDetailSheet(
                  context: context,
                  item: item,
                  onSave: () => _saveSingleItem(i),
                  onEdit: () => _editItem(i),
                  onRemove: () => setState(() => _selected.remove(i)),
                );
              },
              onLongPress: () => _onWordLongPress(i),
              onBookmark: () => _toggleVocabBookmark(item),
              bookmarked: _isVocabBookmarked(item),
              onSpeak: () => _speakWord(item),
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
        // 书籍类页码独立字段(v1.4.4),不参与材料路径分组
        sourcePage: subInfo?.sourcePage ?? _results[index].sourcePage,
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
                onPressed: () => _retry(resetGuards: true),
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
    final phoneticCtrl = TextEditingController(text: item.phonetic ?? '');
    final grammarCtrl = TextEditingController(text: item.grammarNote ?? '');
    final sentenceCtrl = TextEditingController(
      text: item.originalSentence ?? '',
    );

    void disposeAll() {
      wordCtrl.dispose();
      transCtrl.dispose();
      posCtrl.dispose();
      phoneticCtrl.dispose();
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
                TextField(
                  controller: phoneticCtrl,
                  decoration: const InputDecoration(
                    labelText: '音标',
                    hintText: '如：/ˈʌnfetəd/',
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
                '修改「原文」后，例句中的「${item.displayWordText.length > 12 ? '${item.displayWordText.substring(0, 12)}…' : item.displayWordText}」会自动替换为新词',
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
                  phonetic: phoneticCtrl.text.trim().isEmpty
                      ? null
                      : phoneticCtrl.text.trim(),
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

  /// 词汇卡片收藏(v1.4.0 问题 8):原文+释义+例句作为收藏内容,
  /// 独立于生词本——觉得句子好可单独收藏
  Future<void> _toggleVocabBookmark(Vocabulary v) async {
    final saved = await context.read<BookmarkProvider>().toggle(
          Bookmark(
            source: AppConstants.bookmarkSourceVocab,
            title: v.displayWordText,
            content: _vocabBookmarkContent(v),
            sourceWord: v.word,
          ),
        );
    // await 之后按真实结果提示(异步时序导致提示相反是 v1.4.1 的缺陷)
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(saved ? '已收藏到收藏夹' : '已取消收藏'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  String _vocabBookmarkContent(Vocabulary v) {
    return [
      v.displayWordText,
      if (v.translation != null && v.translation!.isNotEmpty)
        '释义：${v.translation}',
      if (v.originalSentence != null && v.originalSentence!.isNotEmpty)
        '例句：${v.originalSentence}',
    ].join('\n');
  }

  bool _isVocabBookmarked(Vocabulary v) {
    // 用 watch:收藏/取消后星标实时变化(用 read 不会重建,v1.4.0 实测"点星没反应"根因)
    return context
        .watch<BookmarkProvider>()
        .isBookmarked(
            AppConstants.bookmarkSourceVocab, _vocabBookmarkContent(v));
  }

  /// 系统 TTS 朗读(v1.5.0):单词点一下朗读。失败(无语音引擎)提示一次。
  Future<void> _speakWord(Vocabulary v) async {
    final ok = await TtsService.instance.speak(v.displayWordText);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('设备未找到可用语音引擎，暂时无法朗读'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  /// 词条长按(v1.4.4 用户最新指示):
  /// 未选中 → 选中(多选批量);已选中 → **取消该词选中**(单个取消,
  /// 误选可即时修正)。复制功能迁至词详情弹窗(v1.4.4),长按不再弹菜单。
  void _onWordLongPress(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
    });
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
  /// v1.3.0 问题 2：加「✨ AI 补全」——填词后一键调 AI 回填 释义/词性/例句/语法。
  void _showAddWordDialog() {
    final wordCtrl = TextEditingController();
    final transCtrl = TextEditingController();
    final posCtrl = TextEditingController();
    final phoneticCtrl = TextEditingController();
    final sentenceCtrl = TextEditingController();
    bool completing = false;

    void disposeAll() {
      wordCtrl.dispose();
      transCtrl.dispose();
      posCtrl.dispose();
      phoneticCtrl.dispose();
      sentenceCtrl.dispose();
    }

    /// 只回填空字段——用户手动填过的内容不覆盖
    void applyWordInfo(Map<String, String> info) {
      if (transCtrl.text.trim().isEmpty) transCtrl.text = info['translation'] ?? '';
      if (posCtrl.text.trim().isEmpty) posCtrl.text = info['part_of_speech'] ?? '';
      if (phoneticCtrl.text.trim().isEmpty) {
        phoneticCtrl.text = info['phonetic'] ?? '';
      }
      if (sentenceCtrl.text.trim().isEmpty) {
        sentenceCtrl.text = info['original_sentence'] ?? '';
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
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
                  controller: phoneticCtrl,
                  decoration: const InputDecoration(
                    labelText: '音标（可选）',
                    hintText: '如：/ˈʌnfetəd/',
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
                const SizedBox(height: 8),
                // ✨ AI 补全：填词后一键回填释义/词性/例句
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: completing ||
                            wordCtrl.text.trim().isEmpty ||
                            !_followUpEndpoint.isConfigured
                        ? null
                        : () async {
                            setLocalState(() => completing = true);
                            try {
                              final info = await _api.completeWordInfo(
                                wordCtrl.text.trim(),
                                endpoint: _followUpEndpoint,
                              );
                              if (info['translation']?.isEmpty ?? true) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'AI 未返回有效信息，请手动填写或换个词试试',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else {
                                applyWordInfo(info);
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('AI 补全失败：$e'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            } finally {
                              setLocalState(() => completing = false);
                            }
                          },
                    icon: completing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(completing ? '补全中…' : '✨ AI 补全'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                  ),
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
                      phonetic: phoneticCtrl.text.trim().isEmpty
                          ? null
                          : phoneticCtrl.text.trim(),
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


