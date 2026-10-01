import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../services/api_endpoint.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/tutor_engine.dart';
import '../input/widgets/follow_up_bubble.dart' show ThinkingBlock;
import '../input/widgets/model_avatars.dart';

/// 与学习助理的**独立对话窗口**(v2.4,C1 用户要求)。
///
/// 用户原话:"对话功能需要弄个窗口,点进去后是单独的 ai 对话,不要像现在这样
/// 对话留在「学习助理」功能页 —— 同样要支持 ai 头像、读取用户软件内所有需要的数据、
/// 流式输出和思考、思考强度选择。"
///
/// 设计要点:
/// - **证据包照旧**:回答只依据 [TutorEngine.evidencePrompt] 给出的真实快照
///   (全部本地数据:词汇量/复习/阅读/测验/错误/习惯),禁止编造;
/// - **流式 + 思考分开**:正文边收边显示,思考过程收在可折叠块里(与追问一致);
/// - **思考强度可选**:识图固定低档(那是照抄任务),这里保留用户选择的档位 ——
///   规划类问题值得多想一会儿;
/// - 消息落库(tutor_messages),换页/重启都还在。
class TutorChatScreen extends StatefulWidget {
  /// 本地诊断快照(与「学习助理」页同一个,不在对话页重复加载)
  final LearnerSnapshot snapshot;

  /// 指定会话(v2.8,用户第 5(2) 条)。
  /// null = 用最近一个会话;一个都没有则在用户第一次提问时自动新建。
  final int? conversationId;

  /// 进来时的开场问题(v2.8:从「学习现状分析」等入口带着问题进来)
  final String? initialQuestion;

  const TutorChatScreen({
    super.key,
    required this.snapshot,
    this.conversationId,
    this.initialQuestion,
  });

  @override
  State<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends State<TutorChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _api = DoubaoApiService();

  final List<_Turn> _turns = [];
  bool _asking = false;
  bool _loadingHistory = true;
  String _reasoning = '';
  String _model = '';

  /// 当前会话 id(null = 还没建,首条提问时建;v2.8 用户第 5(2) 条)
  int? _conversationId;

  /// 当前会话标题(AppBar 显示 + 重命名用)
  String _title = '新对话';

  /// 当前思考档位(默认跟随全局设置)
  late String _thinking;

  static const List<String> _presets = [
    '我现在该读什么难度的材料?',
    '为什么我的复习总是堆着?',
    '帮我排一下这周的学习安排',
    '我最近哪块最薄弱?',
  ];

  @override
  void initState() {
    super.initState();
    _model = ApiEndpointConfig.primary.model;
    _thinking = ApiEndpointConfig.primary.thinking;
    _conversationId = widget.conversationId;
    _loadHistory();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      var id = _conversationId;
      if (id == null) {
        // 没指定就用最近一个会话;一个都没有就留空,等首条提问时再建
        final convs = await DatabaseService.getTutorConversations(limit: 1);
        if (convs.isNotEmpty) {
          id = convs.first['id'] as int?;
          _title = '${convs.first['title'] ?? '新对话'}';
        }
      } else {
        final convs = await DatabaseService.getTutorConversations(limit: 100);
        for (final c in convs) {
          if (c['id'] == id) _title = '${c['title'] ?? '新对话'}';
        }
      }
      final rows = await DatabaseService.getTutorMessages(
        limit: 60,
        conversationId: id,
      );
      if (!mounted) return;
      setState(() {
        _conversationId = id;
        _turns
          ..clear()
          ..addAll(rows.map((m) => _Turn(
                isUser: '${m['role']}' == 'user',
                text: '${m['content'] ?? ''}',
              )));
        _loadingHistory = false;
      });
      _jumpToBottom();
      // 带着开场问题进来(用户从「让 AI 帮我规划」这类入口点进来)
      final q = widget.initialQuestion?.trim() ?? '';
      if (q.isNotEmpty && rows.isEmpty) {
        await _ask(q);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      debugPrint('ReadFlow 读取助理会话失败: $e');
    }
  }

  /// 保证有一个会话(首次提问时创建;v2.8 用户第 5(2) 条"新建/多开")
  Future<int?> _ensureConversation(String firstQuestion) async {
    if (_conversationId != null && _conversationId! > 0) {
      return _conversationId;
    }
    final id = await DatabaseService.createTutorConversation(
      title: '新对话',
      kind: 'chat',
    );
    if (id <= 0) return null;
    await DatabaseService.autoTitleTutorConversation(id, firstQuestion);
    final convs = await DatabaseService.getTutorConversations(limit: 100);
    for (final c in convs) {
      if (c['id'] == id) _title = '${c['title'] ?? '新对话'}';
    }
    if (mounted) setState(() => _conversationId = id);
    return id;
  }

