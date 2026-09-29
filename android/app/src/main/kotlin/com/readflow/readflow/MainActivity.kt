package com.readflow.readflow

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /// 「从文件导入」的选择器回调结果(v2.7)。同一时刻只允许一个请求在飞。
    private var pendingFileResult: MethodChannel.Result? = null

    companion object {
        private const val PICK_FILE_REQUEST = 4711

        /// 单个文件上限 8MB:纯文本超过这个量级基本不是学习材料,
        /// 而且整包塞进内存再跨通道传回 Dart 会把低端机拖死。
        private const val MAX_FILE_BYTES = 8 * 1024 * 1024
    }

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

        // 打开外部链接通道(ACTION_VIEW):材料中心的"原文链接🔗"用。
        // v2.6 用户要求 —— 搜索结果既要软件内转述、也要能点开原文出处。
        // 同样零新依赖(不引 url_launcher),交给系统浏览器/对应 App 处理。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app/open_url",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openUrl") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url.isNullOrEmpty()) {
                result.error("BAD_ARGS", "链接为空", null)
                return@setMethodCallHandler
            }
            try {
                val view = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(view)
                result.success("ok")
            } catch (e: Exception) {
                result.error("OPEN_URL_FAILED", "打不开这个链接: ${e.message}", null)
            }
        }

        // 文件选择通道(v2.7,用户第 2(4) 条:材料导入要支持"文件")。
        //
        // 为什么自写而不用 file_picker:实测它的 11.0.3 在 AGP 9 下**不 apply Kotlin
        // 插件**(源码是 .kt)—— Kotlin 源根本不编译,构建直接报"找不到符号
        // FilePickerPlugin";退回 10.0.0 又因为它的 compileSdk 写死 34,与
        // flutter_plugin_android_lifecycle 要求的 36 冲突。两个版本都构建不过,
        // 而这段原生代码只需要 SAF 一个 Intent —— 与 app/open_url 同一套写法,零依赖。
        //
        // 走 ACTION_OPEN_DOCUMENT(**不需要任何存储权限**,用户通过系统选择器授权单个文件),
        // 名字取 OpenableColumns.DISPLAY_NAME,内容读成字节回传(Dart 侧收到 Uint8List)。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app/pick_file",
        ).setMethodCallHandler { call, result ->
            if (call.method != "pickFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingFileResult != null) {
                result.error("BUSY", "上一次选择还没结束,请稍候", null)
                return@setMethodCallHandler
            }
            pendingFileResult = result
            try {
                // type 用 */* 而不是 text/*:手机上 .md/.srt/.csv 常被标成
                // application/octet-stream,按 MIME 过滤会让用户"看不到自己的文件"。
                // 扩展名与大小在 Dart 侧校验并给出人话提示。
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                }
                startActivityForResult(intent, PICK_FILE_REQUEST)
            } catch (e: Exception) {
                pendingFileResult = null
                result.error("NO_PICKER", "打不开系统文件选择器: ${e.message}", null)
            }
        }
    }

    @Deprecated("ACTION_OPEN_DOCUMENT 的传统回调写法,兼容所有 Android 版本")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_FILE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingFileResult ?: return
        pendingFileResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            // 用户取消:回 null,Dart 侧按"没选"处理(不是错误)
            result.success(null)
            return
        }
        try {
            val name = displayNameOf(uri) ?: uri.lastPathSegment ?: "未命名文件"
            val bytes = readCapped(uri)
            if (bytes == null) {
                result.error(
                    "TOO_LARGE",
                    "文件超过 ${MAX_FILE_BYTES / 1024 / 1024}MB,建议切成几份再导入",
                    null,
                )
                return
            }
            result.success(mapOf("name" to name, "bytes" to bytes))
        } catch (e: Exception) {
            result.error("READ_FAILED", "读不到这个文件的内容: ${e.message}", null)
        }
    }

    /// 取用户可见的文件名(SAF 的 display name;拿不到返回 null)
    private fun displayNameOf(uri: android.net.Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    /// 读文件内容;超过 [MAX_FILE_BYTES] 返回 null(不抛,由调用方给提示)
    private fun readCapped(uri: android.net.Uri): ByteArray? {
        contentResolver.openInputStream(uri)?.use { input ->
            val out = java.io.ByteArrayOutputStream()
            val chunk = ByteArray(64 * 1024)
            var total = 0
            while (true) {
                val n = input.read(chunk)
                if (n <= 0) break
                total += n
                if (total > MAX_FILE_BYTES) return null
                out.write(chunk, 0, n)
            }
            return out.toByteArray()
        }
        return null
    }
}
