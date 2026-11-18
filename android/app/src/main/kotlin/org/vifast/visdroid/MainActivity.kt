package org.vifast.visdroid

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity của VisDroid — kênh natives gần như rỗng:
 *  - "visdroid/filesDir": trả về thư mục tệp bền vững của app (thay path_provider)
 *  - "visdroid/prefs": get/set String của SharedPreferences (thay shared_preferences)
 * Tự viết hai channel nhỏ này để không kéo plugin Android nào (path_provider_android /
 * shared_preferences_android dùng build.gradle Groovy cũ, xung đột AGP 9 của Flutter 3.50).
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "visdroid/filesDir")
            .setMethodCallHandler { call, result ->
                if (call.method == "get") {
                    result.success(getFilesDir().absolutePath)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "visdroid/prefs")
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("visdroid", MODE_PRIVATE)
                when (call.method) {
                    "get" -> result.success(prefs.getString(call.argument<String>("key"), null))
                    "set" -> {
                        prefs.edit()
                            .putString(call.argument<String>("key"), call.argument<String>("value"))
                            .apply()
                        result.success(null)
                    }
                    "remove" -> {
                        prefs.edit().remove(call.argument<String>("key")).apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
