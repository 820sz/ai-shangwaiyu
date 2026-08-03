import 'package:flutter/material.dart';
import '../../services/material_search_service.dart';
import 'widgets/material_search_result_card.dart';

/// AI 学习材料推荐结果页
class AiMaterialSearchScreen extends StatefulWidget {
  final String category;

  const AiMaterialSearchScreen({super.key, required this.category});

  @override
  State<AiMaterialSearchScreen> createState() =>
      _AiMaterialSearchScreenState();
}

class _AiMaterialSearchScreenState extends State<AiMaterialSearchScreen> {
  final MaterialSearchService _service = MaterialSearchService();

  List<Map<String, String>>? _materials;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final materials =
          await _service.searchMaterials(widget.category);
      if (mounted) {
        setState(() {
          _materials = materials;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    // 加载中
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'AI 正在为您搜索「${widget.category}」相关学习材料…',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // 错误
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text(
                _error!.contains('API Key')
                    ? '请先在「我的 → API 设置」中配置豆包 API Key'
                    : '搜索失败',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              if (_error!.contains('API Key'))
                TextButton(
                  onPressed: () {
                    // 导航到 API 设置
                    Navigator.pop(context);
                    // 通过 app.dart 的 IndexedStack 切换到 profile tab 比较困难
                    // 这里简单提示用户手动切换
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请切换到底部「我的」标签 → API 设置')),
                    );
                  },
                  child: const Text('前往设置'),
                )
              else
                TextButton(
                  onPressed: _search,
                  child: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }

    // 空结果
    if (_materials == null || _materials!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'AI 未找到合适的材料，请换个分类试试',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _search,
              child: const Text('重新搜索'),
            ),
          ],
        ),
      );
    }

    // 结果列表
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _materials!.length + 1,
        itemBuilder: (context, index) {
          if (index == _materials!.length) {
            return const SizedBox(height: 80);
          }
          final m = _materials![index];
          return MaterialSearchResultCard(
            name: m['name'] ?? '',
            description: m['description'] ?? '',
            level: m['level'] ?? '',
            keywords: m['keywords'] ?? '',
          );
        },
      ),
    );
  }
}
