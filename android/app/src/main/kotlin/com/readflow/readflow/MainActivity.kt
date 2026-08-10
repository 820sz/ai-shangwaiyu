package com.readflow.readflow

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 自写安装通道:替代 open_filex(它部分路径下不回调 result,
        // 导致 Dart 端 await 永久挂起——用户看到"正在打开安装器"卡死)。
        // 同步返回成功或带错误信息的失败,Dart 端可快速感知并兜底超时。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app/install_apk",
        ).setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("BAD_ARGS", "APK 路径为空", null)
                return@setMethodCallHandler
            }
            try {
                val file = File(path)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "APK 文件不存在: $path", null)
                    return@setMethodCallHandler
                }
                // authority 必须与 AndroidManifest 的 FileProvider 声明一致
                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileProvider.com.crazecoder.openfile",
                    file,
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(intent)
                result.success("ok")
            } catch (e: Exception) {
                result.error("OPEN_FAILED", "打开安装器失败: ${e.message}", null)
            }
        }

        // 分享文本通道(ACTION_SEND + 系统分享面板):文章全文翻译的
        // "保存"出口——用户可存到微信/备忘录/文件管理器。
        // 零新依赖(share_plus 需拉包),自写 20 行原生代码。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app/share_text",
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareText") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val text = call.argument<String>("text")
            if (text.isNullOrEmpty()) {
                result.error("BAD_ARGS", "分享内容为空", null)
                return@setMethodCallHandler
            }
            try {
                val title = call.argument<String>("title") ?: "翻译"
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    putExtra(Intent.EXTRA_SUBJECT, title)
                    putExtra(Intent.EXTRA_TITLE, title)
                }
                val chooser = Intent.createChooser(send, "保存/分享翻译")
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(chooser)
                result.success("ok")
            } catch (e: Exception) {
                result.error("SHARE_FAILED", "打开分享面板失败: ${e.message}", null)
            }
        }
    }
}
