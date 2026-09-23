import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../config/constants.dart';
import '../../../services/api_endpoint.dart';
import '../../../services/base_api.dart';
import '../../../services/doubao_api.dart';
import '../../../utils/follow_up_context.dart';
import '../../../widgets/confirm_destructive.dart';
import 'follow_up_bubble.dart';
import 'follow_up_models.dart';
import 'model_avatars.dart';
import 'scroll_buttons.dart';

/// 追问抽屉的共享状态与逻辑(v1.6.0 抽取)。
///
/// 原先整套追问逻辑内嵌在 ProcessChatScreen 里(识图页专用);写译批改
/// 也要「和识图里一样的学习体验」(收藏/选模型/上下楼记忆),所以把
/// 状态机抽到这里,两个页面共用同一份实现,不再各写一套。
///
/// 页面只需提供 [buildContext](材料上下文)与可选的 [imageFilesProvider]
/// (支持视觉的模型能真正"看到"材料)。
class FollowUpController {
  FollowUpController({
    required this.buildContext,
    this.imageFilesProvider,
    this.historyKey = 'saved_follow_up_chats',
    this.emptyHint = '输入问题，AI 将基于材料内容回答',
  }) {
    slotNotifier.value = slot;
    loadConversations();
  }

  /// 材料上下文(识别结果/翻译/写译原文与批改结果)
  final String Function() buildContext;

  /// 可选的图片提供者(识图页追问时把页面图片一起发给视觉模型)
  final List<File>? Function()? imageFilesProvider;

  /// 历史对话在 Hive 里的 key(不同页面互不覆盖)
  final String historyKey;

  /// 空态提示文案
  final String emptyHint;

  final ValueNotifier<List<FollowUpMessage>> messages = ValueNotifier([]);
  final ValueNotifier<bool> loading = ValueNotifier(false);

  /// 槽位切换通知:抽屉是独立路由,主屏 setState 不会重建它
  final ValueNotifier<String> slotNotifier = ValueNotifier('primary');

  final TextEditingController inputCtrl = TextEditingController();
  final FocusNode focusNode = FocusNode();

  StreamSubscription<SseChunk>? _sub;
  /// 流内空闲看门狗(v1.9.0,P1-3):60s 无新数据即断开,避免永久转圈
  Timer? _idleTimer;
  bool pendingScroll = false;
  /// P3:本帧是否已经注册过"滚到底"的 postFrameCallback(防同帧重复注册)
  bool scrollScheduled = false;

  /// 页面/控制器已销毁(P2-11/P2-12)。
  /// 抽屉是独立路由,主屏 dispose 之后在途的异步回调仍可能拿着本对象
  /// (最典型的是 `_stream` 里 `await imageDataUrisFor()` 的那几秒)——
  /// 没有这道总闸,回调会往已 dispose 的 ValueNotifier 里写值。
  bool _disposed = false;

  /// 本轮流式的身份令牌(P2-11)。stop / editMessage / clear / 新一次 _stream
  /// 都会自增它,于是"上一轮"的回调在写回气泡前就能发现自己是旧的并退出。
  ///
  /// 为什么需要:`_stream` 在 await 期间存在窗口,这期间用户可能已经
  /// 编辑提问或清空了列表,旧闭包仍按旧的 aiMsgIndex 写回 → 写错气泡。
  int _streamToken = 0;

  /// 本次会话是否有追问内容(退出时提示保存)
  bool dirty = false;

  /// 外部预设上下文(如「询问 AI 详解」),优先级高于 [buildContext]
  String? contextOverride;

  List<FollowUpSavedConversation> savedConversations = [];

  // ── 槽位 / 模型 / 思考(全部走 Hive,与识图页共享设置) ──

  String get slot {
    final v = Hive.box(AppConstants.hiveBoxSettings).get(
      AppConstants.keyFollowUpSlot,
    );
    return (v is String && v == 'secondary') ? 'secondary' : 'primary';
  }

