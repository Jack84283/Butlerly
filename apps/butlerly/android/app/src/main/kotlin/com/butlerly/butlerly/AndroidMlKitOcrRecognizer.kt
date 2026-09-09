package com.butlerly.butlerly

import android.app.Activity
import android.graphics.BitmapFactory
import android.graphics.Rect
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Android OCR adapter. It accepts only the app's private local image file. */
class AndroidMlKitOcrRecognizer(private val activity: Activity) {
    fun recognize(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("invalid_arguments", "A local image path is required.", mapOf("stage" to "arguments"))
            return
        }
        val file = File(path)
        val bitmap = BitmapFactory.decodeFile(path)
        if (!file.isFile || bitmap == null) {
            result.error("image_open_failed", "The local image could not be opened.", mapOf("stage" to "imageOpen"))
            return
        }
        val width = bitmap.width
        val height = bitmap.height
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            recognizer.process(InputImage.fromFilePath(activity, android.net.Uri.fromFile(file)))
                .addOnSuccessListener { text ->
                    var order = 0
                    val observations = text.textBlocks.flatMap { block ->
                        block.lines.map { line -> observation(line, width, height, order++) }
                    }
                    val diagnostics = mapOf(
                        "sourceKind" to "image",
                        "sourceOpened" to true,
                        "pageCount" to 1,
                        "observationCount" to observations.size,
                        "recognizedLineCount" to observations.count { (it["text"] as String).isNotBlank() },
                        "observationsWithBounds" to observations.count { (it["width"] as Double) > 0 && (it["height"] as Double) > 0 },
                        "pixelWidth" to width,
                        "pixelHeight" to height,
                    )
                    result.success(mapOf("text" to text.text, "observations" to observations, "diagnostics" to diagnostics))
                    recognizer.close()
                }
                .addOnFailureListener { error ->
                    result.error("ocr_failed", "Local text recognition failed.", mapOf("stage" to "mlKitRecognition", "type" to error.javaClass.simpleName))
                    recognizer.close()
                }
        } catch (error: Exception) {
            recognizer.close()
            result.error("ocr_failed", "Local text recognition failed.", mapOf("stage" to "mlKitSetup", "type" to error.javaClass.simpleName))
        }
    }

    private fun observation(line: Text.Line, width: Int, height: Int, order: Int): Map<String, Any> {
        val box = line.boundingBox ?: Rect(0, 0, 0, 0)
        return mapOf(
            "text" to line.text,
            "confidence" to (line.confidence ?: 0f).toDouble(),
            "left" to box.left.toDouble() / width,
            "top" to box.top.toDouble() / height,
            "width" to box.width().toDouble() / width,
            "height" to box.height().toDouble() / height,
            "pageIndex" to 0,
            "order" to order,
        )
    }
}
