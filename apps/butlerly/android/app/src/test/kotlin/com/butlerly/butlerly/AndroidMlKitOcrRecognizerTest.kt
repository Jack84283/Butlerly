package com.butlerly.butlerly

import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidMlKitOcrRecognizerTest {
    @Test
    fun cameraImageExifOrientationsMapToExpectedRotations() {
        assertEquals(0, AndroidMlKitOcrRecognizer.exifRotationDegrees(ExifInterface.ORIENTATION_NORMAL))
        assertEquals(90, AndroidMlKitOcrRecognizer.exifRotationDegrees(ExifInterface.ORIENTATION_ROTATE_90))
        assertEquals(180, AndroidMlKitOcrRecognizer.exifRotationDegrees(ExifInterface.ORIENTATION_ROTATE_180))
        assertEquals(270, AndroidMlKitOcrRecognizer.exifRotationDegrees(ExifInterface.ORIENTATION_ROTATE_270))
    }

    @Test
    fun mirroredExifOrientationsRemainSafeWithoutAnUnintendedRotation() {
        assertEquals(0, AndroidMlKitOcrRecognizer.exifRotationDegrees(ExifInterface.ORIENTATION_FLIP_HORIZONTAL))
        assertEquals(0, AndroidMlKitOcrRecognizer.exifRotationDegrees(ExifInterface.ORIENTATION_TRANSPOSE))
        assertEquals(0, AndroidMlKitOcrRecognizer.exifRotationDegrees(ExifInterface.ORIENTATION_UNDEFINED))
    }
}
