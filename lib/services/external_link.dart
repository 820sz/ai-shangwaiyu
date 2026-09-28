import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 打开外部链接(v2.6)。
///
/// 用户第 8 条:搜索结果"既要有软件内的转述,又要提供原文链接🔗"。
/// 实现上**不引第三方包**(url_launcher 会多一个依赖面),复用项目里已有的
/// 自写通道风格:Android 端 `app/open_url` → `Intent.ACTION_VIEW` 交给系统
/// 浏览器打开;其它平台(桌面/测试)直接返回 false,由调用方给出提示。
///
/// 只接受 http/https —— 防止 `intent://`、`file://` 这类被 AI 编出来的怪协议
/// 把用户带到别的 App 里去。
Future<bool> launchExternalUrl(String url) async {
  final trimmed = url.trim();
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    debugPrint('ReadFlow 拒绝打开非 http(s) 链接: $trimmed');
    return false;
  }
  try {
    const channel = MethodChannel('app/open_url');
    final r = await channel.invokeMethod<String>('openUrl', {'url': trimmed});
    return r == 'ok';
  } catch (e) {
    debugPrint('ReadFlow 打开链接失败: $e');
    return false;
  }
}
