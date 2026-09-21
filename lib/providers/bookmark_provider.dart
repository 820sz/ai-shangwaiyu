import 'package:flutter/foundation.dart';

import '../models/bookmark.dart';
import '../services/database.dart';

/// 收藏夹 Provider(v1.4.0 问题 8/9):
/// 内存缓存 + 变更通知;isBookmarked 供 UI 星标状态判断。
class BookmarkProvider extends ChangeNotifier {
  List<Bookmark> _items = [];
  bool _loaded = false;

  /// 加载失败原因(P2-30 三态):页面据此区分
  /// 「加载失败,可重试」与「还没有收藏」。
  /// 只记录 [load] 的失败——删除失败不该把整页变成错误态。
  String? _error;

  List<Bookmark> get items => _items;
  bool get loaded => _loaded;
  String? get error => _error;

  Future<void> load() async {
    try {
      _items = await DatabaseService.getBookmarks();
      _loaded = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('ReadFlow bookmark load: $e');
      // 关键:失败必须留下痕迹。此前只 debugPrint,`_loaded` 停在 false
      // → 收藏夹永远转圈,用户既看不到原因也没有重试入口。
      _error = '收藏夹加载失败：$e';
      notifyListeners();
    }
  }

  /// 是否已收藏(按来源+内容精确匹配)
  bool isBookmarked(String source, String content) {
    return _items.any((b) => b.source == source && b.content == content);
  }

  /// 收藏/取消收藏(切换)。[build] 由调用方构造完整 Bookmark。
  /// 返回 true = 已收藏(刚插入);false = 已取消(刚删除)。
  /// 调用方据此提示,避免异步时序导致提示文案相反(v1.4.2)。
  Future<bool> toggle(Bookmark build) async {
    try {
      final existed = await DatabaseService.findBookmark(
        build.source,
        build.content,
      );
      if (existed != null) {
        await DatabaseService.deleteBookmark(existed.id!);
        _items = _items.where((b) => b.id != existed.id).toList();
        notifyListeners();
        return false;
      } else {
        final id = await DatabaseService.insertBookmark(build);
        _items = [
          Bookmark(
            id: id,
            source: build.source,
            title: build.title,
            content: build.content,
            sourceWord: build.sourceWord,
            model: build.model,
            createdAt: build.createdAt,
          ),
          ..._items,
        ];
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('ReadFlow bookmark toggle: $e');
      return false;
    }
  }

  Future<void> remove(int id) async {
    try {
      await DatabaseService.deleteBookmark(id);
      _items = _items.where((b) => b.id != id).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('ReadFlow bookmark remove: $e');
    }
  }
}
