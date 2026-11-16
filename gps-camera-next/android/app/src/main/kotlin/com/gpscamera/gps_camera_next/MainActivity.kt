package com.gpscamera.gps_camera_next

import android.content.Intent
import android.graphics.BitmapFactory
import android.media.ExifInterface
import io.flutter.plugin.common.StandardMethodCodec
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.camerax.WhiteBalance
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val channel = "com.gpscamera.gps_camera_next/gallery"
    private var library: MediaLibraryChannel? = null
    private var platform: PlatformChannel? = null
    private var location: LocationChannel? = null

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        library?.dispose()
        library = null
        platform?.dispose()
        platform = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        if (library?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        if (location?.onRequestPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (library?.onActivityResult(requestCode, resultCode) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        library = MediaLibraryChannel(this, messenger)
        platform = PlatformChannel(this, messenger)
        location = LocationChannel(this, messenger)
        MethodChannel(
            messenger, channel, StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()
        ).setMethodCallHandler { call, result ->
                when (call.method) {

                    "stampVideo" -> {
                        val path = call.argument<String>("path")
                        val start = call.argument<Number>("startedAtMs")?.toLong()
                        if (path == null || start == null || !File(path).isFile) {
                            result.error("video_stamp", "Missing recording", null)
                        } else {
                            val samples = call.argument<List<Map<String, Any>>>("samples").orEmpty()
                                .mapNotNull { row ->
                                    val at = (row["atMs"] as? Number)?.toLong()
                                    val label = row["label"] as? String
                                    if (at == null || label == null) null else at to label
                                }.sortedBy { it.first }
                            val clock24 = call.argument<Boolean>("clock24") ?: false
                            val frames = call.argument<List<Map<String, Any>>>("frames").orEmpty()
                                .mapNotNull { row ->
                                    val at = (row["atMs"] as? Number)?.toLong()
                                    val file = (row["path"] as? String)?.let(::File)
                                    if (at == null || file == null || !file.isFile) null else at to file
                                }.sortedBy { it.first }
                            val rect = call.argument<List<Number>>("stampRect")
                                ?.map { it.toFloat() }?.takeIf { it.size == 3 }
                            val turns = call.argument<Number>("quarterTurns")?.toInt() ?: 0
                            runOnUiThread {
                                VideoStamp.export(
                                    applicationContext, File(path), start, samples, clock24,
                                    frames, rect, turns, result,
                                )
                            }
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

                    "setPhotoLocation" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val lat = call.argument<Double>("latitude")
                        val lon = call.argument<Double>("longitude")
                        if (bytes == null) {
                            result.error("ARGS", "bytes required", null)
                        } else {
                            try {
                                result.success(setPhotoLocation(
                                    bytes, lat, lon, call.argument<String>("sourcePath"),
                                    call.argument<Int>("quarterTurns") ?: 0,
                                    call.argument<String>("locationDescription"),
                                ))
                            } catch (e: Exception) {
                                result.error("EXIF_FAILED", e.message, null)
                            }
                        }
                    }

                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("ARGS", "bytes required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(MediaSaver.save(
                                this, call.argument<String>("name") ?: "capture.jpg", "image/jpeg",
                                call.argument<Number>("takenMs")?.toLong() ?: System.currentTimeMillis(),
                            ) { it.write(bytes) })
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    "saveVideo" -> {
                        val source = call.argument<String>("path")?.let(::File)
                        if (source == null || !source.isFile || source.length() == 0L) {
                            result.error("ARGS", "recording missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(MediaSaver.save(
                                this, call.argument<String>("name") ?: source.name, "video/mp4",
                                call.argument<Number>("takenMs")?.toLong() ?: System.currentTimeMillis(),
                            ) { out -> source.inputStream().use { it.copyTo(out) } })
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        val manager = getSystemService(CAMERA_SERVICE) as CameraManager
        MethodChannel(messenger, "com.gpscamera.gps_camera_next/adjustments")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "features", "setWhiteBalance" -> {
                            val cameraId = requireNotNull(call.argument<String>("camera"))
                            val characteristics = manager.getCameraCharacteristics(cameraId)
                            val cctRange = if (Build.VERSION.SDK_INT >= 36) {
                                characteristics.get(CameraCharacteristics.COLOR_CORRECTION_COLOR_TEMPERATURE_RANGE)
                            } else null
                            val manual = characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                                ?.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING) == true
                            val range = cctRange ?: if (manual) android.util.Range(2500, 9000) else null
                            if (call.method == "features") {
                                result.success(mapOf(
                                    "flash" to (characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true),
                                    "whiteBalanceMin" to range?.lower,
                                    "whiteBalanceMax" to range?.upper,
                                ))
                            } else {
                                val controlId = requireNotNull(call.argument<Number>("control")).toLong()
                                val kelvin = call.argument<Int>("kelvin")
                                require(kelvin == null || range?.contains(kelvin) == true) { "White balance temperature is unavailable" }
                                WhiteBalance.apply(flutterEngine, controlId, kelvin, cctRange != null, result)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("CAMERA_ADJUSTMENT_FAILED", error.message, null)
                }
            }
    }

    private fun setPhotoLocation(
        bytes: ByteArray, lat: Double?, lon: Double?, sourcePath: String?, quarterTurns: Int,
        locationDescription: String?
    ): ByteArray {
        val file = File.createTempFile("gps-exif-", ".jpg", cacheDir)
        try {
            file.writeBytes(bytes)
            val exif = ExifInterface(file.absolutePath)
            if (sourcePath != null) {
                val source = ExifInterface(sourcePath)
                // Keep capture settings while letting the new pixels describe their own size and orientation.
                for (tag in listOf(
                    ExifInterface.TAG_MAKE, ExifInterface.TAG_MODEL,
                    ExifInterface.TAG_DATETIME_ORIGINAL, ExifInterface.TAG_DATETIME_DIGITIZED,
                    ExifInterface.TAG_EXPOSURE_TIME, ExifInterface.TAG_F_NUMBER,
                    ExifInterface.TAG_FOCAL_LENGTH, ExifInterface.TAG_ISO_SPEED_RATINGS,
                    ExifInterface.TAG_FLASH, ExifInterface.TAG_WHITE_BALANCE
                )) {
                    source.getAttribute(tag)?.let { exif.setAttribute(tag, it) }
                }
                // The pixels are stored as framed in portrait. When the phone was held sideways
                // the orientation tag turns them upright without re-encoding.
                exif.setAttribute(ExifInterface.TAG_ORIENTATION, when (((quarterTurns % 4) + 4) % 4) {
                    1 -> ExifInterface.ORIENTATION_ROTATE_270
                    2 -> ExifInterface.ORIENTATION_ROTATE_180
                    3 -> ExifInterface.ORIENTATION_ROTATE_90
                    else -> ExifInterface.ORIENTATION_NORMAL
                }.toString())
            }
            for (tag in listOf(
                ExifInterface.TAG_GPS_LATITUDE, ExifInterface.TAG_GPS_LATITUDE_REF,
                ExifInterface.TAG_GPS_LONGITUDE, ExifInterface.TAG_GPS_LONGITUDE_REF,
                ExifInterface.TAG_GPS_ALTITUDE, ExifInterface.TAG_GPS_ALTITUDE_REF,
                ExifInterface.TAG_GPS_DEST_LATITUDE, ExifInterface.TAG_GPS_DEST_LATITUDE_REF,
                ExifInterface.TAG_GPS_DEST_LONGITUDE, ExifInterface.TAG_GPS_DEST_LONGITUDE_REF
            )) exif.setAttribute(tag, null)

            if (lat != null && lon != null && lat in -90.0..90.0 && lon in -180.0..180.0) {
                exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE, exifCoordinate(lat))
                exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, if (lat < 0) "S" else "N")
                exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE, exifCoordinate(lon))
                exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, if (lon < 0) "W" else "E")
            }
            exif.setAttribute(ExifInterface.TAG_USER_COMMENT, locationDescription)
            exif.saveAttributes()
            return file.readBytes()
        } finally {
            file.delete()
        }
    }

    private fun exifCoordinate(coordinate: Double): String {
        val totalMillis = kotlin.math.round(abs(coordinate) * 3_600_000).toLong()
        val degrees = totalMillis / 3_600_000
        val minutes = (totalMillis / 60_000) % 60
        val seconds = totalMillis % 60_000
        return "$degrees/1,$minutes/1,$seconds/1000"
    }
}
