package com.gpscamera.gps_camera_next

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ClipData
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

internal const val ALBUM = "GPS Camera Next"

/** Writes captures into the app's MediaStore album and returns their content URI. */
internal object MediaSaver {
    fun save(
        context: Context, name: String, mime: String, takenMs: Long, write: (java.io.OutputStream) -> Unit,
    ): String {
        val video = mime.startsWith("video/")
        val resolver = context.contentResolver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$ALBUM")
                put(MediaStore.MediaColumns.DATE_TAKEN, takenMs)
                // Hidden from every reader, this app included, until the bytes are complete.
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values) ?: throw java.io.IOException("MediaStore insert failed")
            try {
                (resolver.openOutputStream(uri) ?: throw java.io.IOException("openOutputStream failed")).use(write)
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (error: Exception) {
                runCatching { resolver.delete(uri, null, null) }
                throw error
            }
            return uri.toString()
        }
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), ALBUM)
        dir.mkdirs()
        val file = File(dir, name)
        try {
            file.outputStream().use(write)
        } catch (error: Exception) {
            file.delete()
            throw error
        }
        // Wait for the scan so the caller gets a stable id instead of a path.
        val latch = CountDownLatch(1)
        var scanned: Uri? = null
        MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), arrayOf(mime)) { _, uri ->
            scanned = uri
            latch.countDown()
        }
        latch.await(10, TimeUnit.SECONDS)
        return scanned?.toString() ?: throw java.io.IOException("Media scan failed")
    }
}

