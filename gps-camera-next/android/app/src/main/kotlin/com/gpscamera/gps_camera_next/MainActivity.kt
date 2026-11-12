package com.gpscamera.gps_camera_next

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.ExifInterface
import io.flutter.plugin.common.StandardMethodCodec
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.camerax.WhiteBalance
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val channel = "com.gpscamera.gps_camera_next/gallery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger, channel, StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()
        ).setMethodCallHandler { call, result ->
                when (call.method) {

                    "listVideos" -> {
                        try {
                            result.success(listVideos())
                        } catch (error: Exception) {
                            result.error("VIDEO_LIBRARY_FAILED", "Could not read saved videos", null)
                        }
                    }

                    "openVideo" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        if (id == null || id <= 0) {
                            result.error("VIDEO_UNAVAILABLE", "Invalid video", null)
                            return@setMethodCallHandler
                        }
                        val uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
                        runOnUiThread {
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "video/mp4")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                result.success(null)
                            } catch (error: Exception) {
                                result.error("VIDEO_UNAVAILABLE", "Could not open the video", null)
                            }
                        }
                    }

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
                            runOnUiThread {
                                VideoStamp.export(applicationContext, File(path), start, samples, clock24, result)
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

                    "photoMetadata" -> {
                        try {
                            val file = File(requireNotNull(call.argument<String>("path")))
                            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            BitmapFactory.decodeFile(file.absolutePath, bounds)
                            check(bounds.outWidth > 0 && bounds.outHeight > 0)
                            val exif = ExifInterface(file.absolutePath)
                            val position = FloatArray(2)
                            val hasLocation = exif.getLatLong(position)
                            result.success(mapOf(
                                "width" to bounds.outWidth,
                                "height" to bounds.outHeight,
                                "modifiedMs" to file.lastModified(),
                                "latitude" to (if (hasLocation) position[0].toDouble() else null),
                                "longitude" to (if (hasLocation) position[1].toDouble() else null),
                            ))
                        } catch (error: Exception) {
                            result.error("photo_metadata", "Could not read photo metadata", null)
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
                                result.success(setPhotoLocation(bytes, lat, lon, call.argument<String>("sourcePath")))
                            } catch (e: Exception) {
                                result.error("EXIF_FAILED", e.message, null)
                            }
                        }
                    }

                    "saveImage" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val name = call.argument<String>("name") ?: "capture.jpg"
                        val album = call.argument<String>("album") ?: "GPS Camera Next"
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
                                val uri = android.net.Uri.parse(ref)
                                val deleted = contentResolver.delete(uri, null, null)
                                if (deleted == 0) {
                                    val stillExists = contentResolver.query(
                                        uri, arrayOf(MediaStore.Images.Media._ID), null, null, null
                                    )?.use { it.moveToFirst() }
                                    if (stillExists != false) {
                                        throw java.io.IOException("Could not verify gallery deletion")
                                    }
                                }
                            } else {
                                val file = File(ref)
                                if (file.exists() && !file.delete()) {
                                    throw java.io.IOException("Could not delete gallery photo")
                                }
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

    private fun listVideos(): List<Map<String, Any>> {
        val columns = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.DATE_ADDED,
        )
        // Gal stores both current and older exports in the Pictures album.
        val folder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${MediaStore.Video.Media.RELATIVE_PATH} = ?" to
                "${Environment.DIRECTORY_PICTURES}/GPS Camera Next/"
        } else {
            "${MediaStore.Video.Media.DATA} LIKE ?" to
                "%/${Environment.DIRECTORY_PICTURES}/GPS Camera Next/%"
        }
        val cursor = checkNotNull(contentResolver.query(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            columns, folder.first, arrayOf(folder.second),
            "${MediaStore.Video.Media.DATE_ADDED} DESC, ${MediaStore.Video.Media._ID} DESC",
        ))
        return cursor.use {
            buildList {
                while (it.moveToNext()) {
                    add(mapOf(
                        "id" to it.getLong(0),
                        "name" to it.getString(1).orEmpty(),
                        "durationMs" to it.getLong(2),
                        "addedSeconds" to it.getLong(3),
                    ))
                }
            }
        }
    }

    private fun setPhotoLocation(
        bytes: ByteArray, lat: Double?, lon: Double?, sourcePath: String?
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
                exif.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
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
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw Exception("openOutputStream failed")
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                runCatching { contentResolver.delete(uri, null, null) }
                throw e
            }
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
