import 'package:flutter/material.dart';

/// 用户头像:主色圆 + 人形图标
Widget userAvatar({required BuildContext context, double radius = 16}) {
  return CircleAvatar(
    radius: radius,
    backgroundColor: Theme.of(context).colorScheme.primary,
    child: Icon(Icons.person, size: radius * 1.1, color: Colors.white),
  );
}

/// AI 头像：品牌Logo（ClipOval + errorBuilder 兜底）。
/// [modelName] 必传 —— 追问抽屉必须显式传当前追问槽位的模型名，
/// 否则头像永远按主模型显示（2026-08-04 追问头像 bug 修复的约定）。
Widget aiAvatar({
  bool error = false,
  double radius = 16,
  required String modelName,
}) {
  final name = modelName;
  final asset = _iconAssetFor(name);
  final color = error ? Colors.red[400]! : _colorFor(name);
  final double size = radius * 2;

  // 错误状态：红底 + 错误图标
  if (error) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Icon(
        Icons.error_outline,
        size: radius * 1.0,
        color: Colors.white,
      ),
    );
  }

  // 有品牌 Logo 路径 → ClipOval + Image.asset（加载失败时 errorBuilder 兜底）
  if (asset != null) {
    return ClipOval(
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, err, stack) =>
            _avatarFallback(radius, color, name),
      ),
    );
  }

  // 无品牌 Logo → 纯色 + 首字母
  return _avatarFallback(radius, color, name);
}

/// 品牌 Logo 加载失败或无品牌时的兜底：纯色圆 + 首字母
Widget _avatarFallback(double radius, Color color, String modelName) {
  return CircleAvatar(
    radius: radius,
    backgroundColor: color,
    child: _avatarText(radius, modelName),
  );
}

Widget _avatarText(double radius, String modelName) {
  final label = modelName.isNotEmpty ? modelName[0].toUpperCase() : 'AI';
  return Text(
    label,
    style: TextStyle(
      fontSize: radius * 0.85,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  );
}

String? _iconAssetFor(String modelName) {
  final m = modelName.toLowerCase();
  if (m.contains('doubao') || m.contains('seed') || m.contains('ark')) {
    return 'assets/icons/doubao-color.png';
  }
  if (m.contains('deepseek')) {
    return 'assets/icons/deepseek-color.png';
  }
  if (m.contains('gpt') || m.contains('openai')) {
    return 'assets/icons/openai.png';
  }
  if (m.contains('claude') || m.contains('anthropic')) {
    return 'assets/icons/claude-color.png';
  }
  if (m.contains('gemini')) {
    return 'assets/icons/gemini-color.png';
  }
  if (m.contains('qwen') || m.contains('tongyi')) {
    return 'assets/icons/qwen-color.png';
  }
  if (m.contains('glm') || m.contains('chatglm') || m.contains('zhipu')) {
    return 'assets/icons/zhipu-color.png';
  }
  if (m.contains('moonshot') || m.contains('kimi')) {
    return 'assets/icons/kimi-color.png';
  }
  if (m.contains('google')) {
    return 'assets/icons/google-color.png';
  }
  if (m.contains('iflytek') || m.contains('spark')) {
    return 'assets/icons/iflytekcloud-color.png';
  }
  return null;
}

Color _colorFor(String modelName) {
  final m = modelName.toLowerCase();
  if (m.contains('doubao') || m.contains('seed') || m.contains('ark'))
    return const Color(0xFF3D7A5C);
  if (m.contains('deepseek')) return const Color(0xFF4A6CF7);
  if (m.contains('gpt') || m.contains('openai'))
    return const Color(0xFF10A37F);
  if (m.contains('claude') || m.contains('anthropic'))
    return const Color(0xFFD97757);
  if (m.contains('gemini')) return const Color(0xFF4285F4);
  if (m.contains('qwen') || m.contains('tongyi'))
    return const Color(0xFF6B4CE6);
  if (m.contains('glm') || m.contains('zhipu'))
    return const Color(0xFF5B8DEF);
  if (m.contains('moonshot') || m.contains('kimi'))
    return const Color(0xFF8B5CF6);
  if (m.contains('baidu') || m.contains('ernie'))
    return const Color(0xFF2932E1);
  if (m.contains('google')) return const Color(0xFF4285F4);
  if (m.contains('iflytek') || m.contains('spark'))
    return const Color(0xFF1677FF);
  // 稳定兜底色
  final colors = const [
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF00ACC1),
  ];
  var hash = 0;
  for (var i = 0; i < modelName.length; i++) {
    hash = modelName.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return colors[hash.abs() % colors.length];
}
