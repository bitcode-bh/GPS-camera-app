package com.gpscamera.gps_camera_next

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.style.AbsoluteSizeSpan
import android.text.style.CharacterStyle
import android.text.style.ForegroundColorSpan
import androidx.media3.common.util.Size
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.TextureOverlay
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@UnstableApi
internal object VideoStamp {
    fun export(
        context: Context,
        source: File,
        startedAtMs: Long,
        samples: List<Pair<Long, String>>,
        clock24: Boolean,
        frames: List<Pair<Long, File>>,
        stampRect: List<Float>?,
        quarterTurns: Int,
        result: MethodChannel.Result,
    ) {
        var pendingOutput: File? = null
        try {
            val output = File.createTempFile("stamped_", ".mp4", context.cacheDir)
            pendingOutput = output
            check(output.delete())
            val format = SimpleDateFormat(
                if (clock24) "dd MMM yyyy HH:mm:ss" else "dd MMM yyyy hh:mm:ss a",
                Locale.getDefault(),
            )
            val settings = StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(-1f, -1f)
                .setBackgroundFrameAnchor(-0.94f, -0.94f)
                .build()
            val hiddenSettings = StaticOverlaySettings.Builder().setAlphaScale(0f).build()
            fun hideText(atMs: Long): Boolean {
                val sample = samples.getOrNull(indexAt(samples, atMs))
                val frame = frames.getOrNull(indexAt(frames, atMs))
                return sample?.second == "Stamp disabled" ||
                    (stampRect != null && frame != null && frame.first >= (sample?.first ?: 0L))
            }
            val overlay = object : TextOverlay() {
                private var fontSize = 24
                private var lastSecond = Long.MIN_VALUE
                private var lastSample = -2
                private var lastPicture = false
                private var text = SpannableString("")

                override fun configure(videoSize: Size) {
                    super.configure(videoSize)
                    fontSize = (minOf(videoSize.width, videoSize.height) * 0.032f)
                        .toInt().coerceAtLeast(14)
                }

                override fun getOverlaySettings(presentationTimeUs: Long) =
                    if (hideText(presentationTimeUs / 1000)) hiddenSettings else settings

                override fun getText(presentationTimeUs: Long): SpannableString {
                    val second = presentationTimeUs / 1_000_000
                    val atMs = presentationTimeUs / 1000
                    val index = indexAt(samples, atMs)
                    val picture = hideText(atMs)
                    if (second == lastSecond && index == lastSample && picture == lastPicture) return text
                    lastSecond = second
                    lastSample = index
                    lastPicture = picture
                    val location = samples.getOrNull(index)?.second.orEmpty()
                    if (picture) {
                        // Media3 rasterises even a transparent TextOverlay;
                        // an empty string would create a zero-width bitmap.
                        text = SpannableString(".")
                        return text
                    }
                    val timestamp = format.format(Date(startedAtMs + atMs))
                    text = SpannableString(
                        if (location.isEmpty()) timestamp else "$timestamp\n$location"
                    ).apply {
                        setSpan(AbsoluteSizeSpan(fontSize), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        setSpan(ForegroundColorSpan(Color.WHITE), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        setSpan(object : CharacterStyle() {
                            override fun updateDrawState(paint: TextPaint) {
                                paint.setShadowLayer(1f, 0f, 0.5f, Color.argb(102, 0, 0, 0))
                            }
                        }, 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    }
                    return text
                }
            }
            // The same stamp as a photo: pictures of the on-screen stamp, placed
            // where it sits in the viewfinder. The text stamp is the fallback.
            val stamps: List<TextureOverlay> =
                if (frames.isNotEmpty() && stampRect != null) {
                    listOf(pictureOverlay(frames, samples, stampRect), overlay)
                } else {
                    listOf(overlay)
                }
            val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(source)))
                .setEffects(Effects(emptyList(), videoEffects(quarterTurns, stamps)))
                .build()
            Transformer.Builder(context)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        result.success(output.absolutePath)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        output.delete()
                        result.error("video_stamp", "Could not render the video stamp", null)
                    }
                })
                .build()
                .start(item, output.absolutePath)
        } catch (error: Exception) {
            pendingOutput?.delete()
            result.error("video_stamp", "Could not start the video export", null)
        }
    }

    /// A sideways recording is turned upright first, like a sideways photo,
    /// so the stamp reads level in the landscape video.
    private fun videoEffects(quarterTurns: Int, stamps: List<TextureOverlay>) = buildList {
        val turns = Math.floorMod(quarterTurns, 4)
        if (turns != 0) {
            add(ScaleAndRotateTransformation.Builder().setRotationDegrees(turns * 90f).build())
        }
        add(OverlayEffect(stamps))
    }

    private fun <T> indexAt(items: List<Pair<Long, T>>, atMs: Long): Int {
        val hit = items.binarySearchBy(atMs) { it.first }
        return if (hit >= 0) hit else -hit - 2
    }

    private fun pictureOverlay(
        frames: List<Pair<Long, File>>, samples: List<Pair<Long, String>>, rect: List<Float>
    ): BitmapOverlay {
        val (left, bottom, width) = rect
        val settings = StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(-1f, -1f)
            .setBackgroundFrameAnchor(
                (-1f + 2f * left).coerceIn(-1f, 1f),
                (-1f + 2f * bottom).coerceIn(-1f, 1f),
            )
            .build()
        return object : BitmapOverlay() {
            private var targetWidth = 0
            private var shown = -1
            private var bitmap: Bitmap? = null
            private val empty = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)

            override fun configure(videoSize: Size) {
                super.configure(videoSize)
                targetWidth = (videoSize.width * width).toInt().coerceAtLeast(1)
            }

            override fun getOverlaySettings(presentationTimeUs: Long) = settings

            override fun getBitmap(presentationTimeUs: Long): Bitmap {
                val atMs = presentationTimeUs / 1000
                val index = indexAt(frames, atMs)
                val sample = samples.getOrNull(indexAt(samples, atMs))
                // A missing frame must never extend an older map or remove a
                // newer integrity warning; the text overlay covers this interval.
                if (index < 0 || frames[index].first < (sample?.first ?: 0L)) return empty
                val current = bitmap
                if (index == shown && current != null) return current
                val decoded = BitmapFactory.decodeFile(frames[index].second.absolutePath)
                    ?: throw IllegalStateException("Could not decode video stamp")
                val height = (decoded.height * targetWidth.toFloat() / decoded.width)
                    .toInt().coerceAtLeast(1)
                val scaled = Bitmap.createScaledBitmap(decoded, targetWidth, height, true)
                if (scaled !== decoded) decoded.recycle()
                shown = index
                bitmap = scaled
                return scaled
            }
        }
    }
}
