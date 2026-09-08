import 'dart:io';

import 'package:image/image.dart' as img;

/// 图标替换脚本:assets/icon_new.png/webp → 5 个 mipmap 密度。
/// 用法:dart run tool/make_icon.dart
/// (v1.2.14 同款做法:用户定稿图直接缩放替换,不做任何处理)
void main() {
  final source = File('assets/icon_new.png');
  if (!source.existsSync()) {
    stderr.writeln('找不到 assets/icon_new.png');
    exit(1);
  }
  final decoded = img.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('图片解码失败');
    exit(1);
  }
  final sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  sizes.forEach((dir, size) {
    final resized = img.copyResize(decoded, width: size, height: size);
    final path = 'android/app/src/main/res/$dir/ic_launcher.png';
    File(path).writeAsBytesSync(img.encodePng(resized));
    stdout.writeln('$path <- ${decoded.width}x${decoded.height} -> ${size}x$size');
  });
  stdout.writeln('图标替换完成');
}
