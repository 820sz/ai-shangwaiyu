/// 自动配图封面:先显示程序化封面,抓到/生成到真图后原地换上。
///
/// 为什么单独一个 wrapper 而不是把异步塞进 [MaterialCover]:
/// - MaterialCover 是纯展示组件(大量 const 调用点),保持无状态、零网络;
/// - 配图是"增强",失败必须无声无息退回程序化封面 —— 用 wrapper 才能
///   做到"没网/没图时行为与之前完全一致"。
///
/// 取图顺序见 `services/material_art.dart`:材料源已有图 → 豆瓣书封 →
/// 360 图片 → (可选)AI 生图 → 程序化封面。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../services/material_art.dart';
import 'material_cover.dart';

class ArtCover extends StatefulWidget {
  /// 材料标题(同时是程序化封面的 seed)
  final String title;

  /// 材料种类(book/news/paper/podcast/wiki/article)
  final String kind;

  /// 材料源自带的图(feed/og:image/库里 cover_url);有就优先用,抓取只作兜底
  final String? imageUrl;

  final double width;
  final double height;
  final double radius;
  final String? levelLabel;

  /// 是否允许联网抓图(列表里的小图也允许;抓完落盘,后续零网络)
  final bool enableFetch;

  const ArtCover({
    super.key,
    required this.title,
    this.kind = 'article',
    this.imageUrl,
    this.width = double.infinity,
    this.height = 168,
    this.radius = Radii.card,
    this.levelLabel,
    this.enableFetch = true,
  });

  @override
  State<ArtCover> createState() => _ArtCoverState();
}

class _ArtCoverState extends State<ArtCover> {
  File? _file;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _kick();
  }

  @override
  void didUpdateWidget(covariant ArtCover old) {
    super.didUpdateWidget(old);
    if (old.title != widget.title || old.kind != widget.kind) {
      _file = null;
      _started = false;
      _kick();
    }
  }

  /// 有源头图时不主动抓;只有"没图"或"源头图加载失败"才去抓。
  Future<void> _kick({bool force = false}) async {
    if (!widget.enableFetch || _started) {
      if (!force) return;
    }
    _started = true;
    try {
      final cached = await MaterialArt.cached(title: widget.title, kind: widget.kind);
      if (!mounted) return;
      if (cached != null) {
        setState(() => _file = cached);
        return;
      }
      final hasSource = (widget.imageUrl ?? '').trim().startsWith('http');
      if (hasSource && !force) return;
      final f = await MaterialArt.resolve(title: widget.title, kind: widget.kind);
      if (!mounted || f == null) return;
      setState(() => _file = f);
    } catch (_) {
      // 配图是增强:失败继续用程序化封面
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialCover(
      seed: widget.title,
      kind: widget.kind,
      imageUrl: widget.imageUrl,
      localImagePath: _file?.path,
      width: widget.width,
      height: widget.height,
      radius: widget.radius,
      levelLabel: widget.levelLabel,
      // 源头图挂了(图床被墙/防盗链/404) → 换成抓来的图
      onImageError: () => unawaited(_kick(force: true)),
    );
  }
}