  ApiEndpointConfig get endpoint {
    if (slot == 'secondary' && ApiEndpointConfig.secondary.isConfigured) {
      return ApiEndpointConfig.secondary;
    }
    return ApiEndpointConfig.primary;
  }

  String get model => endpoint.model;

  /// 追问思考档位 — 独立存储(keyFollowUpThinking)。
  /// v1.7.0:合法档位按**当前模型族**判定(DS 官方只有 low/high/max),
  /// 此前用固定 4 档校验,DS 下选「极致」会被打回 disabled。
  String get thinking {
    final v = Hive.box(
      AppConstants.hiveBoxSettings,
    ).get(AppConstants.keyFollowUpThinking);
    final allowed =
        AppConstants.followUpThinkingOptionsFor(endpoint.model).keys;
    return (v is String && allowed.contains(v)) ? v : 'disabled';
  }

  // ── 发送 / 停止 / 编辑 ──

  void send(String text) {
    if (_disposed) return;
    final q = text.trim();
    if (q.isEmpty || loading.value) return;
    final userMsg = FollowUpMessage(role: 'user', content: q);
    final aiMsg = FollowUpMessage(
      role: 'ai',
      content: '',
      streaming: true,
      model: model,
    );
    messages.value = [...messages.value, userMsg, aiMsg];
    inputCtrl.clear();
    loading.value = true;
    dirty = true;
    pendingScroll = true;
    _stream(q, messages.value.length - 1);
  }

