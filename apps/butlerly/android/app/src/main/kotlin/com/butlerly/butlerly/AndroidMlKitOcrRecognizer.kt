package com.butlerly.butlerly

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.Rect
import androidx.exifinterface.media.ExifInterface
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

        // Keep non-receipt scanning at the preexisting single-pass cost.
        fun recognitionPassLimit(intent: String?): Int = if (intent == "receipt") 4 else 1

        // A recognizer failure is not the same as successfully seeing no text.
        fun terminalRecognitionErrorCode(hadSuccessfulPass: Boolean): String =
            if (hadSuccessfulPass) "no_text" else "ocr_failed"

        data class ExifTransform(
            val rotationDegrees: Int,
            val mirrorX: Boolean,
            val mirrorY: Boolean,
        )

        /** Maps all EXIF camera orientations into an upright bitmap transform. */
        fun exifTransform(orientation: Int): ExifTransform = when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> ExifTransform(0, mirrorX = true, mirrorY = false)
            ExifInterface.ORIENTATION_ROTATE_180 -> ExifTransform(180, mirrorX = false, mirrorY = false)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> ExifTransform(0, mirrorX = false, mirrorY = true)
            // EXIF transpose/transverse are a reflection plus a quarter-turn.
            ExifInterface.ORIENTATION_TRANSPOSE -> ExifTransform(90, mirrorX = true, mirrorY = false)
            ExifInterface.ORIENTATION_ROTATE_90 -> ExifTransform(90, mirrorX = false, mirrorY = false)
            ExifInterface.ORIENTATION_TRANSVERSE -> ExifTransform(270, mirrorX = true, mirrorY = false)
            ExifInterface.ORIENTATION_ROTATE_270 -> ExifTransform(270, mirrorX = false, mirrorY = false)
            else -> ExifTransform(0, mirrorX = false, mirrorY = false)
        }
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
        val orientationTransform = exifTransform(readExifOrientation(path))
        val orientedBitmap = transform(bitmap, orientationTransform)
        if (orientedBitmap !== bitmap) bitmap.recycle()
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val passLimit = recognitionPassLimit(call.argument<String>("intent"))
        var hadSuccessfulPass = false
        var lastFailureType: String? = null
        data class Candidate(val text: Text, val rotation: Int, val score: Double)
        var best: Candidate? = null

        fun finishRecognition() {
            try {
                val chosen = best
                if (chosen == null || chosen.text.text.isBlank()) {
                    val code = terminalRecognitionErrorCode(hadSuccessfulPass)
                    val details = mutableMapOf<String, Any>("stage" to "mlKitRecognition")
                    if (code == "ocr_failed" && lastFailureType != null) {
                        details["type"] = lastFailureType!!
                    }
                    result.error(
                        code,
                        if (code == "no_text") "No readable text was found." else "Local text recognition failed.",
                        details,
                    )
                    return
                }
                val width = if (chosen.rotation % 180 == 0) orientedBitmap.width else orientedBitmap.height
                val height = if (chosen.rotation % 180 == 0) orientedBitmap.height else orientedBitmap.width
                var order = 0
                val observations = chosen.text.textBlocks.flatMap { block ->
                    block.lines.map { line -> observation(line, width, height, order++) }
                }
                val confidences = observations.map { it["confidence"] as Double }
                val diagnostics = mapOf(
                    "sourceKind" to "image",
                    "sourceOpened" to true,
                    "pageCount" to 1,
                    "observationCount" to observations.size,
                    "recognizedLineCount" to observations.count { (it["text"] as String).isNotBlank() },
                    "observationsWithBounds" to observations.count {
                        (it["width"] as Double) > 0 && (it["height"] as Double) > 0
                    },
                    "visionObservationCount" to observations.size,
                    "confidenceMinimum" to confidences.minOrNull(),
                    "confidenceAverage" to confidences.takeIf { it.isNotEmpty() }?.average(),
                    "confidenceMaximum" to confidences.maxOrNull(),
                    "pixelWidth" to width,
                    "pixelHeight" to height,
                    "orientation" to "exif+quarterTurn" + (chosen.rotation / 90),
                )
                result.success(mapOf(
                    "text" to chosen.text.text,
                    "observations" to observations,
                    "diagnostics" to diagnostics,
                ))
            } catch (error: Exception) {
                result.error("ocr_failed", "Local text recognition failed.", mapOf(
                    "stage" to "mlKitResult",
                    "type" to error.javaClass.simpleName,
                ))
            } finally {
                orientedBitmap.recycle()
                recognizer.close()
            }
        }

        // EXIF may say upright even when receipt lettering is sideways. ML
        // Kit applies the requested rotation virtually to the bounded bitmap,
        // so the preserved evidence file and bitmap pixels remain unchanged.
        // Scan other quarter-turns only if the first pass lacks strong receipt
        // evidence. Keep the result with the best readable receipt evidence.
        fun scan(turn: Int) {
            if (turn >= passLimit) {
                finishRecognition()
                return
            }
            val degrees = turn * 90
            try {
                recognizer.process(InputImage.fromBitmap(orientedBitmap, degrees))
                    .addOnSuccessListener { text ->
                        hadSuccessfulPass = true
                        if (text.text.isNotBlank()) {
                            val candidate = Candidate(text, degrees, receiptRecognitionScore(text))
                            if (best == null || candidate.score > best!!.score) best = candidate
                        }
                        if (turn == 0 && hasStrongReceiptEvidence(text)) {
                            finishRecognition()
                        } else {
                            scan(turn + 1)
                        }
                    }
                    .addOnFailureListener { error ->
                        lastFailureType = error.javaClass.simpleName
                        scan(turn + 1)
                    }
            } catch (error: Exception) {
                lastFailureType = error.javaClass.simpleName
                scan(turn + 1)
            }
        }
        scan(0)
    }

    private fun receiptRecognitionScore(text: Text): Double {
        val lines = text.textBlocks.flatMap { it.lines }
        val lower = text.text.lowercase()
        var score = lines.count { line -> line.text.count { it.isLetter() } >= 3 } * 3.0
        score += lines.sumOf { (it.confidence ?: 0f).toDouble() }
        if (Regex("""\b(?:grand\s+)?total\b""").containsMatchIn(lower)) score += 35
        if (Regex("""\bsubtotal\b""").containsMatchIn(lower)) score += 12
        if (Regex("""\b(?:tax|costco|wholesale|transaction details)\b""").containsMatchIn(lower)) score += 10
        if (Regex("""\b\d+[.,]\d{2}\b""").containsMatchIn(lower)) score += 8
        return score
    }

    private fun hasStrongReceiptEvidence(text: Text): Boolean {
        val lines = text.textBlocks.flatMap { it.lines }
        if (lines.size < 5) return false
        val lower = text.text.lowercase()
        val hasAmount = Regex("""\b\d+[.,]\d{2}\b""").containsMatchIn(lower)
        val itemized = lower.contains("total") && lower.contains("subtotal")
        val bankScreenshot = lower.contains("transaction details") ||
            lower.contains("appears on your statement as")
        return hasAmount && (itemized || bankScreenshot)
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

    private fun readExifOrientation(path: String): Int = try {
        ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_UNDEFINED,
        )
    } catch (_: Exception) {
        ExifInterface.ORIENTATION_UNDEFINED
    }

    private fun transform(bitmap: Bitmap, transform: ExifTransform): Bitmap {
        if (transform.rotationDegrees == 0 && !transform.mirrorX && !transform.mirrorY) return bitmap
        val matrix = Matrix().apply {
            setRotate(transform.rotationDegrees.toFloat())
            postScale(
                if (transform.mirrorX) -1f else 1f,
                if (transform.mirrorY) -1f else 1f,
            )
        }
        return Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true,
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
