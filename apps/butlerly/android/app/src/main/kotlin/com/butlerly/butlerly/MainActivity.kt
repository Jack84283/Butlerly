package com.butlerly.butlerly

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "butlerly/local_ocr"
    private val ocr = AndroidMlKitOcrRecognizer(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "availability" -> result.success(true)
                    "recognizeText" -> ocr.recognize(call, result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "butlerly/storage_capacity")
            .setMethodCallHandler { call, result ->
                if (call.method != "availableBytes") {
                    result.notImplemented()
                } else {
                    val storagePath = call.argument<String>("path")
                    if (storagePath == null) {
                        result.error("invalid_path", "Storage path required.", null)
                    } else {
                        try {
                            result.success(android.os.StatFs(storagePath).availableBytes)
                        } catch (error: Exception) {
                            result.error("storage_unavailable", "Cannot read free capacity.", null)
                        }
                    }
                }
            }
    }
}