  void stop() {
    if (_disposed) return;
    // 作废本轮:在途回调(可能正卡在 await 里)之后不许再写气泡
    _streamToken++;
    _sub?.cancel();
    _sub = null;
    final msgs = List<FollowUpMessage>.from(messages.value);
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == 'ai' && msgs[i].streaming) {
        msgs[i] = FollowUpMessage(
          role: 'ai',
          content: msgs[i].content.isEmpty ? '（已停止生成）' : msgs[i].content,
          reasoningText: msgs[i].reasoningText,
          streaming: false,
          model: msgs[i].model,
        );
        break;
      }
    }
    messages.value = msgs;
    loading.value = false;
  }

  /// 编辑用户消息:替换内容 + 删除其后消息 + 重新生成
  void editMessage(int index, String newText) {
    if (_disposed) return;
    final msgs = List<FollowUpMessage>.from(messages.value);
    if (index < 0 || index >= msgs.length) return;
    _sub?.cancel();
    msgs[index] = FollowUpMessage(role: 'user', content: newText);
    final trimmed = msgs.take(index + 1).toList();
    trimmed.add(
      FollowUpMessage(role: 'ai', content: '', streaming: true, model: model),
    );
    messages.value = trimmed;
    loading.value = true;
    dirty = true;
    pendingScroll = true;
    // _stream 开头会自增 _streamToken,旧流至此彻底作废
    _stream(newText, trimmed.length - 1);
  }

  void clear() {
    if (_disposed) return;
    _streamToken++; // 同 stop:清空后旧流不许再往列表里写
    _sub?.cancel();
    _sub = null;
    messages.value = [];
    loading.value = false;
    dirty = false;
  }

  Future<void> _stream(String question, int aiMsgIndex) async {
    if (_disposed) return;
    final token = ++_streamToken; // 本次流的身份,旧流从这里开始失效
    _sub?.cancel();
    String reasoning = '';
    String content = '';

    final ctx = contextOverride ?? buildContext();
    contextOverride = null; // 一次性消费

    List<String>? imageUris;
    final files = imageFilesProvider?.call();
    if (files != null &&
        files.isNotEmpty &&
        modelSupportsImages(endpoint.model)) {
      try {
        imageUris = await DoubaoApiService().imageDataUrisFor(files);
      } catch (e) {
        debugPrint('ReadFlow followUp image prep fallback: $e');
        imageUris = null;
      }
    }

    // 准备图片可能要几秒:await 之后、listen 之前再判一次 ——
    // 这段时间里页面可能已销毁,或用户已停止/编辑/清空(P2-11)。
    // 不判就会"页面已经销毁但仍在发请求",并往错的/已释放的气泡里写。
    if (_disposed || token != _streamToken) return;

    void updateMsg({bool done = false}) {
      // 旧流的回调一律丢弃:只认自己那一轮令牌,且只写 AI 气泡
      if (_disposed || token != _streamToken) return;
      final msgs = List<FollowUpMessage>.from(messages.value);
      if (aiMsgIndex < msgs.length && msgs[aiMsgIndex].role == 'ai') {
        msgs[aiMsgIndex] = FollowUpMessage(
          role: 'ai',
          content: done
              // v1.8.0:思考模型有时把答案整段写在思考通道(content 为空)
              // → 直接把思考内容当回答展示,而不是显示"未返回内容"
              ? (content.isNotEmpty
                    ? content
                    : (reasoning.trim().isNotEmpty ? reasoning : '（AI 未返回内容）'))
              : content,
          reasoningText: reasoning.isNotEmpty ? reasoning : null,
          streaming: !done,
          model: msgs[aiMsgIndex].model,
        );
        messages.value = msgs;
      }
      if (done) loading.value = false;
    }

    try {
      // 上下楼记忆:把当前轮之前的已完成对话发给模型(role 映射在纯函数内)
      final history = buildFollowUpHistory(messages.value, aiMsgIndex);
      final stream = DoubaoApiService().followUpStream(
        question,
        context: ctx,
        endpoint: endpoint,
        imageDataUris: imageUris,
        thinkingLevel: thinking,
        history: history,
      );
      _sub = stream.listen(
        (chunk) {
          _armIdleWatchdog(); // P1-3:每个 chunk 重置空闲看门狗
          if (chunk.isReasoning) {
            reasoning += chunk.text;
          } else {
            content += chunk.text;
          }
          updateMsg();
        },
        onDone: () {
          _idleTimer?.cancel();
          updateMsg(done: true);
        },
        onError: (e) {
          _idleTimer?.cancel();
          // 保留已流式显示的内容,追加友好错误
          content = content.isNotEmpty
              ? '$content\n\n[错误] ${BaseApiService.friendlyError(e)}'
              : BaseApiService.friendlyError(e);
          updateMsg(done: true);
        },
        cancelOnError: false,
      );
    } catch (e) {
      _idleTimer?.cancel();
      content = BaseApiService.friendlyError(e);
      updateMsg(done: true);
    }
  }

  /// 流内空闲看门狗(v1.9.0,审查 P1-3):60s 没收到任何字节就主动收尾。
  /// dio 的 receiveTimeout 只覆盖"等响应头",流式 body 中途卡死时
  /// 旧实现会一直转圈,用户只能杀进程。
  void _armIdleWatchdog() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (_disposed) return;
      _sub?.cancel();
      _sub = null;
      loading.value = false;
      final msgs = List<FollowUpMessage>.from(messages.value);
      for (int i = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].role == 'ai' && msgs[i].streaming) {
          msgs[i] = FollowUpMessage(
            role: 'ai',
            content: msgs[i].content.isEmpty
                ? '（60 秒没有收到新数据，已中止。可重试或降低思考档位）'
                : '${msgs[i].content}\n\n[已中止] 60 秒没有收到新数据',
            reasoningText: msgs[i].reasoningText,
            streaming: false,
            model: msgs[i].model,
          );
          break;
        }
      }
      messages.value = msgs;
    });
  }

  // ── 历史对话持久化 ──

  void loadConversations() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings).get(historyKey);
      if (raw is List) {
        savedConversations = raw
            .map(
              (e) => FollowUpSavedConversation.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
    } catch (_) {
      savedConversations = [];
    }
  }

  Future<void> saveConversation() async {
    final msgs = messages.value;
    if (msgs.isEmpty) return;
    final now = DateTime.now();
    final firstUser =
        msgs.where((m) => m.role == 'user').firstOrNull?.content ?? '';
    final title = firstUser.isNotEmpty
        ? (firstUser.length > 30 ? '${firstUser.substring(0, 30)}…' : firstUser)
        : '追问记录';
    final conv = FollowUpSavedConversation(
      id: now.millisecondsSinceEpoch.toString(),
      title: title,
      dateLabel:
          '${now.month}月${now.day}日 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      messages: msgs
          .where((m) => !m.streaming)
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
    savedConversations.insert(0, conv);
    try {
      await Hive.box(
        AppConstants.hiveBoxSettings,
      ).put(historyKey, savedConversations.map((c) => c.toJson()).toList());
      dirty = false;
    } catch (e) {
      debugPrint('ReadFlow saveFollowUp error: $e');
    }
  }

  void loadConversation(FollowUpSavedConversation conv) {
    messages.value = conv.messages
        .map(
          (m) => FollowUpMessage(
            role: m['role'] as String,
            content: m['content'] as String,
            reasoningText: m['reasoningText'] as String?,
            model: m['model'] as String?,
          ),
        )
        .toList();
    dirty = false;
  }

  void dispose() {
    // 先立旗再拆资源:在途回调看到 _disposed 就不会再去碰已释放的 ValueNotifier
    _disposed = true;
    _streamToken++; // 顺带作废在途流(它 await 回来后不会再 listen)
    _sub?.cancel();
    _sub = null;
    inputCtrl.dispose();
    focusNode.dispose();
    messages.dispose();
    loading.dispose();
    slotNotifier.dispose();
  }
}