  /// 新建对话(清空当前视图,下一条消息进新会话)
  Future<void> _newConversation() async {
    final id = await DatabaseService.createTutorConversation(
      title: '新对话',
      kind: 'chat',
    );
    if (!mounted) return;
    setState(() {
      _conversationId = id > 0 ? id : null;
      _title = '新对话';
      _turns.clear();
      _reasoning = '';
    });
    _inputCtrl.clear();
  }

  /// 历史对话列表:点选切换、可删
  Future<void> _showConversations() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) =>
            FutureBuilder<List<Map<String, Object?>>>(
          future: DatabaseService.getTutorConversations(limit: 50),
          builder: (ctx, snap) {
            final list = snap.data ?? const <Map<String, Object?>>[];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.xs, Gap.xs),
                  child: Row(
                    children: [
                      const Text('历史对话',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _newConversation();
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新对话'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('还没有对话'))
                      : ListView.builder(
                          controller: scrollCtrl,
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final c = list[i];
                            final id = c['id'] as int?;
                            final selected = id == _conversationId;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              leading: Icon(
                                selected
                                    ? Icons.chat_bubble
                                    : Icons.chat_bubble_outline,
                                size: 18,
                              ),
                              title: Text('${c['title'] ?? '新对话'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(
                                _fmtTime(
                                    '${c['updated_at'] ?? c['created_at'] ?? ''}'),
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: IconButton(
                                tooltip: '删除这个对话',
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () async {
                                  if (id == null) return;
                                  final nav = Navigator.of(ctx);
                                  await DatabaseService.deleteTutorConversation(id);
                                  if (!mounted) return;
                                  nav.pop();
                                  if (id == _conversationId) {
                                    setState(() {
                                      _conversationId = null;
                                      _turns.clear();
                                      _title = '新对话';
                                      _loadingHistory = true;
                                    });
                                    await _loadHistory();
                                  }
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                if (id == null || id == _conversationId) return;
                                setState(() {
                                  _conversationId = id;
                                  _loadingHistory = true;
                                  _turns.clear();
                                });
                                _loadHistory();
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: Gap.sm),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 改对话标题(用户第 5(2) 条"编辑对话标题")
  Future<void> _renameConversation() async {
    final ctrl = TextEditingController(text: _title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('改对话标题'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '如:六级冲刺规划',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final id = _conversationId;
    if (id == null || id <= 0) {
      setState(() => _title = name);
      return;
    }
    await DatabaseService.renameTutorConversation(id, name);
    if (!mounted) return;
    setState(() => _title = name);
  }

  /// 清空当前对话(用户第 5(2) 条"清除聊天")
  Future<void> _clearCurrent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空这个对话?'),
        content: const Text('只清空当前的对话内容;助理记住的偏好与结论(长期记忆)会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await DatabaseService.clearTutorMessages(conversationId: _conversationId);
    if (!mounted) return;
    setState(() {
      _turns.clear();
      _reasoning = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已清空这个对话(长期记忆保留)'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _fmtTime(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '今天 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.month}/${t.day} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _ask(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || _asking) return;
    _inputCtrl.clear();
    final convId = await _ensureConversation(q);
    final findings = TutorEngine.diagnose(widget.snapshot);
    if (!mounted) return;
    setState(() {
      _turns.add(_Turn(isUser: true, text: q));
      _turns.add(const _Turn(isUser: false, text: ''));
      _asking = true;
      _reasoning = '';
    });
    await DatabaseService.insertTutorMessage(
      role: 'user',
      content: q,
      conversationId: convId,
    );
    _jumpToBottom();

    final history = <Map<String, String>>[
      for (final t in _turns.take(_turns.length - 2))
        {
          'role': t.isUser ? 'user' : 'assistant',
          'content': t.text,
        },
    ];

    final buffer = StringBuffer();
    final reasoning = StringBuffer();
    try {
      await for (final chunk in _api.followUpStream(
        q,
        context: _systemPrompt(
          TutorEngine.evidencePrompt(widget.snapshot, findings),
        ),
        history: history,
        thinkingLevel: _thinking,
      )) {
        if (!mounted) return;
        if (chunk.isReasoning) {
          reasoning.write(chunk.text);
          setState(() => _reasoning = reasoning.toString());
          continue;
        }
        buffer.write(chunk.text);
        setState(() {
          _turns[_turns.length - 1] = _Turn(isUser: false, text: buffer.toString());
        });
        _jumpToBottom();
      }
      final answer = buffer.isEmpty ? '(没有拿到回复,请重试)' : buffer.toString();
      if (mounted && buffer.isEmpty) {
        setState(() => _turns[_turns.length - 1] = _Turn(isUser: false, text: answer));
      }
      if (!answer.startsWith('(')) {
        await DatabaseService.insertTutorMessage(
          role: 'tutor',
          content: answer,
          conversationId: convId,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _turns[_turns.length - 1] = _Turn(isUser: false, text: '出错了:$e'));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  String _systemPrompt(String evidence) => '''
你是这位学习者的私人英语导师。你**只能基于下面给出的数据快照与本地诊断结论**回答,
禁止编造数据、禁止编造材料名、禁止给出与数据矛盾的判断。

回答要求:
1. 先给结论,再给依据(引用具体数字);
2. 给可执行的下一步(具体到"读什么/读多少/几分钟/练什么");
3. 数据不足以判断时,直接说"我缺 X 信息",并向用户提 1-2 个具体问题;
4. 不要说"加油""坚持就是胜利"这类空话;回答控制在 300 字内。

$evidence''';

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        // v2.8:标题就是**当前对话标题**(可改),右边是对话管理(用户第 5(2) 条)
        title: InkWell(
          onTap: _renameConversation,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(_title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
        actions: [
          // 思考强度:规划类问题值得多想;识图那条链路固定低档,不受这里影响
          PopupMenuButton<String>(
            tooltip: '思考强度',
            onSelected: (v) => setState(() => _thinking = v),
            itemBuilder: (_) => [
              for (final e in AppConstants.thinkingOptionsFor(_model).entries)
                PopupMenuItem(
                  value: e.key,
                  child: Row(
                    children: [
                      if (e.key == _thinking)
                        Icon(Icons.check, size: 16, color: theme.colorScheme.primary)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 6),
                      Text(e.value),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(Icons.psychology_outlined, size: 18, color: muted),
                  const SizedBox(width: 4),
                  Text(
                    AppConstants.thinkingOptionsFor(_model)[_thinking] ?? _thinking,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ),
          // 对话管理:新建 / 历史 / 改名 / 清空
          PopupMenuButton<String>(
            tooltip: '对话管理',
            onSelected: (v) {
              switch (v) {
                case 'new':
                  _newConversation();
                case 'history':
                  _showConversations();
                case 'rename':
                  _renameConversation();
                case 'clear':
                  _clearCurrent();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('新建对话')),
              PopupMenuItem(value: 'history', child: Text('历史对话(可删除)')),
              PopupMenuItem(value: 'rename', child: Text('改标题')),
              PopupMenuItem(value: 'clear', child: Text('清空这个对话')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    children: [
                      if (_turns.isEmpty) _buildIntro(theme, muted),
                      for (var i = 0; i < _turns.length; i++)
                        _buildTurn(theme, muted, i),
                      if (_asking && _reasoning.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 34),
                          child: ThinkingBlock(
                            text: _reasoning,
                            expanded: false,
                            streaming: true,
                            onToggle: () => setState(() {}),
                          ),
                        ),
                    ],
                  ),
          ),
          // 预设问题(第一次打开时最有用)
          if (_turns.isEmpty)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _presets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_presets[i], style: const TextStyle(fontSize: 12)),
                  onPressed: _asking ? null : () => _ask(_presets[i]),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '问助理任何关于你学习的问题…',
                        isDense: true,
                      ),
                      onSubmitted: _ask,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _asking
                      ? IconButton.filled(
                          style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.error),
                          onPressed: () => setState(() => _asking = false),
                          tooltip: '停止显示',
                          icon: const Icon(Icons.stop, size: 18),
                        )
                      : FilledButton(
                          onPressed: () => _ask(_inputCtrl.text),
                          child: const Text('发送'),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro(ThemeData theme, Color muted) {
    return Card(
      color: theme.colorScheme.primary.withAlpha(10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                aiAvatar(radius: 14, modelName: _model, context: context),
                const SizedBox(width: 8),
                Text('助理知道你现在的全部学习数据',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '· 词汇量 ${widget.snapshot.model.summaryText.isEmpty ? '(未测得)' : widget.snapshot.model.summaryText}\n'
              '· 待复习 ${widget.snapshot.dueReviewCount} 个 · 读过 ${widget.snapshot.materialsFinished} 份材料\n'
              '· 答案只依据这些真实数据,不会编造',
              style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text('可以直接问下面的问题,或自己打字:',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildTurn(ThemeData theme, Color muted, int index) {
    final t = _turns[index];
    if (t.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 40),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(t.text, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ),
      );
    }
    // 流式进行中的那条:没有内容时先显示"正在思考…",不要留空白气泡
    final streaming = _asking && index == _turns.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          aiAvatar(radius: 14, modelName: _model, context: context),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: t.text.isEmpty && streaming
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text('正在思考…',
                            style: TextStyle(fontSize: 12, color: muted)),
                      ],
                    )
                  : SelectableText(
                      t.text,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Turn {
  final bool isUser;
  final String text;

  const _Turn({required this.isUser, required this.text});
}
