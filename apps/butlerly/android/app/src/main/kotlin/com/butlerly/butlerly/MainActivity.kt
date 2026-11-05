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
                when (call.method) {
                    "availableBytes", "filesystemId" -> {
                        val storagePath = call.argument<String>("path")
                        if (storagePath == null) {
                            result.error("invalid_path", "Storage path required.", null)
                        } else {
                            try {
                                if (call.method == "availableBytes") {
                                    result.success(android.os.StatFs(storagePath).availableBytes)
                                } else {
                                    result.success(android.system.Os.stat(storagePath).st_dev.toString())
                                }
                            } catch (error: Exception) {
                                result.error("storage_unavailable", "Cannot read filesystem metadata.", null)
                            }
                        }
                    }
                    "publishNoReplace" -> {
                        val source = call.argument<String>("source")
                        val destination = call.argument<String>("destination")
                        if (source == null || destination == null) {
                            result.error("invalid_path", "Source and destination required.", null)
                        } else {
                            try {
                                // POSIX link(2) is atomic and fails if destination exists.
                                android.system.Os.link(source, destination)
                                result.success(null)
                            } catch (error: Exception) {
                                result.error("publish_failed", "Atomic no-replace publication failed.", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
