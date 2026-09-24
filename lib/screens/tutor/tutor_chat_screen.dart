import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/constants.dart';
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

  const TutorChatScreen({super.key, required this.snapshot});

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
      final rows = await DatabaseService.getTutorMessages(limit: 50);
      if (!mounted) return;
      setState(() {
        _turns
          ..clear()
          ..addAll(rows.map((m) => _Turn(
                isUser: '${m['role']}' == 'user',
                text: '${m['content'] ?? ''}',
              )));
        _loadingHistory = false;
      });
      _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      debugPrint('ReadFlow 读取助理会话失败: $e');
    }
  }

  Future<void> _ask(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || _asking) return;
    _inputCtrl.clear();
    final findings = TutorEngine.diagnose(widget.snapshot);
    setState(() {
      _turns.add(_Turn(isUser: true, text: q));
      _turns.add(const _Turn(isUser: false, text: ''));
      _asking = true;
      _reasoning = '';
    });
    await DatabaseService.insertTutorMessage(role: 'user', content: q);
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
        await DatabaseService.insertTutorMessage(role: 'tutor', content: answer);
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
        title: const Text('和助理聊聊'),
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
                          style: IconButton.styleFrom(backgroundColor: Colors.red[400]),
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
                aiAvatar(radius: 14, modelName: _model),
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
              color: const Color(0xFF4A90D9).withAlpha(20),
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
          aiAvatar(radius: 14, modelName: _model),
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
