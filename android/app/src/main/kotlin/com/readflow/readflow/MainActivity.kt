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
    }
}
