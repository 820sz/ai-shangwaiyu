import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';

import '../../models/material_recommendation.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/base_api.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/learner_model_store.dart';
import '../../services/learner_profile_store.dart';
import '../../services/material_recommend_service.dart';
import 'learner_profile_screen.dart';
import 'learner_preferences_screen.dart';
import 'material_recommendation_detail_screen.dart';

/// AI 学习资源推荐(v1.8.0 重做)。
///
/// 相比旧版(只能看到标题、每次进来重新识别):
/// - 依据**学习画像**(用户填写/按词汇推断,可改)+ **真实词汇数据**推荐
/// - 推荐清单落库,下次进来直接读缓存;要新的点「重新推荐」
/// - 每条都能点进去看**可学习的内容**(流式生成并缓存)
class AiMaterialSearchScreen extends StatefulWidget {
  final String category;

  const AiMaterialSearchScreen({super.key, required this.category});

  @override
  State<AiMaterialSearchScreen> createState() =>
      _AiMaterialSearchScreenState();
}

class _AiMaterialSearchScreenState extends State<AiMaterialSearchScreen> {
  final _api = DoubaoApiService();

  LearnerProfile _profile = const LearnerProfile();
  /// 学习者模型(v2.0):只取题材黑名单用 —— 推荐结果与缓存列表都要过它
  LearnerModel _learner = LearnerModel();
  List<MaterialRecommendation> _saved = [];
  bool _loadingSaved = true;
  bool _generating = false;
  String _streamText = '';
  String? _error;
  StreamSubscription<SseChunk>? _sub;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _profile = LearnerProfileStore.load();
    // P2-10:_bootstrap 第一行就 context.read,进页立刻返回时 element 已
    // deactivate → 抛错并被 CrashLogger 记成"崩溃",污染诊断日志
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    // P2-34:总超时/「取消生成」用的令牌也要随页面销毁释放,否则请求仍挂着
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final vocab = context.read<VocabProvider>();
    if (vocab.vocabularies.isEmpty) {
      await vocab.loadVocabularies();
    }
    // 没填过画像 → 用词汇数据给一版建议(仍然可编辑)
    if (_profile.isEmpty) {
      _profile = LearnerProfileStore.suggestFromVocab(vocab.vocabularies);
    }
    _learner = LearnerModelStore.load();
    await _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await DatabaseService.getRecommendations(
      category: widget.category,
    );
    if (mounted) {
      setState(() {
        _saved = saved;
        _loadingSaved = false;
      });
    }
  }

  Future<void> _editProfile() async {
    final result = await Navigator.push<LearnerProfile>(
      context,
      MaterialPageRoute(builder: (_) => const LearnerProfileScreen()),
    );
    if (result != null && mounted) {
      setState(() => _profile = result);
    }
  }

  /// 题材黑名单(v2.0):用户在这里维护,推荐与列表立刻遵守
  Future<void> _editPreferences() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LearnerPreferencesScreen()),
    );
    if (!mounted) return;
    // 回来重读黑名单并重算过滤(可能刚屏蔽了当前列表里的东西)
    setState(() => _learner = LearnerModelStore.load());
  }

  /// 流式生成推荐清单(结果落库,可反复查看)
  ///
  /// v1.9.0 修复:
  /// - **思考通道兜底**(P1-6):DeepSeek 思考模型常把 JSON 整段写在
  ///   reasoning_content 里;旧实现 `if (chunk.isReasoning) return;` 直接丢弃,
  ///   于是开着高思考档时这里必然报"未返回可解析的推荐清单"。
  /// - **可取消 + 总超时**(P2-34):旧实现只 `await done.future`,
  ///   模型一直吐字但永不结束时页面永久卡在"AI 正在推荐…"且无法取消。
  /// - **原子替换**(P2-2):走 `replaceRecommendations` 单事务,
  ///   不再"先清空再逐条插入"(中途失败会连已生成的学习内容一起丢)。
  Future<void> _generate({bool replace = false}) async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _streamText = '';
      _error = null;
    });
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    try {
      final vocab = context.read<VocabProvider>().vocabularies;
      final stream = _api.streamPrompt(
        system: MaterialRecommendService.recommendationSystemPrompt,
        user: MaterialRecommendService.recommendationUserPrompt(
          profile: _profile,
          vocab: vocab,
          category: widget.category,
          // 黑名单进提示词(让模型别推),本地过滤再兜底
          blockedTopics: _learner.blockedTopics,
          blockedKeywords: _learner.blockedKeywords,
        ),
        cancelToken: cancelToken,
      );
      final buffer = StringBuffer();
      final reasoningBuffer = StringBuffer();
      final done = Completer<void>();
      _sub = stream.listen(
        (chunk) {
          if (chunk.isReasoning) {
            // 思考过程不展示,但要留作兜底(P1-6)
            reasoningBuffer.write(chunk.text);
            return;
          }
          buffer.write(chunk.text);
          if (mounted) setState(() => _streamText = buffer.toString());
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (e) {
          if (!done.isCompleted) done.completeError(e);
        },
        cancelOnError: false,
      );
      // 总预算 180s:模型持续吐字但永不结束时不至于永久卡住(P2-34)
      await done.future.timeout(
        const Duration(seconds: 180),
        onTimeout: () {
          _sub?.cancel();
          throw Exception('生成超时(180s),已中止。可重试或降低思考档位');
        },
      );

      // 结果来源:正文优先,正文解析不出再从思考通道抠(P1-6)
      var items = MaterialRecommendService.parseRecommendations(
        buffer.toString(),
        category: widget.category,
        profileSnapshot: _profile.summaryText,
      );
      if (items.isEmpty) {
        final raw = buffer.toString().trim().isNotEmpty
            ? buffer.toString()
            : reasoningBuffer.toString();
        final extracted = DoubaoApiService.extractJsonBlock(raw);
        if (extracted.isNotEmpty) {
          items = MaterialRecommendService.parseRecommendations(
            extracted,
            category: widget.category,
            profileSnapshot: _profile.summaryText,
          );
        }
      }
      if (items.isEmpty) {
        throw Exception('AI 未返回可解析的推荐清单');
      }
      // 题材黑名单(v2.0):入库前先滤掉 —— 提示词只是"请模型避开",
      // 模型不听话时由代码兜底;顺手也让缓存/库表不再存用户明确不想看的东西。
      // 被滤掉多少仍然要告诉用户(build 里按 _saved 总数再算一次并显示)。
      final blocked = MaterialRecommendService.blockedCount(
        items,
        blockedTopics: _learner.blockedTopics,
        blockedKeywords: _learner.blockedKeywords,
      );
      final kept = MaterialRecommendService.filterBlocked(
        items,
        blockedTopics: _learner.blockedTopics,
        blockedKeywords: _learner.blockedKeywords,
      );
      if (kept.isEmpty) {
        throw Exception(
          'AI 推荐的 ${items.length} 条都命中了你屏蔽的题材/关键词,'
          '可在右上角「不想看的题材」里调整',
        );
      }
      if (replace) {
        // 原子替换(P2-2):清空 + 插入在同一事务里,失败整体回滚
        await DatabaseService.replaceRecommendations(widget.category, kept);
      } else {
        for (final item in kept) {
          await DatabaseService.insertRecommendation(item);
        }
      }
      await _loadSaved();
      if (mounted) {
        setState(() => _streamText = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              blocked > 0
                  ? '已生成 ${kept.length} 条推荐并保存,按你的偏好屏蔽了 $blocked 条'
                  : '已生成 ${kept.length} 条推荐并保存',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = BaseApiService.friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 题材黑名单(v2.0):缓存列表与刚生成的结果都过同一道过滤 ——
    // 只过滤新结果的话,上次生成里被屏蔽的条目会从缓存里"复活"
    final visible = MaterialRecommendService.filterBlocked(
      _saved,
      blockedTopics: _learner.blockedTopics,
      blockedKeywords: _learner.blockedKeywords,
    );
    final hidden = _saved.length - visible.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category),
        actions: [
          IconButton(
            tooltip: '不想看的题材',
            icon: const Icon(Icons.block),
            onPressed: _editPreferences,
          ),
          IconButton(
            tooltip: '学习画像',
            icon: const Icon(Icons.person_outline),
            onPressed: _editProfile,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _profileCard(theme),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _generating ? null : () => _generate(replace: true),
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    _generating
                        ? 'AI 正在推荐…'
                        : (_saved.isEmpty ? 'AI 推荐材料' : '重新推荐'),
                  ),
                ),
              ),
            ],
          ),
          if (_generating)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () {
                  // P2-34:长生成可中止(取消后保留已生成片段)
                  _cancelToken?.cancel('用户取消');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已取消生成，已生成的部分保留在下方'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.stop, size: 16),
                label: const Text('取消生成'),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ],
          if (_generating) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.primary.withAlpha(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _streamText.isEmpty ? '正在思考…' : _streamText,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_loadingSaved)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_saved.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '还没有推荐，点上面按钮让 AI 按你的水平挑材料',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else ...[
            Text(
              '推荐材料（${visible.length}）',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            // 屏蔽不静默(v2.0):告诉用户挡掉了几条,并给入口去看/改黑名单
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.block,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '已按你的偏好屏蔽 $hidden 条',
                        style: TextStyle(
                          fontSize: 12,
                          // P2-31:次要文字用主题色,深浅色都达 AA
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _editPreferences,
                      child: const Text('调整'),
                    ),
                  ],
                ),
              ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '当前 ${_saved.length} 条推荐都被你的屏蔽条件挡住了',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              )
            else
              ...visible.map((r) => _recommendationCard(theme, r)),
          ],
        ],
      ),
    );
  }

  Widget _profileCard(ThemeData theme) {
    final hasProfile = !_profile.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.person_outline, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasProfile ? _profile.summaryText : '还没填学习画像（点右侧填写）',
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
            TextButton(
              onPressed: _editProfile,
              child: Text(hasProfile ? '修改' : '填写'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recommendationCard(ThemeData theme, MaterialRecommendation r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Row(
          children: [
            Expanded(
              child: Text(
                r.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (r.level.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.level,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.summary.isNotEmpty)
                Text(r.summary, style: const TextStyle(fontSize: 12)),
              if (r.reason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '为什么推荐：${r.reason}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (r.hasContent)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '已生成学习内容',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: '删除',
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () async {
            if (r.id != null) {
              await DatabaseService.deleteRecommendation(r.id!);
            }
            await _loadSaved();
          },
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MaterialRecommendationDetailScreen(
                recommendation: r,
                profile: _profile,
              ),
            ),
          );
          await _loadSaved(); // 详情页可能生成了内容
        },
      ),
    );
  }
}
