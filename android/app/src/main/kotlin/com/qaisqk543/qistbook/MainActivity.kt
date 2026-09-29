package com.qaisqk543.qistbook

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Self Repair → storage health: free bytes on internal storage.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qistbook/storage"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getFreeBytes") {
                try {
                    val stat = StatFs(filesDir.path)
                    result.success(stat.availableBytes)
                } catch (e: Exception) {
                    result.error("ERR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
