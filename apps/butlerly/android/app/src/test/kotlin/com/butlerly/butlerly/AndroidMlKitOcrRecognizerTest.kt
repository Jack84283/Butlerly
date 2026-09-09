package com.butlerly.butlerly

import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidMlKitOcrRecognizerTest {
    @Test
    fun cameraImageExifOrientationsMapToExpectedRotations() {
        assertTransform(ExifInterface.ORIENTATION_NORMAL, 0, mirrorX = false, mirrorY = false)
        assertTransform(ExifInterface.ORIENTATION_ROTATE_90, 90, mirrorX = false, mirrorY = false)
        assertTransform(ExifInterface.ORIENTATION_ROTATE_180, 180, mirrorX = false, mirrorY = false)
        assertTransform(ExifInterface.ORIENTATION_ROTATE_270, 270, mirrorX = false, mirrorY = false)
    }

    @Test
    fun mirroredAndDiagonalExifOrientationsApplyRequiredReflection() {
        assertTransform(ExifInterface.ORIENTATION_FLIP_HORIZONTAL, 0, mirrorX = true, mirrorY = false)
        assertTransform(ExifInterface.ORIENTATION_FLIP_VERTICAL, 0, mirrorX = false, mirrorY = true)
        assertTransform(ExifInterface.ORIENTATION_TRANSPOSE, 90, mirrorX = true, mirrorY = false)
        assertTransform(ExifInterface.ORIENTATION_TRANSVERSE, 270, mirrorX = true, mirrorY = false)
    }

    private fun assertTransform(
        orientation: Int,
        rotationDegrees: Int,
        mirrorX: Boolean,
        mirrorY: Boolean,
    ) {
        val transform = AndroidMlKitOcrRecognizer.exifTransform(orientation)
        assertEquals(rotationDegrees, transform.rotationDegrees)
        assertEquals(mirrorX, transform.mirrorX)
        assertEquals(mirrorY, transform.mirrorY)
    }
}
