package com.butlerly.butlerly

import android.app.Activity
import android.graphics.Bitmap
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
    companion object {
        // Keeps transient OCR bitmaps bounded to roughly 16 MiB at ARGB_8888,
        // including on supported devices with 3–4 GiB of RAM.
        const val MAX_OCR_DIMENSION = 2048
    }

    fun recognize(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("invalid_arguments", "A local image path is required.", mapOf("stage" to "arguments"))
            return
        }
        if (call.argument<String>("sourceKind") == "pdf") {
            result.error("unsupported_source", "PDF OCR is unavailable on Android.", mapOf("stage" to "sourceType"))
            return
        }
        val file = File(path)
        if (!file.isFile) {
            result.error("image_open_failed", "The local image could not be opened.", mapOf("stage" to "imageOpen"))
            return
        }
        val bitmap = decodeBounded(path)
        if (bitmap == null) {
            result.error("image_open_failed", "The local image could not be opened.", mapOf("stage" to "imageDecode"))
            return
        }
        val width = bitmap.width
        val height = bitmap.height
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            // The original evidence file is never modified; this bounded bitmap
            // exists only for the duration of this recognition request.
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { text ->
                    if (text.text.isBlank()) {
                        result.error("no_text", "No readable text was found.", mapOf("stage" to "mlKitRecognition"))
                        bitmap.recycle()
                        recognizer.close()
                        return@addOnSuccessListener
                    }
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
                        "visionObservationCount" to observations.size,
                        "confidenceMinimum" to observations.minOfOrNull { it["confidence"] as Double },
                        "confidenceAverage" to observations.map { it["confidence"] as Double }.average(),
                        "confidenceMaximum" to observations.maxOfOrNull { it["confidence"] as Double },
                        "pixelWidth" to width,
                        "pixelHeight" to height,
                    )
                    result.success(mapOf("text" to text.text, "observations" to observations, "diagnostics" to diagnostics))
                    bitmap.recycle()
                    recognizer.close()
                }
                .addOnFailureListener { error ->
                    result.error("ocr_failed", "Local text recognition failed.", mapOf("stage" to "mlKitRecognition", "type" to error.javaClass.simpleName))
                    bitmap.recycle()
                    recognizer.close()
                }
        } catch (error: Exception) {
            bitmap.recycle()
            recognizer.close()
            result.error("ocr_failed", "Local text recognition failed.", mapOf("stage" to "mlKitSetup", "type" to error.javaClass.simpleName))
        }
    }

    private fun decodeBounded(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sampleSize > MAX_OCR_DIMENSION) {
            sampleSize *= 2
        }
        return BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply {
                inSampleSize = sampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            },
        )
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
