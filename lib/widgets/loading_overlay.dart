import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  final String message;

  const LoadingOverlay({super.key, this.message = '处理中…'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(77),
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32,
              vertical: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 显示加载遮罩
  static void show(BuildContext context, {String message = '处理中…'}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => LoadingOverlay(message: message),
    );
  }

  /// 隐藏加载遮罩
  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}
