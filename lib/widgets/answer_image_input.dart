import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/design_tokens.dart';
import '../config/v4_theme.dart';

/// 作答图片附件(v2.24,用户 2026-11-03:
/// "所有输出练习包括其他需要用户上传自己写的成果答案的地方,都要支持图片上传,
/// 现在只能打字")。
///
/// 为什么做成"附件 + 转写"而不是让批改模型直接吃图:
/// - 现有批改/判分链路全是**文本 + rubric**,直接改多模态要动每一条评分逻辑;
/// - 图片只是"另一种输入方式":先转写成文字,拼进原答案,再走同一套批改 ——
///   评分口径、折算档、错误归档都不用改,也不会因为某模型不支持图片而崩。
///
/// 本组件只负责"选图 / 预览 / 删除"三件事,上传和转写由调用方在提交时做,
/// 这样各页面可以自己决定"要不要先转写、转写失败怎么提示"。
class AnswerImageInput extends StatelessWidget {
  final List<File> images;
  final ValueChanged<List<File>> onChanged;
  final bool enabled;
  final int maxImages;
  final String hint;

  const AnswerImageInput({
    super.key,
    required this.images,
    required this.onChanged,
    this.enabled = true,
    this.maxImages = 6,
    this.hint = '答案也可以拍照上传 —— AI 会先转写成文字,再按同一套标准批改',
  });

  Future<void> _pick(BuildContext context, {required bool fromCamera}) async {
    if (images.length >= maxImages) {
      _toast(context, '最多 $maxImages 张图片');
      return;
    }
    final picker = ImagePicker();
    try {
      if (fromCamera) {
        final photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 72,
          maxWidth: 1800,
        );
        if (photo != null) {
          onChanged(<File>[...images, File(photo.path)]);
        }
      } else {
        final picked = await picker.pickMultiImage(
          imageQuality: 72,
          maxWidth: 1800,
          limit: maxImages - images.length,
        );
        if (picked.isNotEmpty) {
          onChanged(<File>[...images, ...picked.map((x) => File(x.path))]);
        }
      }
    } catch (e) {
      if (context.mounted) _toast(context, '没能打开图片:$e');
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (images.isNotEmpty) ...[
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.xs),
              itemBuilder: (_, i) => Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      images[i],
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      cacheWidth: 192,
                      errorBuilder: (_, _, _) => Container(
                        width: 64,
                        height: 64,
                        color: skin.surfaceAlt,
                        child: Icon(Icons.broken_image_outlined,
                            size: 18, color: skin.inkFaint),
                      ),
                    ),
                  ),
                  if (enabled)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: GestureDetector(
                        onTap: () {
                          final next = <File>[...images]..removeAt(i);
                          onChanged(next);
                        },
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: skin.ink.withValues(alpha: 0.72),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 13, color: skin.surface),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.xs),
        ],
        Row(
          children: <Widget>[
            _pillButton(
              context,
              icon: Icons.photo_camera_outlined,
              label: '拍照',
              skin: skin,
              onTap: enabled ? () => _pick(context, fromCamera: true) : null,
            ),
            const SizedBox(width: Gap.xs),
            _pillButton(
              context,
              icon: Icons.photo_library_outlined,
              label: '相册',
              skin: skin,
              onTap: enabled ? () => _pick(context, fromCamera: false) : null,
            ),
            if (images.isNotEmpty) ...[
              const SizedBox(width: Gap.xs),
              Text(
                '已附 ${images.length} 张',
                style: TextStyle(fontSize: 10.5, color: skin.inkFaint),
              ),
            ],
          ],
        ),
        if (images.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            style: TextStyle(fontSize: 10.5, color: skin.inkFaint),
          ),
        ],
      ],
    );
  }

  Widget _pillButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required V4Skin skin,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: skin.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: skin.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon,
                size: 15,
                color: onTap == null ? skin.inkFaint : skin.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: onTap == null ? skin.inkFaint : skin.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 把"文本 + 图片转写"合并成一份可交给批改的答案。
///
/// 纯函数(可单测):文本为空时只返回转写;转写为空时只返回文本;
/// 两者都有时用显式分隔,让批改模型能区分"用户原话"和"照片内容"。
String mergeAnswerWithTranscript(String text, String transcript) {
  final t = text.trim();
  final s = transcript.trim();
  if (s.isEmpty) return t;
  if (t.isEmpty) return s;
  return '$t\n\n【图片转写】\n$s';
}