/** MediaStore access for the in-app Library: listing, thumbnails, metadata, delete and share. */
internal class MediaLibraryChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val resolver: ContentResolver = activity.contentResolver
    private val main = Handler(Looper.getMainLooper())
    private val workers = Executors.newFixedThreadPool(4)
    private var observer: ContentObserver? = null
    private var pendingAccess: MethodChannel.Result? = null
    private var pendingDelete: Pair<Uri, MethodChannel.Result>? = null

    init {
        MethodChannel(messenger, "com.gpscamera.gps_camera_next/library").setMethodCallHandler(this)
        EventChannel(messenger, "com.gpscamera.gps_camera_next/library_changes").setStreamHandler(this)
    }

    fun dispose() {
        onCancel(null)
        workers.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "ensureAccess") return ensureAccess(result)
        workers.execute {
            try {
                val id = call.argument<Number>("id")?.toLong() ?: 0
                val video = call.argument<String>("kind") == "video"
                val value: Any? = when (call.method) {
                    "list" -> list()
                    "thumbnail" -> thumbnail(id, video, call.argument<Int>("size") ?: 256)
                    "read" -> resolver.openInputStream(uriFor(id, video))?.use(InputStream::readBytes)
                    "location" -> location(id, video)
                    // Unit can't cross the channel; reply with null.
                    "share" -> share(id, video, call.argument<String>("mime")).let { null }
                    "delete" -> return@execute delete(uriFor(id, video), result)
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(value) }
            } catch (error: Exception) {
                main.post { result.error("LIBRARY_FAILED", error.javaClass.simpleName, null) }
            }
        }
    }

    private fun uriFor(id: Long, video: Boolean): Uri = ContentUris.withAppendedId(
        if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id,
    )

    // Before scoped storage the album is a public folder and needs the storage permission.
    private fun ensureAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        ) return result.success("granted")
        if (pendingAccess != null) return result.success("denied")
        pendingAccess = result
        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_ACCESS)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_ACCESS) return false
        val result = pendingAccess ?: return true
        pendingAccess = null
        result.success(
            when {
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED -> "granted"
                activity.shouldShowRequestPermissionRationale(Manifest.permission.WRITE_EXTERNAL_STORAGE) -> "denied"
                else -> "permanentlyDenied"
            }
        )
        return true
    }

    private fun list(): List<Map<String, Any?>> {
        val rows = ArrayList<Map<String, Any?>>()
        val filter = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?" to "${Environment.DIRECTORY_PICTURES}/$ALBUM/"
        } else {
            @Suppress("DEPRECATION")
            "${MediaStore.MediaColumns.DATA} LIKE ?" to "%/${Environment.DIRECTORY_PICTURES}/$ALBUM/%"
        }
        for (video in listOf(false, true)) {
            val columns = arrayOf(
                MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, "datetaken",
                MediaStore.MediaColumns.DATE_ADDED, MediaStore.MediaColumns.DATE_MODIFIED,
                MediaStore.MediaColumns.WIDTH, MediaStore.MediaColumns.HEIGHT,
                MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.MIME_TYPE,
                if (video) "duration" else MediaStore.MediaColumns._ID,
            )
            // Rows still being written are pending and never returned, and empty files are skipped.
            resolver.query(
                if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                columns, "${filter.first} AND ${MediaStore.MediaColumns.SIZE} > 0", arrayOf(filter.second), null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val taken = cursor.getLong(2)
                    rows.add(mapOf(
                        "id" to cursor.getLong(0),
                        "kind" to if (video) "video" else "image",
                        "name" to cursor.getString(1).orEmpty(),
                        "takenMs" to if (taken > 0) taken else cursor.getLong(3) * 1000,
                        "modifiedSeconds" to cursor.getLong(4),
                        "width" to cursor.getInt(5),
                        "height" to cursor.getInt(6),
                        "size" to cursor.getLong(7),
                        "mime" to cursor.getString(8).orEmpty(),
                        "durationMs" to if (video) cursor.getLong(9) else 0L,
                    ))
                }
            } ?: throw java.io.IOException("MediaStore unavailable")
        }
        rows.sortWith(
            compareByDescending<Map<String, Any?>> { it["takenMs"] as Long }.thenByDescending { it["id"] as Long }
        )
        return rows
    }

    private fun thumbnail(id: Long, video: Boolean, size: Int): ByteArray? {
        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Uses the system's cached, orientation-corrected thumbnail when it has one.
            resolver.loadThumbnail(uriFor(id, video), Size(size, size), null)
        } else {
            @Suppress("DEPRECATION")
            if (video) MediaStore.Video.Thumbnails.getThumbnail(
                resolver, id, MediaStore.Video.Thumbnails.MINI_KIND, null,
            ) else MediaStore.Images.Thumbnails.getThumbnail(
                resolver, id, MediaStore.Images.Thumbnails.MINI_KIND, null,
            )
        }
        bitmap ?: return null
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    /** The capture location stored in the file itself, or null. Never the device's position. */
    private fun location(id: Long, video: Boolean): Map<String, Double>? {
        val uri = uriFor(id, video)
        if (video) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(activity, uri)
                val iso6709 = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION) ?: return null
                val match = Regex("""([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)""").find(iso6709) ?: return null
                return mapOf("lat" to match.groupValues[1].toDouble(), "lon" to match.groupValues[2].toDouble())
            } finally {
                retriever.release()
            }
        }
        // The owning app reads its own files unredacted. Others need ACCESS_MEDIA_LOCATION.
        val source = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            activity.checkSelfPermission(Manifest.permission.ACCESS_MEDIA_LOCATION) == PackageManager.PERMISSION_GRANTED
        ) MediaStore.setRequireOriginal(uri) else uri
        val position = FloatArray(2)
        val found = resolver.openInputStream(source)?.use { ExifInterface(it).getLatLong(position) } ?: false
        return if (found) mapOf("lat" to position[0].toDouble(), "lon" to position[1].toDouble()) else null
    }

    private fun share(id: Long, video: Boolean, mime: String?) {
        val uri = uriFor(id, video)
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime?.takeIf { it.isNotEmpty() } ?: if (video) "video/mp4" else "image/jpeg")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newRawUri(null, uri)
        main.post { activity.startActivity(Intent.createChooser(send, null)) }
    }

    private fun delete(uri: Uri, result: MethodChannel.Result) {
        try {
            val deleted = resolver.delete(uri, null, null) > 0 || !exists(uri)
            main.post { result.success(deleted) }
        } catch (error: SecurityException) {
            // Media this install does not own needs the user's consent.
            val sender = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    MediaStore.createDeleteRequest(resolver, listOf(uri)).intentSender
                Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && error is RecoverableSecurityException ->
                    error.userAction.actionIntent.intentSender
                else -> null
            }
            main.post {
                if (sender == null || pendingDelete != null) return@post result.success(false)
                pendingDelete = uri to result
                try {
                    activity.startIntentSenderForResult(sender, REQUEST_DELETE, null, 0, 0, 0)
                } catch (error: Exception) {
                    pendingDelete = null
                    result.success(false)
                }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_DELETE) return false
        val (uri, result) = pendingDelete ?: return true
        pendingDelete = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(false)
        } else workers.execute {
            // Android 11+ deletes on consent. Android 10 only grants access, so delete now.
            val gone = runCatching {
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) resolver.delete(uri, null, null)
                !exists(uri)
            }.getOrDefault(false)
            main.post { result.success(gone) }
        }
        return true
    }

    private fun exists(uri: Uri): Boolean =
        resolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)?.use { it.moveToFirst() } ?: false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        val changes = object : ContentObserver(main) {
            override fun onChange(selfChange: Boolean) = events.success(null)
        }
        observer = changes
        resolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, changes)
        resolver.registerContentObserver(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true, changes)
    }

    override fun onCancel(arguments: Any?) {
        observer?.let(resolver::unregisterContentObserver)
        observer = null
    }

    private companion object {
        const val REQUEST_ACCESS = 4701
        const val REQUEST_DELETE = 4702
    }
}