/// 打开追问抽屉(独立路由;与识图页同一套交互)
void showFollowUpDrawer({
  required BuildContext context,
  required FollowUpController controller,
  String? prefillQuestion,
  String? contextOverride,
  String title = '追问抽屉',
}) {
  controller.inputCtrl.clear();
  if (prefillQuestion != null) controller.inputCtrl.text = prefillQuestion;
  controller.contextOverride = contextOverride;
  final bottomSafe = MediaQuery.of(context).padding.bottom;
  showModalBottomSheet(
    context: context,
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
      child: _FollowUpSheet(controller: controller, title: title),
    ),
  );
}

class _FollowUpSheet extends StatelessWidget {
  final FollowUpController controller;
  final String title;

  const _FollowUpSheet({required this.controller, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // 拖拽条
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 标题栏
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                CompactModelPicker(controller: controller),
                ValueListenableBuilder<List<FollowUpMessage>>(
                  valueListenable: controller.messages,
                  builder: (_, msgs, _) {
                    if (msgs.isEmpty) return const SizedBox.shrink();
                    return GestureDetector(
                      onTap: controller.clear,
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
                    );
                  },
                ),
                const Spacer(),
                if (controller.savedConversations.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showHistoryPicker(context, controller),
                    child: Icon(
                      Icons.history,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          // 消息列表
          Expanded(
            child: ValueListenableBuilder<List<FollowUpMessage>>(
              valueListenable: controller.messages,
              builder: (ctx, msgs, child) {
                if (msgs.isEmpty) {
                  return Center(
                    child: Text(
                      controller.emptyHint,
                      // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                }
                // P3:这段 builder 在流式期间每个 chunk 都会重跑,同一帧内可能
                // 注册多次 postFrameCallback → animateTo 被重复触发。用一个
                // 控制器上的标志位保证"每帧至多注册一次"。
                if (!controller.scrollScheduled) {
                  controller.scrollScheduled = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    controller.scrollScheduled = false;
                    if (!scrollCtrl.hasClients) return;
                    final pos = scrollCtrl.position;
                    final nearBottom = pos.maxScrollExtent - pos.pixels < 150;
                    if (controller.pendingScroll || nearBottom) {
                      controller.pendingScroll = false;
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
                }
                return Stack(
                  children: [
                    ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) => _buildBubble(context, msgs[i], i),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: FollowUpScrollButtons(scrollCtrl: scrollCtrl),
                    ),
                  ],
                );
              },
            ),
          ),
          // 输入栏
          StatefulBuilder(
            builder: (ctx, setLocalState) {
              final hasText = controller.inputCtrl.text.isNotEmpty;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller.inputCtrl,
                          focusNode: controller.focusNode,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: '基于材料提问…',
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
                                      controller.inputCtrl.clear();
                                      setLocalState(() {});
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (_) => setLocalState(() {}),
                          onSubmitted: (v) {
                            if (v.trim().isEmpty || controller.loading.value) {
                              return;
                            }
                            controller.send(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<bool>(
                        valueListenable: controller.loading,
                        builder: (ctx, loading, _) {
                          if (loading) {
                            return IconButton.filled(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.red[400],
                              ),
                              onPressed: controller.stop,
                              tooltip: '停止生成',
                              icon: const Icon(Icons.stop, size: 18),
                            );
                          }
                          return IconButton.filled(
                            onPressed: !hasText
                                ? null
                                : () => controller.send(controller.inputCtrl.text),
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
      ),
    );
  }

  Widget _buildBubble(BuildContext context, FollowUpMessage msg, int index) {
    final theme = Theme.of(context);
    if (msg.role != 'user') {
      return AiFollowUpBubble(
        message: msg,
        avatar: aiAvatar(radius: 14, modelName: msg.model ?? controller.model),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: GestureDetector(
              onLongPress: () =>
                  _showEditDialog(context, controller, index, msg.content),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90D9).withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        msg.content,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _showEditDialog(
                        context,
                        controller,
                        index,
                        msg.content,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          userAvatar(context: context, radius: 14),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    FollowUpController controller,
    int index,
    String original,
  ) {
    final ctrl = TextEditingController(text: original);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑提问'),
        content: TextField(
          controller: ctrl,
          minLines: 1,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newText = ctrl.text.trim();
              ctrl.dispose();
              Navigator.pop(ctx);
              if (newText.isEmpty || newText == original) return;
              controller.editMessage(index, newText);
            },
            child: const Text('修改并重新发送'),
          ),
        ],
      ),
    );
  }

  void _showHistoryPicker(BuildContext context, FollowUpController controller) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text(
                      '历史追问',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      // P2-28:此前这一下就把整库历史追问删光,无确认、无反馈
                      onPressed: () => _confirmClearAll(ctx, controller),
                      child: const Text(
                        '清空全部',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.savedConversations.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '暂无保存的对话',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else
                ...List.generate(controller.savedConversations.length, (i) {
                  final conv = controller.savedConversations[i];
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
                      // P2-28:单条历史也是永久删除,同样先确认;删除后给反馈。
                      // 用 conv 对象定位而不是下标 —— 确认弹窗期间列表可能变化
                      onPressed: () =>
                          _deleteConversation(ctx, controller, conv),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      controller.loadConversation(conv);
                    },
                  );
                }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// 清空全部历史追问(P2-28):一次性、不可撤销的永久删除,
  /// 必须先确认;删完给一条"已清空"的反馈,否则用户不知道点没点上。
  ///
  /// [panelCtx] 是历史面板(showModalBottomSheet 那条路由)的 context:
  /// 确认弹窗与关闭面板都用它,不能拿抽屉自己的 context —— 那样会关错路由。
  Future<void> _confirmClearAll(
    BuildContext panelCtx,
    FollowUpController controller,
  ) async {
    final count = controller.savedConversations.length;
    final ok = await confirmDestructive(
      panelCtx,
      title: '清空历史追问',
      message: '将删除全部 $count 条已保存的追问对话，删除后不可恢复。',
      confirmText: '清空',
    );
    if (!ok || !panelCtx.mounted) return;
    controller.savedConversations.clear();
    try {
      await Hive.box(
        AppConstants.hiveBoxSettings,
      ).delete(controller.historyKey);
    } catch (e) {
      debugPrint('ReadFlow clearFollowUpHistory: $e');
    }
    if (!panelCtx.mounted) return;
    _closePanelWithFeedback(panelCtx, '已清空历史追问');
  }

  /// 删除一条已保存的追问(P2-28):单条也是永久删除,同样先确认再删、
  /// 删完给反馈(此前是单击即从 Hive 里抹掉,删错了没有任何补救机会)。
  Future<void> _deleteConversation(
    BuildContext panelCtx,
    FollowUpController controller,
    FollowUpSavedConversation conv,
  ) async {
    final ok = await confirmDestructive(
      panelCtx,
      title: '删除追问记录',
      message: '确定删除「${conv.title}」吗？删除后不可恢复。',
    );
    if (!ok || !panelCtx.mounted) return;
    controller.savedConversations.remove(conv);
    try {
      await Hive.box(AppConstants.hiveBoxSettings).put(
        controller.historyKey,
        controller.savedConversations.map((c) => c.toJson()).toList(),
      );
    } catch (e) {
      debugPrint('ReadFlow deleteFollowUpHistory: $e');
    }
    if (!panelCtx.mounted) return;
    _closePanelWithFeedback(panelCtx, '已删除追问记录');
  }

  /// 先弹反馈、再关历史面板。
  /// 顺序不能反:SnackBar 是挂在下面的 Scaffold 上的,面板还盖在屏幕上时
  /// 先弹出来会被面板挡住(弹出动画与面板收起动画同时进行,收完就看得见)。
  void _closePanelWithFeedback(BuildContext panelCtx, String message) {
    showFeedbackSnack(panelCtx, message);
    Navigator.pop(panelCtx);
  }
}

/// 追问抽屉专用的紧凑模型/思考选择器 — 主/副双槽位分组。
class CompactModelPicker extends StatelessWidget {
  final FollowUpController controller;

  const CompactModelPicker({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: controller.slotNotifier,
      builder: (_, _, _) => _buildMenu(context),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final theme = Theme.of(context);
    final secConfigured = ApiEndpointConfig.secondary.isConfigured;
    final isSecondary = controller.slot == 'secondary' && secConfigured;
    final primaryModels = primaryModelChoices();
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
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return PopupMenuButton<String>(
      offset: const Offset(0, 200),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 420),
      itemBuilder: (_) => [
        groupTitle(isSecondary ? '主 API(多模态)' : '主 API'),
        ...primaryModels.map((m) {
          final isSel = controller.slot == 'primary' && m == controller.model;
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
        const PopupMenuDivider(),
        groupTitle(secConfigured ? '副 API(专项文本)' : '副 API(专项文本 · 未配置)'),
        if (!secConfigured)
          PopupMenuItem(
            enabled: false,
            height: 36,
            child: Text(
              '到「我的 → API 设置」填写副 API Key 后即可切换',
              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
            ),
          )
        else
          ...secModels.map((m) {
            final isSel =
                controller.slot == 'secondary' && m == controller.model;
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
        ...AppConstants.followUpThinkingOptionsFor(controller.endpoint.model)
            .entries
            .map((e) {
          final isSel = e.key == controller.thinking;
          return PopupMenuItem(
            value: 'think:${e.key}',
            height: 30,
            child: Row(
              children: [
                Icon(
                  isSel ? Icons.lightbulb : Icons.lightbulb_outline,
                  size: 12,
                  color: isSel ? Colors.orange : theme.colorScheme.onSurfaceVariant,
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
        final box = Hive.box(AppConstants.hiveBoxSettings);
        if (v.startsWith('primary:')) {
          box.put(AppConstants.keyDoubaoModel, v.substring(8));
          box.put(AppConstants.keyFollowUpSlot, 'primary');
        } else if (v.startsWith('secondary:')) {
          box.put(AppConstants.keyDeepseekModel, v.substring(10));
          box.put(AppConstants.keyFollowUpSlot, 'secondary');
        } else if (v.startsWith('think:')) {
          box.put(AppConstants.keyFollowUpThinking, v.substring(6));
        }
        controller.slotNotifier.value = controller.slot;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isSecondary ? '副·' : '主·',
              style: TextStyle(
                fontSize: 9,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              controller.model.length > 16
                  ? '${controller.model.substring(0, 16)}…'
                  : controller.model,
              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
            ),
            Icon(Icons.arrow_drop_down, size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
