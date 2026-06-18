package com.gpscamera.gps_camera_pro

import android.content.ContentValues
import android.graphics.BitmapFactory
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.graphics.ImageFormat
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val channel = "com.gpscamera.gps_camera_pro/gallery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // Detect back-camera hardware capabilities via Camera2.
                    "detectCapabilities" -> {
                        try {
                            val mgr = getSystemService(CAMERA_SERVICE) as CameraManager
                            var found = false
                            val allCameras = mgr.cameraIdList.map { cameraInfo(mgr, it) }
                            for (id in mgr.cameraIdList) {
                                val chars = mgr.getCameraCharacteristics(id)
                                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                                if (facing != CameraCharacteristics.LENS_FACING_BACK) continue

                                val map = chars.get(
                                    CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP
                                ) ?: continue

                                // All JPEG output sizes, sorted by descending area
                                val jpegSizes = map.getOutputSizes(ImageFormat.JPEG) ?: continue
                                val sizeList = jpegSizes
                                    .sortedByDescending { it.width.toLong() * it.height }
                                    .map { mapOf("w" to it.width, "h" to it.height) }

                                val hasFlash =
                                    chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false

                                val oisModes = chars.get(
                                    CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION
                                )
                                val hasOis = oisModes?.contains(
                                    CameraMetadata.LENS_OPTICAL_STABILIZATION_MODE_ON
                                ) == true

                                val videoStabModes = chars.get(
                                    CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES
                                )
                                val hasEis = videoStabModes?.contains(
                                    CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON
                                ) == true

                                val sceneModes = chars.get(
                                    CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES
                                )
                                val hasHdr =
                                    sceneModes?.contains(CameraMetadata.CONTROL_SCENE_MODE_HDR)
                                        ?: false
                                val hasNight =
                                    sceneModes?.contains(CameraMetadata.CONTROL_SCENE_MODE_NIGHT)
                                        ?: false

                                val rawSizes = map.getOutputSizes(ImageFormat.RAW_SENSOR)
                                val capabilities = chars.get(
                                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES
                                ) ?: intArrayOf()
                                val supportsRaw =
                                    capabilities.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_RAW) &&
                                        rawSizes?.isNotEmpty() == true
                                val manualSensor =
                                    capabilities.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)
                                val manualPostProcessing =
                                    capabilities.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING)

                                val maxZoom =
                                    chars.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM)
                                        ?.toDouble() ?: 8.0
                                val minFocusDistance = chars.get(
                                    CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE
                                )?.toDouble()
                                val manualFocus = (minFocusDistance ?: 0.0) > 0.0
                                val hasMacro = manualFocus && (minFocusDistance ?: 0.0) >= 8.0
                                val isoRange = chars.get(
                                    CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE
                                )
                                val exposureRange = chars.get(
                                    CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE
                                )
                                val evRange = chars.get(
                                    CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE
                                )
                                val evStep = chars.get(
                                    CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP
                                )
                                val awbModes = chars.get(
                                    CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES
                                ) ?: intArrayOf()
                                val fpsRanges = chars.get(
                                    CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES
                                )?.map { "${it.lower}-${it.upper}" } ?: emptyList()
                                val focalLengths = chars.get(
                                    CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS
                                ) ?: floatArrayOf()
                                val lensOptions = buildLensOptions(id, focalLengths)
                                val physicalIds =
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                        chars.physicalCameraIds.toList()
                                    } else {
                                        emptyList()
                                    }

                                result.success(
                                    mapOf(
                                        "resolutions" to sizeList,
                                        "hasFlash" to hasFlash,
                                        "hasOis" to hasOis,
                                        "hasEis" to hasEis,
                                        "hasHdr" to hasHdr,
                                        "hasNight" to hasNight,
                                        "supportsRaw" to supportsRaw,
                                        "manualFocus" to manualFocus,
                                        "manualSensor" to manualSensor,
                                        "kelvinWhiteBalance" to manualPostProcessing,
                                        "hasMacro" to hasMacro,
                                        "maxDigitalZoom" to maxZoom,
                                        "minFocusDistance" to minFocusDistance,
                                        "isoRange" to isoRange?.let {
                                            mapOf("min" to it.lower, "max" to it.upper)
                                        },
                                        "exposureTimeRange" to exposureRange?.let {
                                            mapOf("min" to it.lower, "max" to it.upper)
                                        },
                                        "exposureCompensationRange" to evRange?.let {
                                            mapOf(
                                                "min" to evIndexToEv(it.lower, evStep),
                                                "max" to evIndexToEv(it.upper, evStep),
                                                "step" to rationalToDouble(evStep)
                                            )
                                        },
                                        "whiteBalanceModes" to awbModes.toList(),
                                        "fpsRanges" to fpsRanges,
                                        "lensOptions" to lensOptions,
                                        "physicalCameraIds" to physicalIds,
                                        "cameras" to allCameras,
                                    )
                                )
                                found = true
                                break
                            }
                            if (!found) result.error("NO_CAMERA", "No back camera found", null)
                        } catch (e: Exception) {
                            result.error("DETECT_FAILED", e.message, null)
                        }
                    }

                    // Accept a PNG-encoded image and return JPEG bytes.
                    // Using BitmapFactory to decode avoids the RGBA→ARGB byte-order
                    // mismatch that would occur if we passed raw pixel data directly.
                    "pngToJpeg" -> {
                        val png = call.argument<ByteArray>("png")
                        val quality = call.argument<Int>("quality") ?: 92
                        if (png == null) {
                            result.error("ARGS", "png required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val bitmap = BitmapFactory.decodeByteArray(png, 0, png.size)
                                ?: throw Exception("PNG decode failed")
                            val out = ByteArrayOutputStream()
                            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, quality, out)
                            bitmap.recycle()
                            result.success(out.toByteArray())
                        } catch (e: Exception) {
                            result.error("ENCODE_FAILED", e.message, null)
                        }
                    }

                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "capture.jpg"
                        val album = call.argument<String>("album") ?: "GPS Camera"
                        if (bytes == null) {
                            result.error("ARGS", "bytes required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val ref = saveImage(bytes, name, album)
                            result.success(ref)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    "deleteImage" -> {
                        val ref = call.argument<String>("ref")
                        if (ref == null) {
                            result.error("ARGS", "ref required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            if (ref.startsWith("content://")) {
                                contentResolver.delete(android.net.Uri.parse(ref), null, null)
                            } else {
                                val file = File(ref)
                                if (file.exists()) file.delete()
                                android.media.MediaScannerConnection.scanFile(
                                    this, arrayOf(ref), null, null
                                )
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("DELETE_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // Native Camera2 manual-sensor pipeline (real ISO/shutter/WB/focus).
        val proCam = ProCamera2(
            applicationContext,
            flutterEngine.renderer,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        this.proCam = proCam
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ProCamera2.NS)
            .setMethodCallHandler { call, result -> proCam.handle(call, result) }
    }

    private var proCam: ProCamera2? = null

    override fun onDestroy() {
        proCam?.close()
        super.onDestroy()
    }

    private fun evIndexToEv(index: Int, step: Rational?): Double {
        return index * rationalToDouble(step)
    }

    private fun rationalToDouble(value: Rational?): Double {
        if (value == null || value.denominator == 0) return 0.0
        return value.numerator.toDouble() / value.denominator.toDouble()
    }

    private fun cameraInfo(mgr: CameraManager, id: String): Map<String, Any?> {
        val chars = mgr.getCameraCharacteristics(id)
        val facing = when (chars.get(CameraCharacteristics.LENS_FACING)) {
            CameraCharacteristics.LENS_FACING_BACK -> "back"
            CameraCharacteristics.LENS_FACING_FRONT -> "front"
            CameraCharacteristics.LENS_FACING_EXTERNAL -> "external"
            else -> "unknown"
        }
        val physicalIds =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) chars.physicalCameraIds.toList()
            else emptyList()
        val apertures = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_APERTURES)
        return mapOf(
            "id" to id,
            "facing" to facing,
            "focalLengths" to (chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?.map { it.toDouble() } ?: emptyList()),
            "aperture" to apertures?.firstOrNull()?.toDouble(),
            "sensorOrientation" to chars.get(CameraCharacteristics.SENSOR_ORIENTATION),
            "physicalIds" to physicalIds,
        )
    }

    private fun buildLensOptions(id: String, focalLengths: FloatArray): List<Map<String, Any>> {
        if (focalLengths.isEmpty()) {
            return listOf(
                mapOf(
                    "id" to id,
                    "type" to "main",
                    "focalLength" to 1.0,
                    "zoom" to 1.0,
                )
            )
        }
        val unique = focalLengths
            .map { it.toDouble() }
            .distinctBy { (it * 100.0).toInt() }
            .sorted()
        val mainFocal = unique.minByOrNull { abs(it - 4.3) } ?: unique.first()
        return unique.map { focal ->
            val zoom = if (mainFocal > 0.0) focal / mainFocal else 1.0
            mapOf(
                "id" to "$id:$focal",
                "type" to classifyLens(zoom, focal),
                "focalLength" to focal,
                "zoom" to zoom,
            )
        }
    }

    private fun classifyLens(zoom: Double, focal: Double): String {
        return when {
            zoom < 0.8 -> "ultraWide"
            zoom > 4.0 || focal >= 18.0 -> "periscope"
            zoom > 1.45 -> "telephoto"
            else -> "main"
        }
    }

    // Returns a content:// URI on API 29+ or a file path on older Android.
    private fun saveImage(bytes: ByteArray, name: String, album: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$album")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("MediaStore insert failed")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("openOutputStream failed")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                album
            ).also { it.mkdirs() }
            val file = File(dir, name)
            FileOutputStream(file).use { it.write(bytes) }
            android.media.MediaScannerConnection.scanFile(
                this, arrayOf(file.absolutePath), arrayOf("image/jpeg"), null
            )
            return file.absolutePath
        }
    }
}
